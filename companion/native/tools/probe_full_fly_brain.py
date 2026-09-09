#!/usr/bin/env python3
"""Bounded full-connectome GPU acceptance/benchmark; saves local JSON evidence."""
import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from engine.fly_brain import FullFlyBrain

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-dir', required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--no-graph', action='store_true')
args = parser.parse_args()
brain = FullFlyBrain(args.data_dir, use_cuda_graph=not args.no_graph).load()
report = {'status': brain.status(), 'trials': []}
print(json.dumps(report['status']), flush=True)
for left, right in [(0., 0.), (1., 0.), (0., 1.), (1., 1.)]:
    brain.reset()
    rows = [brain.step(left, right, duration_ms=50) for _ in range(2)]
    report['trials'].append({'left': left, 'right': right, 'bursts': rows})
    print(json.dumps(report['trials'][-1]), flush=True)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2)+'\n')
