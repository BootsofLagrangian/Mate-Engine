#!/usr/bin/env python3
"""Summarize unfiltered main-scene transition traces; does not declare naturalness."""
import argparse
import gzip
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('directory', type=Path)
args = parser.parse_args()
path = args.directory / 'joints.jsonl'
if not path.exists():
    path = args.directory / 'joints.jsonl.gz'
if not path.exists() and (args.directory/'trace_files.json').exists():
    entries = json.loads((args.directory/'trace_files.json').read_text())
    entry = next(x for x in entries if x['original_name'] in ('joints.jsonl', 'joints.jsonl.gz'))
    path = Path(__file__).resolve().parents[3]/entry['repo_relative_path']
with (gzip.open(path, 'rt') if path.suffix == '.gz' else path.open()) as stream:
    frames = [json.loads(line) for line in stream]

def distance(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))

boundaries = []
for i, row in enumerate(frames):
    if not row['boundary'] or row['scenario'] == 'initial_grounding' or i == 0:
        continue
    previous = frames[i-1]
    window = [x for x in frames[max(0, i-4):i+8]
              if row['time']-.05 <= x['time'] <= row['time']+.10]
    joints = {}
    for name in row['joints']:
        before = previous['joints'][name]
        after = row['joints'][name]
        joints[name] = {
            'before_speed_deg_s': before['speed_deg_s'],
            'after_speed_deg_s': after['speed_deg_s'],
            'boundary_velocity_change_deg_s': distance(before['velocity'], after['velocity']),
            'boundary_step_px': after['step_px'],
            'window_peak_step_px': max(x['joints'][name]['step_px'] for x in window),
            'window_peak_speed_deg_s': max(x['joints'][name]['speed_deg_s'] for x in window),
            'window_peak_acceleration_deg_s2': max(x['joints'][name]['acceleration_deg_s2'] for x in window),
        }
    boundaries.append({'time': row['time'], 'scenario': row['scenario'],
                       'from': [previous['state'], previous['gesture'], previous['turn_active'], previous['gait_driven']],
                       'to': [row['state'], row['gesture'], row['turn_active'], row['gait_driven']],
                       'joints': joints})

epochs, active = [], {}
support_frames = 0
unsupported_frames = 0
for row in frames:
    if row['scenario'] == 'initial_grounding':
        continue
    any_support = False
    for side in ('left', 'right'):
        contact = row.get('contact', {}).get(side, {})
        owners = []
        if contact.get('gait_stance') and contact.get('gait_weight', 0) >= .999:
            owners.append('gait')
        if contact.get('turn_stance'):
            owners.append('turn')
        if contact.get('ambient_weight', 0) >= .999:
            owners.append('ambient')
        if owners:
            any_support = True
            point = row['joints'][side+'Foot']['desktop']
            sole = contact['sole_desktop']
            if side not in active:
                active[side] = {'side': side, 'start': row['time'], 'point': point, 'sole': sole,
                                'frames': 0, 'max_ankle_drift_px': 0, 'max_sole_drift_px': 0, 'owners': [],
                                'world_point': row['joints'][side+'Foot'].get('world_desktop'),
                                'world_sole': contact.get('sole_world_desktop'), 'max_world_drift_m': 0.,
                                'max_world_drift_equivalent_px': 0.}
            epoch = active[side]
            epoch['frames'] += 1
            epoch['end'] = row['time']
            epoch['max_ankle_drift_px'] = max(epoch['max_ankle_drift_px'], distance(point, epoch['point']))
            epoch['max_sole_drift_px'] = max(epoch['max_sole_drift_px'], distance(sole, epoch['sole']))
            if epoch['world_point'] is not None:
                world_drift = max(distance(row['joints'][side+'Foot']['world_desktop'], epoch['world_point']),
                                  distance(contact['sole_world_desktop'], epoch['world_sole']))
                epoch['max_world_drift_m'] = max(epoch['max_world_drift_m'], world_drift)
                epoch['max_world_drift_equivalent_px'] = max(epoch['max_world_drift_equivalent_px'], world_drift*row['pixels_per_metre'])
            for owner in owners:
                if owner not in epoch['owners']:
                    epoch['owners'].append(owner)
        elif side in active:
            epochs.append(active.pop(side))
    support_frames += any_support
    unsupported_frames += not any_support

epochs.extend(active.values())
# Use a short committed-position interval to avoid classifying every zero-pixel
# quantized frame as a stop. Raw one-frame qualifying duration is retained too.
overlap = {}
left = 0
for i, row in enumerate(frames):
    stage = row['scenario']
    if stage not in ('journey_0', 'journey_1', 'journey_2', 'before_midwalk_reversal', 'midwalk_reversal'):
        continue
    cell = overlap.setdefault(stage, {'raw_qualifying_seconds': 0., 'rolling_qualifying_seconds': 0.,
                                     'longest_interval_seconds': 0., 'longest_interval_heading_degrees': 0.,
                                     'current_seconds': 0., 'current_heading': 0., 'peak_rolling_speed_px_s': 0.})
    if i == 0:
        continue
    previous = frames[i-1]
    while left+1 < i and frames[left+1]['time'] <= row['time']-.1:
        left += 1
    elapsed = row['time']-frames[left]['time']
    rolling_speed = distance([row['origin_x'], row['origin_y']],
                             [frames[left]['origin_x'], frames[left]['origin_y']])/max(elapsed, 1e-8)
    raw_speed = distance([row['origin_x'], row['origin_y']],
                         [previous['origin_x'], previous['origin_y']])/row['dt']
    yaw_change = abs((row['heading']-previous['heading']+180)%360-180)
    yaw_speed = yaw_change/row['dt']
    cell['peak_rolling_speed_px_s'] = max(cell['peak_rolling_speed_px_s'], rolling_speed)
    if raw_speed > 20 and yaw_speed > 10:
        cell['raw_qualifying_seconds'] += row['dt']
    if rolling_speed > 20 and yaw_speed > 10:
        cell['rolling_qualifying_seconds'] += row['dt']
        cell['current_seconds'] += row['dt']
        cell['current_heading'] += yaw_change
        if cell['current_seconds'] > cell['longest_interval_seconds']:
            cell['longest_interval_seconds'] = cell['current_seconds']
            cell['longest_interval_heading_degrees'] = cell['current_heading']
    else:
        cell['current_seconds'] = cell['current_heading'] = 0.
