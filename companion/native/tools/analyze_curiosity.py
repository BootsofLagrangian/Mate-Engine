#!/usr/bin/env python3
"""Analyze recorded Mate trajectories; never infer native motion from policy replay."""
import argparse
from collections import Counter
import json
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def metrics(rows, native=False):
    points=np.asarray([r['foot_xy' if native else 'foot_px'] for r in rows],float)
    t=np.asarray([r['t_s'] for r in rows],float)
    if len(points)<2: return {'samples':len(points)}
    delta=np.diff(points,axis=0); lengths=np.linalg.norm(delta,axis=1)
    active=np.asarray([r.get('director_active_kind')=='move_to' if native else r.get('moving',False) for r in rows])
    # Navigation-conditioned geometry excludes seated/idle articulation. Retain
    # raw projected-foot path separately; neither is full-body collision proof.
    moving=(active[1:] | active[:-1])
    bins=np.floor(points[:,0]/120).astype(int)
    result={'samples':len(points),'duration_s':float(t[-1]-t[0]),
        'x_span_px':float(np.ptp(points[:,0])),'y_span_px':float(np.ptp(points[:,1])),
        'visited_x_bins_120px':int(len(set(bins))),
        'raw_foot_path_px':float(lengths.sum()),'navigation_foot_path_px':float(lengths[moving].sum()),
        'move_intent_time_fraction':float(np.sum(np.diff(t)*moving)/max(t[-1]-t[0],1e-6)),
        'sample_gap_p99_ms':float(np.percentile(np.diff(t)*1000,99))}
    if native:
        window=np.asarray([r['window_origin'] for r in rows],float)
        result['native_window_path_px']=float(np.linalg.norm(np.diff(window,axis=0),axis=1).sum())
        result['recorded_frame_dt_p99_ms']=float(np.percentile([r['frame_dt_ms'] for r in rows],99))
        result['observed_targets']=sorted(set(r['director_target_id'] for r in rows if r.get('director_active_kind')=='move_to'))
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--policy',type=Path);parser.add_argument('--native',type=Path,nargs='*',default=[]);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    result={'scope':{'policy':'Fixed-speed kinematic replay of production decision policy. No native animation, collisions, monitor APIs or real-time thread scheduling.',
        'native':'Passive Windows execution on the taskbar support. Initial placement only; production selects targets. Sequential unpaired wall-clock runs; cursor/window activity can differ.',
        'circuit':'Reduced fly conditions: 154 FlyWire neurons / 6327 signed edges, engineered rate model. full_connectome native condition: all 138639 supplied neurons / 15091983 signed records, homogeneous LIF on GPU. Both use engineered novelty encoding/action decoding, not biological curiosity.',
        'baseline':'Old idle dispatch cadence; added intermediate reachable destinations shared by all conditions. Novelty versus fly uses the same cadence.',
        'selection':'58-neuron reduction retained as a rejected candidate: nearly silent bilateral calibration reference. 154-neuron graph selected for well-conditioned readouts.',
        'performance':'Recorded frame intervals include all application/render work; they are not attributed solely to the circuit.'}}
    if args.policy:
        data=json.loads(args.policy.read_text());summaries=[]
        for run in data['runs']:
            row=metrics(run['trajectory']);row.update(trial=run['trial'],mode=run['mode'])
            arrivals=[x for x in run['outcomes'] if x['outcome']=='arrived']
            row['arrivals']=len(arrivals);row['nonarrival_outcomes']=len(run['outcomes'])-len(arrivals)
            row['tick_us_p99']=run['tick_us_p99'];row['tick_us_max']=run['tick_us_max'];summaries.append(row)
        result['policy_runs']=summaries
        result['policy_aggregate']={mode:{key:float(np.mean([r[key] for r in summaries if r['mode']==mode])) for key in ['x_span_px','visited_x_bins_120px','navigation_foot_path_px','arrivals','move_intent_time_fraction','tick_us_max']} for mode in ['baseline','curiosity','fly','zero_edges']}
        paired=[]
        for trial in sorted(set(r['trial'] for r in data['runs'])):
            modes={r['mode']:r for r in data['runs'] if r['trial']==trial}
            seq=lambda run:[d['target_id'] for d in run['decisions'] if d.get('target_id')]
            paired.append({'trial':trial,'fly_vs_curiosity_sequence_differs':seq(modes['fly'])!=seq(modes['curiosity']),
                'zero_edges_matches_curiosity':seq(modes['zero_edges'])==seq(modes['curiosity'])})
        result['paired_decision_checks']=paired
        fig,axes=plt.subplots(4,1,figsize=(10,8),sharex=True,sharey=True)
        for ax,mode in zip(axes,['baseline','curiosity','fly','zero_edges']):
            for run in data['runs']:
                if run['mode']!=mode:continue
                rows=run['trajectory'];ax.plot([x['t_s'] for x in rows],[x['foot_px'][0] for x in rows],alpha=.45,lw=1)
            ax.set_ylabel(mode+'\nx (px)');ax.grid(alpha=.2)
        axes[-1].set_xlabel('Simulated time (s)');fig.suptitle('REDUCED circuit policy-only replay: 12 paired starts, fixed 75 px/s; not native motion')
        fig.tight_layout();fig.savefig(args.output/'policy-trajectories.png',dpi=160);plt.close(fig)
    if args.native:
        native=[];fig,axes=plt.subplots(2,1,figsize=(10,7))
        for path in args.native:
            d=json.loads(path.read_text());rows=d.get('trajectory',[])
            if not rows:continue
            m=metrics(rows,True);m.update(mode=d.get('variant',d['mode']),failures=d.get('failures'),source=str(path),fly_diagnostics=d.get('director_final',{}).get('fly_diagnostics',{}))
            if 'navigation_events' in d:
                m['navigation_outcomes']=dict(Counter(e['outcome'] for e in d['navigation_events']))
                m['pointer_transition_count']=len(d.get('pointer_transitions',[]))
                m['navigation_events']=d['navigation_events']
            native.append(m)
            axes[0].plot([r['t_s'] for r in rows],[r['foot_xy'][0] for r in rows],label=d.get('variant',d['mode']))
            axes[1].plot([r['foot_xy'][0] for r in rows],[r['foot_xy'][1] for r in rows],label=d.get('variant',d['mode']),alpha=.8)
        axes[0].set(xlabel='Recorded time (s)',ylabel='Desktop foot x (px)');axes[1].set(xlabel='Desktop foot x (px)',ylabel='Desktop foot y (px)');axes[1].invert_yaxis();axes[1].set_aspect('equal',adjustable='datalim');axes[1].set_title('Taskbar support: horizontal travel; y includes small pose/projection changes')
        for ax in axes:ax.legend();ax.grid(alpha=.2)
        fig.suptitle('Actual Windows taskbar exploration: sequential runs, no injected movement targets');fig.tight_layout();fig.savefig(args.output/'native-trajectories.png',dpi=160);plt.close(fig)
        result['native_runs']=native
    (args.output/'analysis.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
    print(json.dumps({k:v for k,v in result.items() if k in ['policy_aggregate','paired_decision_checks','native_runs']},indent=2))
if __name__=='__main__':main()
