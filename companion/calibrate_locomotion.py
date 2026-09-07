#!/usr/bin/env python3
"""Fit authored gait metadata from raw FK traces and explicitly curated stance windows.

Intervals are conservative source-trajectory observations, not automatic physical
contact labels. This tool does not install assets or modify a motion manifest.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path


def calibrate(trace, intervals, leg):
    fits = []
    for side, interval in intervals.items():
        start, end = interval
        end = end if end > start else end + 1
        samples = [(s['phase'] if s['phase'] >= start else s['phase'] + 1, s)
                   for s in trace['samples'][:-1]]
        samples = [(phase, sample) for phase, sample in samples if start <= phase <= end]
        if len(samples) < 5:
            raise ValueError('Insufficient stance samples')
        mean_phase = sum(t for t, _ in samples) / len(samples)
        points = [sample['points'][side + 'Foot'] for _, sample in samples]
        mean_z = sum(p[2] for p in points) / len(points)
        slope = sum((t - mean_phase) * (s['points'][side + 'Foot'][2] - mean_z)
                    for t, s in samples) / sum((t - mean_phase) ** 2 for t, _ in samples)
        residual = math.sqrt(sum((s['points'][side + 'Foot'][2] - mean_z - slope * (t - mean_phase)) ** 2
                                 for t, s in samples) / len(samples))
        if slope >= 0:
            raise ValueError('Selected stance does not travel backwards along source +Z')
        fits.append({'side': side, 'phase_interval': interval, 'samples': len(samples),
                     'period_travel_m': -slope, 'z_fit_rms_m': residual,
                     'foot_height_range_m': max(p[1] for p in points) - min(p[1] for p in points),
                     'lateral_range_m': max(p[0] for p in points) - min(p[0] for p in points)})
    period = sum(f['period_travel_m'] for f in fits) / len(fits)
    hips = [s['hips_offset'] for s in trace['samples'][:-1]]
    center = [sum(v[i] for v in hips) / len(hips) for i in range(3)]
    peak = max(math.sqrt((v[0] - center[0])**2 + v[1]**2 + (v[2] - center[2])**2) for v in hips)
    # Round upwards and retain a measured 20% margin, avoiding routine source clipping.
    hip_limit = math.ceil(peak / leg * 1.2 * 100) / 100
    if not .1 <= period / leg <= 5 or hip_limit > .5:
        raise ValueError('Measured source does not fit runtime locomotion bounds')
    style = {'version': 1, 'cycle_stride_leg_lengths': period / leg, 'contacts': intervals,
             'contact_blend_phase': .04, 'preserve_source_hip_height': True,
             'hip_translation_limit_leg_lengths': hip_limit}
    return {'name': trace['name'], 'source_path': trace['path'], 'source_sha256': trace['sha256'],
            'duration_s': trace['duration'], 'stance_fits': fits, 'period_travel_m': period,
            'nominal_speed_mps': period / trace['duration'], 'source_hips_mean_m': center,
            'source_hips_centered_xz_absolute_y_peak_m': peak, 'locomotion_style': style}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('intervals', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    data = json.loads(args.trace.read_text())
    selected = json.loads(args.intervals.read_text())
    rows = [calibrate(row, selected[row['name']]['contacts'], data['rest_leg_length_m'])
            for row in data['rows'] if row['name'] in selected]
    result = {'scope': 'Measured source calibration on supplied avatar; no rendered/runtime acceptance',
              'avatar': data['avatar'], 'avatar_sha256': data['avatar_sha256'],
              'rest_leg_length_m': data['rest_leg_length_m'],
              'source_trace_sha256': hashlib.sha256(args.trace.read_bytes()).hexdigest(),
              'selection': selected, 'trace_tool_sha256': data['tool_sha256'],
              'calibration_tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'rows': rows}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    for row in rows:
        print(row['name'], json.dumps(row['locomotion_style']))


if __name__ == '__main__':
    main()
