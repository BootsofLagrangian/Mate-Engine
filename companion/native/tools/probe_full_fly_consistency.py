#!/usr/bin/env python3
"""Full-data first-burst response, deterministic reset and graph/eager parity."""
import argparse
import json
import math
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from engine.fly_brain import FullFlyBrain
parser = argparse.ArgumentParser()
parser.add_argument('--data-dir', required=True)
parser.add_argument('--output', type=Path, required=True)
a = parser.parse_args()
b = FullFlyBrain(a.data_dir).load()
rows = []
for duration in [18, 25, 50]:
    for left, right in [(1., 0.), (0., 1.)]:
        for seed in range(3):
            b.seed = seed
            b.reset()
            result = b.step(left, right, duration_ms=duration)
            rows.append(dict(duration=duration, left=left, right=right, seed=seed, result=result))
            print(json.dumps(rows[-1]), flush=True)
b.seed = 0
b.reset(); first = b.step(1., 0., duration_ms=18)
b.reset(); repeated = b.step(1., 0., duration_ms=18)
graph = b._graph
b._graph = None
b.reset(); eager = b.step(1., 0., duration_ms=18)
b._graph = graph
checks = dict(reset_counts_reproducible=first['raw_counts']==repeated['raw_counts'],
              graph_eager_counts_equal=first['raw_counts']==eager['raw_counts'])
# Independent analytic solution for a single subthreshold conductance pulse.
b.reset()
target = b._groups['outputs']['right'][0]
with b.torch.cuda.stream(b._stream):
    b._g[target] = 1.0
b.step(0., 0., duration_ms=1.8)
with b.torch.cuda.stream(b._stream):
    measured_g = float(b._g[target].item())
    measured_v = float(b._v[target].item())
expected_g = math.exp(-1.8/5.0)
expected_v = -52.0 + 5.0/(5.0-20.0)*(math.exp(-1.8/5.0)-math.exp(-1.8/20.0))
checks['exact_subthreshold_solution'] = abs(measured_g-expected_g)<1e-5 and abs(measured_v-expected_v)<1e-4
# One manual presynaptic spike must not arrive before the full delay cycle.
b.reset()
source = b._groups['inputs']['left'][0]
with b.torch.cuda.stream(b._stream):
    b._v[source] = -44.0
b.step(0., 0., duration_ms=1.8)
with b.torch.cuda.stream(b._stream):
    before_arrival = float(b._g[target].item())
b.step(0., 0., duration_ms=1.8)
with b.torch.cuda.stream(b._stream):
    after_arrival = float(b._g[target].item())
checks['synaptic_delay_not_early'] = before_arrival == 0.0
checks['delayed_synapse_arrives'] = after_arrival > 0.0
report = dict(status=b.status(), rows=rows, checks=checks,
              parity=dict(first=first, repeated=repeated, eager=eager))
a.output.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(checks), flush=True)
if not all(checks.values()):
    raise SystemExit(1)
