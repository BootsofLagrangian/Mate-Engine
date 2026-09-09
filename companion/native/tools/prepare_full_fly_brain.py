#!/usr/bin/env python3
"""Install pinned public full-connectome data locally, without bundling it in Mate."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request

BRAIN='91bdd1e7dcf193f3e7ca5a8933497fcef63b7960'
ANNOTATIONS='8587524c1748ce5ef2080822a2fc890fc03bf597'
SOURCES={
    'Completeness_783.csv':f'https://raw.githubusercontent.com/philshiu/Drosophila_brain_model/{BRAIN}/Completeness_783.csv',
    'Connectivity_783.parquet':f'https://raw.githubusercontent.com/philshiu/Drosophila_brain_model/{BRAIN}/Connectivity_783.parquet',
    'annotations.tsv':f'https://raw.githubusercontent.com/flyconnectome/flywire_annotations/{ANNOTATIONS}/supplemental_files/Supplemental_file1_neuron_annotations.tsv',
}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-dir',type=Path,required=True);p.add_argument('--source-dir',type=Path);a=p.parse_args()
    a.output_dir.mkdir(parents=True,exist_ok=True);records={}
    for name,url in SOURCES.items():
        target=a.output_dir/name
        if not target.exists():
            temporary=target.with_suffix(target.suffix+'.tmp')
            candidates=[a.source_dir/name,a.source_dir/'Drosophila_brain_model'/name] if a.source_dir else []
            source=next((x for x in candidates if x.is_file()),None)
            if source:shutil.copyfile(source,temporary)
            else:urllib.request.urlretrieve(url,temporary)
            temporary.replace(target)
        records[name]={'url':url,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    (a.output_dir/'provenance.json').write_text(json.dumps({'files':records,'scope':'all available v783 neurons and signed weighted connections; not a complete biological brain emulation','licenses':{'brain_repository':'MIT, Philip Shiu and Nico Spiller','annotations':'No repository license declared at pinned revision; retain locally; redistribution not asserted'}},indent=2))
    print(json.dumps(records,indent=2))
if __name__=='__main__':main()
