#!/usr/bin/env python3
"""Analyze actual Windows travel/yaw evidence without changing the recorded run.

Requires numpy. Writes <outputprefix>.json and <outputprefix>.md. Uses fixed,
pre-agreed thresholds, not controller velocity or quantized frame counts alone.
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

import numpy as np

THRESHOLDS = {'actual_speed_px_s_strictly_above': 20, 'speed_window_s': .1,
              'absolute_yawrate_deg_s_strictly_above': 10,
              'minimum_contiguous_s': .25, 'minimum_heading_change_deg': 5}
FORMULA = ('speed=Euclidean displacement of actual window position over trailing100ms '
           'with linear timestamp interpolation / .1; yawrate=absolute unwrapped yaw '
           'delta / actual adjacent sample dt. Runs require every sample above both '
           'thresholds; duration=t_last-t_first; net heading change=abs(yaw_last-yaw_first). '
           'First100ms of each phase excluded.')


def position(value):
    numbers = re.findall(r'-?\d+(?:\.\d+)?', str(value))
    if len(numbers) != 2:
        raise ValueError('Invalid recorded window position: ' + str(value))
    return tuple(float(n) for n in numbers)


def analyze(base):
    report = json.loads((base / 'report.json').read_text())
    with (base / 'frames.csv').open() as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) < 2:
        raise ValueError('At least two CSV samples are required')
    t, x, y, raw_yaw = [np.array([float(r[k]) for r in rows]) for k in ('ms', 'window_x', 'window_y', 'yaw')]
    t /= 1000
    if not all(np.isfinite(a).all() for a in (t, x, y, raw_yaw)) or np.any(np.diff(t) <= 0):
        raise ValueError('Samples must be finite and timestamps strictly increasing')
    yaw = np.degrees(np.unwrap(raw_yaw))
    dt = np.diff(t, prepend=t[0])
    yawrate = np.divide(np.abs(np.diff(yaw, prepend=yaw[0])), dt, out=np.zeros(len(t)), where=dt > 0)
    displ = np.hypot(np.diff(x, prepend=x[0]), np.diff(y, prepend=y[0]))
    rawspeed = np.divide(displ, dt, out=np.zeros(len(t)), where=dt > 0)
    speed = np.hypot(x - np.interp(t - .1, t, x), y - np.interp(t - .1, t, y)) / .1
    snapshot_names = ('source-before.json', 'source-after.json')
    snapshots = [json.loads((base / name).read_text()) if (base / name).is_file() else None for name in snapshot_names]
    before, after = snapshots
    changes = {k: {'before': before.get(k), 'after': after.get(k)}
               for k in sorted(set(before) | set(after)) if before.get(k) != after.get(k)} if all(s is not None for s in snapshots) else {}
    source_complete = all(s is not None for s in snapshots)
    scope = ('Windows development evidence, not final immutable-source acceptance' if changes else
             'Observed Windows run; recorded source hashes unchanged, loaded-build provenance still required' if source_complete else
             'Observed Windows run; source snapshot pair missing, immutable-source attribution unavailable')
    out = {'scope': scope, 'thresholds': THRESHOLDS, 'formula': FORMULA,
           'input_sha256': {f: hashlib.sha256((base / f).read_bytes()).hexdigest()
                            for f in ('report.json', 'frames.csv') + snapshot_names if (base / f).is_file()},
           'checks': len(report['checks']), 'failures': report['failures'],
           'renderer': report.get('renderer'), 'stop_drift_px': report.get('stop_drift_px'),
           'csv_samples': len(rows), 'capture_count': len(report.get('frames', [])),
           'source_snapshot_pair_present': source_complete, 'source_hash_changes': changes, 'trips': [],
           'stationary_pair_phases': list(dict.fromkeys(r['phase'] for r in rows if r['phase'].startswith('pair:'))),
           'phase_selection': 'Exclude loading and explicitly stationary pair: phases; include all other phases irrespective of outcome.'}
    phase_start = np.zeros(len(t))
    for i, row in enumerate(rows):
        phase_start[i] = t[i] if i == 0 or row['phase'] != rows[i - 1]['phase'] else phase_start[i - 1]
    for phase in dict.fromkeys(r['phase'] for r in rows):
        if phase == 'loading' or phase.startswith('pair:'):
            continue
        indices = np.array([i for i, r in enumerate(rows) if r['phase'] == phase])
        valid = (speed > 20) & (yawrate > 10) & (t >= phase_start + .1)
        runs, current = [], []
        for i in indices:
            if current and (not valid[i] or i != current[-1] + 1):
                runs.append(current)
                current = []
            if valid[i]:
                current.append(int(i))
        if current:
            runs.append(current)
        intervals = []
        for run in runs:
            a, b = run[0], run[-1]
            duration, heading = t[b] - t[a], abs(yaw[b] - yaw[a])
            intervals.append({'start_ms': round(t[a] * 1000), 'end_ms': round(t[b] * 1000),
                              'duration_s': round(duration, 4), 'heading_change_deg': round(heading, 4),
                              'window_displacement_px': round(float(np.hypot(x[b] - x[a], y[b] - y[a])), 4),
                              'samples': len(run), 'passes': bool(duration >= .25 and heading >= 5),
                              'maximum_sample_gap_ms': round(float(max(np.diff(t[run]), default=0)) * 1000)})
        out['trips'].append({'phase': phase, 'samples': len(indices),
                            'raw_adjacent_moving_and_turning_samples': int(np.sum((rawspeed[indices] > 20) & (yawrate[indices] > 10))),
                            'trailing_window_moving_and_turning_samples': int(np.sum(valid[indices])),
                            'meaningful_overlap': any(r['passes'] for r in intervals),
                            'qualifying_intervals': [r for r in intervals if r['passes']],
                            'longest_interval': max(intervals, key=lambda r: r['duration_s']) if intervals else None,
                            'all_interval_count': len(intervals)})
    lookup = {int(float(r['ms'])): r for r in rows}
    unmatched, missing, matched = [], [], 0
    for frame in report.get('frames', []):
        row = lookup.get(frame['ms'])
        if row is None:
            missing.append(frame['ms'])
        ok = row is not None and row['phase'] == frame['phase'] and row['state'] == frame['state'] and abs(float(row['yaw']) - frame['yaw']) < 1e-10 and position(frame['window']) == (float(row['window_x']), float(row['window_y']))
        matched += bool(ok)
        if not ok:
            unmatched.append(frame['ms'])
    out['capture_alignment'] = {'exact_same_timestamp_metadata_matches': matched,
                                'total': len(report.get('frames', [])), 'missing_csv_timestamps': missing,
                                'unmatched_metadata_timestamps': unmatched,
                                'save_errors': sum(f['save_error'] != 0 for f in report.get('frames', [])),
                                'files_present': sum((base / f['file']).is_file() for f in report.get('frames', []))}
    stops = [r for r in report.get('transitions', []) if r['phase'] == 'stop_and_settle' and r['state'] == 'settle']
    out['stop_csv_check'] = None
    if stops:
        stop = stops[-1]
        observed = [r for r in rows if float(r['ms']) >= stop['ms'] and r['phase'] == stop['phase']]
        origin = position(stop['window'])
        positions = sorted({(float(r['window_x']), float(r['window_y'])) for r in observed})
        out['stop_csv_check'] = {'start_ms': stop['ms'], 'samples': len(observed), 'unique_window_positions': positions,
                                 'maximum_drift_px': max((float(np.hypot(px - origin[0], py - origin[1])) for px, py in positions), default=None)}
    return out


def markdown(data, base):
    lines = ['# Windows overlap analysis', '', data['scope'] + '.', '',
             f"Input: `{base}`. {data['checks']} checks, {data['failures']} failures; renderer `{data['renderer']}`.", '',
             'Fixed thresholds: actual trailing-100-ms window speed >20 px/s and adjacent-sample absolute yaw rate >10°/s, contiguous duration ≥0.25 s and heading change ≥5°. Loading and explicitly stationary pair: phases excluded; all other phases included regardless of outcome.', '',
             '| Phase | Sustained overlap | Intervals (ms) | Duration / heading / displacement | Raw quantized count |',
             '| --- | --- | --- | --- | --- |']
    for trip in data['trips']:
        intervals = trip['qualifying_intervals']
        spans = '; '.join(f"{r['start_ms']}–{r['end_ms']}" for r in intervals) or 'none'
        values = '; '.join(f"{r['duration_s']:.3f} s / {r['heading_change_deg']:.3f}° / {r['window_displacement_px']:g} px" for r in intervals) or 'none'
        lines.append(f"| {trip['phase']} | {trip['meaningful_overlap']} | {spans} | {values} | {trip['raw_adjacent_moving_and_turning_samples']} |")
    lines += ['', f"Stationary action-pair phases (outside the travel denominator): `{', '.join(data['stationary_pair_phases']) or 'none'}`. Their action checks remain included in the reported check total."]
    align = data['capture_alignment']
    lines += ['', f"Capture/CSV metadata matches: {align['exact_same_timestamp_metadata_matches']}/{align['total']}; image files present {align['files_present']}; save errors {align['save_errors']}.",
              f"Reported stop drift: {data['stop_drift_px']} px. Independently computed stop CSV check: `{json.dumps(data['stop_csv_check'])}`.",
              f"Changed source hashes: `{', '.join(data['source_hash_changes']) or 'none recorded'}`; source snapshot pair present: {data['source_snapshot_pair_present']}.", '',
              'Contiguous means consecutive observed samples, not continuous independent measurement between samples. Raw frame counts are quantization-sensitive and are not acceptance criteria. Own-viewport captures cannot independently establish OS placement. This analyzer checks metadata alignment, not image content. Source disk hashes do not prove which code was loaded or whether hot reload occurred; final build attribution requires separate provenance. See JSON for exact formulas, intervals, sample gaps and input hashes.', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--outputprefix', type=Path, required=True)
    args = parser.parse_args()
    data = analyze(args.input.resolve())
    targets = [Path(str(args.outputprefix) + ext) for ext in ('.json', '.md')]
    protected = {args.input.resolve() / name for name in data['input_sha256']}
    if any(path.resolve() in protected for path in targets):
        raise ValueError('Output cannot overwrite raw input evidence')
    targets[0].parent.mkdir(parents=True, exist_ok=True)
    targets[0].write_text(json.dumps(data, indent=2) + '\n')
    targets[1].write_text(markdown(data, args.input.resolve()))
    print(f"{sum(t['meaningful_overlap'] for t in data['trips'])}/{len(data['trips'])} phases meet meaningful overlap; wrote {targets[0]} and {targets[1]}")


if __name__ == '__main__':
    main()
