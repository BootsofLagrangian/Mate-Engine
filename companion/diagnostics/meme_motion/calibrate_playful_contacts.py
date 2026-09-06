#!/usr/bin/env python3
"""Record measured source stance travel from the retained raw FK samples.

Intervals were selected after inspecting raw source trajectories and renders.
They are conservative flat portions, not asserted full foot-contact detection.
OLS estimates the constant desktop travel that best matches each source plant;
the runtime stance solver corrects the remaining residual, preserving swing.
"""
import json
import math
from pathlib import Path
from install_playful_sources import SELECTED, COMPANION

LEG_METRES = 0.19608956575394


def main():
    path = COMPANION / 'assets/research/playful-walk/contact-traces.json'
    traces = {entry['name']: entry for entry in json.loads(path.read_text())}
    rows = []
    for name, selected in SELECTED.items():
        trace = traces[selected['source_alias']]
        style = selected['locomotion_style']
        intervals = []
        for side, windows in style['contacts'].items():
            if isinstance(windows[0], (int, float)):
                windows = [windows]
            for start, end in windows:
                samples = []
                for sample in trace['samples'][:-1]:
                    phase = sample['phase']
                    phase = phase if phase >= start else phase + 1
                    if start <= phase <= (end if end > start else end + 1):
                        samples.append((phase, sample['points'][side + 'Foot'][2]))
                mean_phase = sum(t for t, _ in samples) / len(samples)
                mean_z = sum(z for _, z in samples) / len(samples)
                slope = sum((t-mean_phase)*(z-mean_z) for t, z in samples) / sum((t-mean_phase)**2 for t, _ in samples)
                residual = math.sqrt(sum((z-mean_z-slope*(t-mean_phase))**2 for t, z in samples)/len(samples))
                intervals.append({'side': side, 'phase_interval': [start, end], 'samples': len(samples),
                                  'estimated_full_period_travel_m': -slope, 'fit_residual_rms_m': residual})
        period_metres = sum(item['estimated_full_period_travel_m'] for item in intervals)/len(intervals)
        hips = [sample['hips_offset'] for sample in trace['samples'][:-1]]
        center = [sum(p[i] for p in hips)/len(hips) for i in range(3)]
        peak = max(math.sqrt((p[0]-center[0])**2+p[1]**2+(p[2]-center[2])**2) for p in hips)
        rows.append({'name': name, 'source_alias': selected['source_alias'], 'source_duration_s': trace['duration'],
                     'reference_rig': 'Mambo mini', 'rest_leg_length_m': LEG_METRES,
                     'intervals': intervals, 'estimated_full_period_travel_m': period_metres,
                     'estimated_cycle_stride_leg_lengths': period_metres/LEG_METRES,
                     'installed_style': style, 'source_hips_mean_m': center,
                     'source_hips_peak_centered_xz_absolute_y_m': peak,
                     'source_hips_peak_leg_lengths': peak/LEG_METRES})
    report = {'scope': 'Post-inspection source calibration; raw Mambo FK before gait/contact corrections',
              'trace_path': str(path.relative_to(COMPANION)), 'rows': rows}
    target = COMPANION / 'diagnostics/meme_motion/playful-calibration.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(target)


if __name__ == '__main__':
    main()
