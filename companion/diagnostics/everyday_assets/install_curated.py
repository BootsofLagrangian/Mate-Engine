#!/usr/bin/env python3
"""Install explicitly curated, checksum-pinned local VRMA assets.

Reads selection.json; preserves unrelated catalog entries. Does not download,
modify source files, attach props, or promote unreviewed acquired candidates.
"""
import argparse,hashlib,json,math,os,re,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def atomic_write(path,blob):
 with tempfile.NamedTemporaryFile(dir=path.parent,prefix='.curated-',delete=False) as stream:
  temporary=Path(stream.name);stream.write(blob)
 try:os.replace(temporary,path)
 finally:temporary.unlink(missing_ok=True)
def install(selection_path):
 selection=json.loads(selection_path.read_text());entries=[];prepared=[];seen=set()
 if not isinstance(selection,dict) or not isinstance(selection.get('motions'),list):raise ValueError('Expected motions selection list')
 for item in selection['motions']:
  entry=dict(item['entry']);name=entry.get('name')
  if not isinstance(name,str) or not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,31}',name) or name in seen:raise ValueError('Invalid or duplicate alias')
  seen.add(name)
  if entry.get('path')!=f'assets/motions/{name}.vrma':raise ValueError('Target path must match the alias under assets/motions')
  target=ROOT/entry['path'];resolved=target.resolve()
  if resolved.parent!=ROOT.resolve()/'assets/motions' or resolved.name!=name+'.vrma':raise ValueError('Target escapes motion directory or aliases another file')
  if not isinstance(entry.get('sha256'),str) or not re.fullmatch(r'[0-9a-f]{64}',entry['sha256']):raise ValueError('Expected SHA256')
  duration=entry.get('duration')
  if type(duration) not in (float,int) or not math.isfinite(duration) or duration<=0:raise ValueError('Invalid duration')
  if not isinstance(item.get('source_path'),str):raise ValueError('Expected source path')
  source=(ROOT/item['source_path']).resolve()
  if not source.is_relative_to(ROOT.resolve()) or source.suffix!='.vrma':raise ValueError('Expected local VRMA source')
  blob=source.read_bytes()
  if hashlib.sha256(blob).hexdigest()!=entry['sha256']:raise ValueError('Source checksum mismatch: '+str(source))
  prepared.append((target,blob));entries.append(entry)
 manifest=ROOT/'motion-assets.json';original=manifest.read_bytes();data=json.loads(original);lookup={e['name']:e for e in entries};merged=[]
 for old in data['motions']:merged.append(lookup.pop(old['name'],old))
 merged.extend(lookup.values());data['motions']=merged
 # Catch concurrent writers before replacing. Root coordinates ownership too.
 if manifest.read_bytes()!=original:raise RuntimeError('Catalog changed concurrently; rerun after coordination')
 # All entries, paths, hashes and the existing catalog are validated before
 # the first mutation. A bad later selection cannot partially install earlier ones.
 for target,blob in prepared:
  target.parent.mkdir(parents=True,exist_ok=True)
  atomic_write(target,blob)
 if manifest.read_bytes()!=original:raise RuntimeError('Catalog changed during binary installation; rerun after coordination')
 atomic_write(manifest,(json.dumps(data,indent=2)+'\n').encode())
 print(json.dumps({'installed_selected':len(entries),'catalog_total':len(merged),'names':[e['name'] for e in entries]}))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',type=Path,default=Path(__file__).with_name('selection.json'));a=p.parse_args();install(a.selection)
