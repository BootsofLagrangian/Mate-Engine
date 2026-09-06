"""Summarize recorded spring callbacks without treating a callback as a frame."""
import argparse, collections, json, math
from pathlib import Path

def summarize(r):
    out={'source_hashes_unchanged':r['source_start']==r['source_end'],'callbacks':r['counts'],'paired_mesh_samples':len(r['mesh_samples']),'max_body_input_error':r['max_prephysics_humanoid_pose_error'],'max_world_error':r['max_world_transform_error'],'yaw_range_rad':[min(x['yaw'] for x in r['callbacks']),max(x['yaw'] for x in r['callbacks'])],'phases':{},'scope':'Tail steps per actual callback and net engine frame are separate. Edge/area metrics compare candidate with simultaneously simulated baseline, not an unstretched rest mesh. Sparse Mantle-selected triangles only.'}
    out['callbacks_per_engine_frame']=dict(collections.Counter(collections.Counter((x['side'],x['engine_frame']) for x in r['callbacks']).values()))
    out['engine_delta_counts']=dict(collections.Counter(x.get('engine_delta_s','unobserved') for x in r['callbacks']))
    out['zero_delta_passes']=[{'side':x['side'],'source_frame':x['frame'],'generation':x['generation']} for x in r['callbacks'] if x.get('engine_delta_s')==0]
    for phase in sorted({x['phase'] for x in r['callbacks']}):
        row={}; mm=[x['comparison'] for x in r['mesh_samples'] if x['phase']==phase]
        for side in [0,1]:
            allside=[x for x in r['callbacks'] if x['side']==side];cb=[x for x in allside if x['phase']==phase];ff={x['engine_frame']:x for x in allside};steps=[]
            for f,x in ff.items():
                if x['phase']!=phase or f-1 not in ff or ff[f-1]['generation']!=x['generation']:continue
                for k,v in x['tails'].items():
                    if k in ff[f-1]['tails']:steps.append((math.dist(v,ff[f-1]['tails'][k]),x['frame'],k))
            row['baseline' if side==0 else 'candidate']={'max_per_callback_tail_step_m':max(x['max_tail_step_m'] for x in cb),'max_net_engine_frame_tail_step':max(steps) if steps else None,'max_bone_length_error_m':max(x['length_error_m'] for x in cb),'max_source_deflection_degrees':math.degrees(max(x['max_source_deflection_rad'] for x in cb))}
        row['mesh']={k:fun(x[k] for x in mm) for k,fun in [('max_displacement_m',max),('p95_relative_edge_change',max),('max_relative_edge_change',max),('min_relative_area',min),('opposed_normals',max)]};out['phases'][phase]=row
    return out
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('report',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.write_text(json.dumps(summarize(json.loads(a.report.read_text())),indent=2)+'\n')
