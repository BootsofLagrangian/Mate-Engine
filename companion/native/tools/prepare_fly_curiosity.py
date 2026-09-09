#!/usr/bin/env python3
"""Export a real FlyWire v783 PFL3-to-DNa02 induced subgraph for local experiments.

Requires pandas, pyarrow and numpy. Public source files remain local; this does
not reproduce Shiu's whole-brain LIF dynamics or infer desktop curiosity from EM.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import numpy as np
import pandas as pd

BRAIN_COMMIT = '91bdd1e7dcf193f3e7ca5a8933497fcef63b7960'
ANNOTATION_COMMIT = '8587524c1748ce5ef2080822a2fc890fc03bf597'
BRAIN_URL = f'https://raw.githubusercontent.com/philshiu/Drosophila_brain_model/{BRAIN_COMMIT}/Connectivity_783.parquet'
ANNOTATION_URL = f'https://raw.githubusercontent.com/flyconnectome/flywire_annotations/{ANNOTATION_COMMIT}/supplemental_files/Supplemental_file1_neuron_annotations.tsv'
EXPECTED_HASHES = {'https://raw.githubusercontent.com/philshiu/Drosophila_brain_model/91bdd1e7dcf193f3e7ca5a8933497fcef63b7960/Connectivity_783.parquet': 'efeb23fb99098e9c390f6869969b2a121a2ee92c833cfc45ecb2c1d8e1af0347', 'https://raw.githubusercontent.com/flyconnectome/flywire_annotations/8587524c1748ce5ef2080822a2fc890fc03bf597/supplemental_files/Supplemental_file1_neuron_annotations.tsv': '9a4f8b2f843196074431ebd7cd883536afa1be86c8a4ce90970441e8be81d1be'}
WEIGHT = 'Excitatory x Connectivity'

def acquire(path, url):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(url, path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != EXPECTED_HASHES[url]:
        raise ValueError('Pinned source checksum mismatch: ' + str(path))
    return {'url': url, 'sha256': digest, 'bytes': path.stat().st_size}

def export(connectivity, annotations, maximum):
    ann = pd.read_csv(annotations, sep='\t', low_memory=False).set_index('root_id')
    graph = pd.read_parquet(connectivity, columns=['Presynaptic_ID', 'Postsynaptic_ID', WEIGHT])
    inputs = set(map(int, ann.index[ann.cell_type == 'PFL3']))
    outputs = set(map(int, ann.index[ann.cell_type == 'DNa02']))
    if len(outputs) != 2 or not inputs:
        raise ValueError('Expected bilateral DNa02 and identified PFL3 cells')
    outgoing = graph[graph.Presynaptic_ID.isin(inputs)]
    incoming = graph[graph.Postsynaptic_ID.isin(outputs)]
    candidates = set(outgoing.Postsynaptic_ID) & set(incoming.Presynaptic_ID)
    first = outgoing.assign(magnitude=outgoing[WEIGHT].abs()).groupby('Postsynaptic_ID').magnitude.sum()
    second = incoming.assign(magnitude=incoming[WEIGHT].abs()).groupby('Presynaptic_ID').magnitude.sum()
    bridges = sorted(candidates - inputs - outputs, key=lambda i: (-int(first[i])*int(second[i]), int(i)))[:maximum]
    selected = sorted(inputs | outputs | set(map(int, bridges)))
    index = {root: i for i, root in enumerate(selected)}
    sub = graph[graph.Presynaptic_ID.isin(selected) & graph.Postsynaptic_ID.isin(selected)]
    def label(root, key):
        value = ann.at[root, key] if root in ann.index else None
        return str(value) if pd.notna(value) else 'unknown'
    nodes = [{'id': str(root), 'type': label(root, 'cell_type'), 'side': label(root, 'side'),
              'class': label(root, 'super_class'), 'role': 'input_premotor' if root in inputs else 'output_descending' if root in outputs else 'intermediate'} for root in selected]
    groups = lambda roots: {side: [index[root] for root in selected if root in roots and label(root, 'side') == side] for side in ['left', 'right']}
    result = {'version': 1, 'nodes': nodes, 'edges': [[index[int(pre)], index[int(post)], int(weight)] for pre, post, weight in sub.itertuples(index=False, name=None) if weight],
              'inputs': groups(inputs), 'outputs': groups(outputs),
              'goal_input_map': {'left': 'right', 'right': 'left'},
              'goal_input_map_note': 'Engineered goal-direction to anatomical PFL3 group mapping, motivated by measured contralateral DNa02 response; not a sensory-neuron annotation.',
              'readout_calibration_note': 'Measure each descending output under both input groups=1 in the chosen runtime dynamics; normalize each side by its own nonzero reference response to remove bilateral baseline bias.',
              'selection': {'input_type': 'PFL3', 'output_type': 'DNa02', 'available_two_hop_intermediates': len(candidates), 'retained_intermediates': len(bridges),
                            'ranking': 'descending product of absolute PFL3-to-intermediate and intermediate-to-DNa02 weights; root ID breaks ties',
                            'edges': 'all original signed weighted edges induced by selected node IDs; no fabricated edges', 'input_is_sensory': False},
              'interpretation': 'Reduced premotor steering circuit. Novelty/goal encoding, forward drive and rate dynamics are engineered; not a whole fly brain or autonomous biological curiosity.'}
    if any(not result[group][side] for group in ['inputs', 'outputs'] for side in ['left', 'right']):
        raise ValueError('Missing bilateral identities')
    return result

def validate(circuit, steps=160, leak=.2, saturate=False):
    count = len(circuit['nodes'])
    weights = np.zeros((count, count), dtype=np.float64)
    for pre, post, weight in circuit['edges']:
        weights[post, pre] += weight
    # This deliberately differs from the paper: signed, bounded rate recurrence.
    weights *= .85 / np.maximum(np.abs(weights).sum(axis=1), 1)[:, None]
    rows = []
    for left, right in [(0, 0), (1, 0), (0, 1), (1, 1)]:
        state = np.zeros(count)
        drive = np.zeros(count)
        drive[circuit['inputs']['left']] = left
        drive[circuit['inputs']['right']] = right
        for _ in range(steps):
            target = np.maximum(weights @ state + drive, 0)
            if saturate:
                target = np.tanh(target)
            state += leak * (target - state)
        values = {side: float(state[circuit['outputs'][side]].mean()) for side in ['left', 'right']}
        rows.append({'input_left': left, 'input_right': right, 'output': values, 'right_minus_left': values['right'] - values['left']})
    return {'model': f'engineered rate recurrence, target={"tanh(ReLU)" if saturate else "ReLU"}(W_normalized*x+external_drive); x+={leak}*(target-x); abs incoming mass <=0.85',
            'steps': steps, 'leak': leak, 'tanh_saturation': saturate, 'rows': rows, 'bilateral_contrast': rows[1]['right_minus_left']*rows[2]['right_minus_left'] < 0,
            'not_original_lif': True}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-intermediates', type=int, default=128)
    args = parser.parse_args()
    if not 0 <= args.max_intermediates <= 256:
        parser.error('max-intermediates must be 0..256')
    connectivity = args.data_dir/'Connectivity_783.parquet'
    annotations = args.data_dir/'annotations.tsv'
    sources = {'connectivity': acquire(connectivity, BRAIN_URL), 'annotations': acquire(annotations, ANNOTATION_URL)}
    circuit = export(connectivity, annotations, args.max_intermediates)
    circuit['provenance'] = {'sources': sources, 'brain_commit': BRAIN_COMMIT, 'annotation_commit': ANNOTATION_COMMIT,
                             'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                             'licenses': {'brain_repository': 'MIT; retain Philip Shiu and Nico Spiller copyright', 'annotations': 'No repository license declared at pinned revision; retain locally, no redistribution license asserted'},
                             'papers': ['https://doi.org/10.1038/s41586-024-07686-5', 'https://pmc.ncbi.nlm.nih.gov/articles/PMC12279373/']}
    circuit['validation'] = validate(circuit)
    circuit['native_validation'] = validate(circuit, steps=24, leak=.5, saturate=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + '.tmp')
    temporary.write_text(json.dumps(circuit, indent=2)+'\n')
    temporary.replace(args.output)
    print(json.dumps({'nodes': len(circuit['nodes']), 'edges': len(circuit['edges']), 'inputs': circuit['inputs'], 'outputs': circuit['outputs'], 'validation': circuit['validation']}))

if __name__ == '__main__':
    main()
