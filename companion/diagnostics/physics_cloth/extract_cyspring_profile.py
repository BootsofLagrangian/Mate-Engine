"""Extract a Unity CySpring profile; never modifies a character or assumes solver units.
Run with UnityPy installed: script BUNDLE OUTPUT [--bone-contains Mantle].
"""
import argparse, hashlib, json
from pathlib import Path

def extract(bundle, bone_contains=''):
    import UnityPy
    matches=[]
    for obj in UnityPy.load(str(bundle)).objects:
        if obj.type.name != 'MonoBehaviour': continue
        tree=obj.read_typetree()
        if 'springParam' in tree and 'collisionParam' in tree:
            matches.append((obj.path_id,tree))
    if len(matches)!=1: raise ValueError(f'Expected one CySpring container, got {len(matches)}')
    pathid,tree=matches[0]
    groups=[g for g in tree['springParam'] if bone_contains in g['_boneName']]
    chains=[]
    for g in groups:
        joints=[{k:v for k,v in g.items() if k!='_childElements'}]+g.get('_childElements',[])
        chains.append({'root':g['_boneName'],'joints':joints})
    return {'schema':'mate.cyspring-source/1','source':{'path':str(bundle),'sha256':hashlib.sha256(bundle.read_bytes()).hexdigest(),'path_id':str(pathid)},'selection':{'bone_contains':bone_contains},'chains':chains,'colliders':tree['collisionParam'],'connected_bones':tree.get('ConnectedBoneList',[]),'raw_container':tree,'limitations':['Native solver global rates and time normalization are not established.','Angle limits, inside/capsule colliders and connected panels require a compatible solver.','Raw values are not VRM parameter units.']}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('bundle',type=Path);p.add_argument('output',type=Path);p.add_argument('--bone-contains',default='');a=p.parse_args()
    profile=extract(a.bundle,a.bone_contains);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(profile,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'chains':len(profile['chains']),'joints':sum(len(x['joints']) for x in profile['chains']),'source':profile['source']}))
