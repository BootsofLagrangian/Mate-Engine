#!/usr/bin/env python3
"""Preserve full diagnostic JSON in ignored logs; keep reviewable summaries."""
from pathlib import Path
import gzip,hashlib,json
ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/'companion'
def compact(directory):
    directory=Path(directory)
    for name in ('report.json','transition-analysis.json'):
        path=directory/name
        if not path.exists():continue
        raw=path.read_bytes(); data=json.loads(raw)
        if 'full_evidence' in data or len(raw)<100000:continue
        digest=hashlib.sha256(raw).hexdigest()
        relative=directory.relative_to(BASE/'diagnostics')
        target=BASE/'logs/diagnostic-traces'/relative/(path.stem+'.full.'+digest[:12]+'.json.gz')
        target.parent.mkdir(parents=True,exist_ok=True)
        with gzip.open(target,'wb') as stream:stream.write(raw)
        data['full_evidence']={'repo_relative_path':str(target.relative_to(ROOT)),
            'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
            'uncompressed_sha256':digest,'uncompressed_bytes':len(raw)}
        if name=='report.json':
            data['epoch_count']=len(data.pop('epochs',[]))
            for event in data.get('events',[]):
                if 'boundaries' in event:event['boundary_count']=len(event.pop('boundaries'))
        else:
            data['support_epoch_count']=len(data.pop('support_epochs',[]))
            boundaries=data.pop('boundaries',[]);data['boundary_count']=len(boundaries)
            data['selected_boundaries']=sorted(boundaries,key=lambda b:max(j['boundary_velocity_change_deg_s'] for j in b['joints'].values()),reverse=True)[:4]
            data['boundary_selection']='Four greatest joint angular-velocity vector changes; all boundaries retained in full_evidence.'
        path.write_text(json.dumps(data,indent=2)+'\n')
if __name__=='__main__':
    import sys
    for argument in sys.argv[1:]:compact(Path(argument).resolve())