for cell in overlap.values():
    cell.pop('current_seconds')
    cell.pop('current_heading')
    cell['passes_prospective_overlap'] = cell['longest_interval_seconds'] >= .25 and cell['longest_interval_heading_degrees'] >= 5.

# Diagnostic selection, not a new pass threshold: locate held→step→held arm
# motion inside an uninterrupted walk for review of quantized-distance phase.
isolated_arm_steps = []
for i in range(1, len(frames)-1):
    before, row, after = frames[i-1:i+2]
    if any(x['state'] != 'walk' for x in (before, row, after)):
        continue
    for bone in ('leftUpperArm','rightUpperArm','leftHand','rightHand'):
        speeds = [x['joints'][bone]['speed_deg_s'] for x in (before, row, after)]
        if speeds[0] < .5 and speeds[2] < .5 and speeds[1] > 30.:
            isolated_arm_steps.append({'time':row['time'],'scenario':row['scenario'],
                'joint':bone,'speeds_deg_s':speeds,'step_degrees':speeds[1]*row['dt'],
                'phase':[x['gait_phase'] for x in (before,row,after)],
                'origin_x':[x['origin_x'] for x in (before,row,after)]})

# Established authored walk excludes its initial half-second acquisition. This
# is an explicit descriptive posture selection, not a whole-scene head gate.
posture_rows = []
previous_gesture, gesture_started = None, 0.
for row in frames:
    if row['gesture'] != previous_gesture:
        previous_gesture, gesture_started = row['gesture'], row['time']
    if row['gesture'] == 'uma_walk' and row['state'] == 'walk' and row['time']-gesture_started >= .5 and 'rest_relative_down_pitch_deg' in row['joints']['head']:
        posture_rows.append(row)
walking_posture = {'scope':'Actual final world head forward pitch relative to humanoid rest; positive down. Statewalk+uma_walk, at least0.5s in the continuously observed gesture-name run; initial acquisition excluded explicitly.', 'frames':len(posture_rows)}
if posture_rows:
    pitches = [r['joints']['head']['rest_relative_down_pitch_deg'] for r in posture_rows]
    walking_posture.update(min_pitch_deg=min(pitches),max_pitch_deg=max(pitches),mean_pitch_deg=sum(pitches)/len(pitches),hips_offset_ranges=[[min(r['hips_offset'][i] for r in posture_rows),max(r['hips_offset'][i] for r in posture_rows)] for i in range(3)])

# Both timeline diagnostics and observed joint motion are retained. Quaternion
# motion here is descriptive, not an attribution experiment against no-B control.
gesture_pairs = {}
for row in frames:
    if not row['scenario'].startswith('pair_') or row['scenario'].endswith('_release'):
        continue
    cell = gesture_pairs.setdefault(row['scenario'], {'live_overlap_frames': 0,
        'live_overlap_seconds': 0., 'head_peak_speed_deg_s': 0.,
        'right_hand_peak_speed_deg_s': 0., 'all_frame_peak_acceleration_deg_s2': 0.})
    d = row.get('overlap', {})
    if d.get('incoming') and d.get('outgoing'):
        cell['live_overlap_frames'] += 1
        cell['live_overlap_seconds'] += row['dt']
        cell['head_peak_speed_deg_s'] = max(cell['head_peak_speed_deg_s'], row['joints']['head']['speed_deg_s'])
        cell['right_hand_peak_speed_deg_s'] = max(cell['right_hand_peak_speed_deg_s'], row['joints']['rightHand']['speed_deg_s'])
    cell['all_frame_peak_acceleration_deg_s2'] = max(cell['all_frame_peak_acceleration_deg_s2'],
        max(j['acceleration_deg_s2'] for j in row['joints'].values()))

summary = {'scope': 'Unfiltered actual-main joint boundaries; desktop projected contacts include window origin. No biological smoothness verdict.',
           'frames': len(frames), 'walking_posture':walking_posture, 'isolated_arm_steps_diagnostic': isolated_arm_steps, 'gesture_pairs': gesture_pairs, 'concurrent_turn_travel': overlap, 'boundaries': boundaries, 'support_epochs': epochs,
           'support_frames': support_frames, 'unsupported_or_blending_frames': unsupported_frames,
           'contact_metadata_present': any('contact' in x for x in frames),
           'world_contact_metadata_present': any('world_desktop' in x['joints']['leftFoot'] for x in frames),
           'max_claimed_world_support_drift_m': max((e['max_world_drift_m'] for e in epochs if e['world_point'] is not None), default=None),
           'max_claimed_world_support_drift_equivalent_px': max((e['max_world_drift_equivalent_px'] for e in epochs if e['world_point'] is not None), default=None),
           'max_claimed_support_drift_px': max((max(e['max_ankle_drift_px'], e['max_sole_drift_px']) for e in epochs), default=None)}
(args.directory / 'transition-analysis.json').write_text(json.dumps(summary, indent=2))
print(json.dumps({k:v for k,v in summary.items() if k not in ('boundaries', 'support_epochs')}, indent=2))
