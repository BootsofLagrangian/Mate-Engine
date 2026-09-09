"""Persistent full FlyWire v783 signed-connectome LIF simulation.

Equations/parameters: Shiu & Spiller, MIT-licensed Drosophila_brain_model,
commit 91bdd1e7dcf193f3e7ca5a8933497fcef63b7960/model.py. This implementation
uses exact subthreshold integration and explicit discrete scheduling; it is not
claimed numerically identical to Brian2. PFL3 external stimulation and the
DNa02-to-desktop movement decoder are engineered, not biological curiosity.

No connectome data is distributed with this module. PyTorch, SciPy and PyArrow
are imported only when an explicitly requested full-brain instance loads.
"""
from __future__ import annotations

import csv
import hashlib
import math
from pathlib import Path
import threading
import time


class FullFlyBrain:
    PARAMETERS = dict(rest_mv=-52.0, reset_mv=-52.0, threshold_mv=-45.0,
                      membrane_tau_ms=20.0, synapse_tau_ms=5.0,
                      refractory_ms=2.2, delay_ms=1.8,
                      synapse_weight_mv=0.275, poisson_scale=250.0,
                      maximum_input_hz=150.0)

    def __init__(self, data_dir, device='cuda', dt_ms=0.1, seed=0,
                 use_cuda_graph=True):
        if not math.isfinite(dt_ms) or dt_ms <= 0 or dt_ms > .1:
            raise ValueError('dt_ms must be finite and in (0, 0.1]')
        for period in (1.8, 2.2):
            if not math.isclose(period / dt_ms, round(period / dt_ms), abs_tol=1e-6):
                raise ValueError('dt_ms must exactly divide delay and refractory periods')
        self.data_dir = Path(data_dir)
        self.device_name = device
        self.dt_ms = float(dt_ms)
        self.seed = int(seed)
        self.use_cuda_graph = bool(use_cuda_graph)
        self._lock = threading.RLock()
        self._loaded = False
        self._graph = None
        self._graph_error = None
        self._biological_ms = 0.0
        self._steps = 0
        self._last = None
        self._coverage = {}

    def _locate(self, name):
        for base in (self.data_dir, self.data_dir / 'Drosophila_brain_model'):
            path = base / name
            if path.is_file():
                return path
        raise FileNotFoundError(f'Missing local full-connectome file: {name}')

    def load(self):
        with self._lock:
            if self._loaded:
                return self
            started = time.perf_counter()
            import numpy as np
            import pyarrow.parquet as pq  # Before torch: avoid Arrow initialization conflicts.
            import scipy.sparse as sp
            import torch
            self.torch = torch
            device = torch.device(self.device_name)
            if device.type == 'cuda' and not torch.cuda.is_available():
                raise RuntimeError('CUDA requested but unavailable; no implicit CPU fallback')
            self.device = device
            completeness = self._locate('Completeness_783.csv')
            connectivity = self._locate('Connectivity_783.parquet')
            annotations = self._locate('annotations.tsv')
            with completeness.open(newline='') as file:
                reader = csv.reader(file)
                next(reader)
                ids = [int(row[0]) for row in reader if row]
            if len(ids) != len(set(ids)):
                raise ValueError('Duplicate neuron IDs in completeness CSV')
            lookup = {root: index for index, root in enumerate(ids)}
            groups = {kind: {side: [] for side in ('left', 'right')}
                      for kind in ('inputs', 'outputs')}
            identities = []
            with annotations.open(newline='') as file:
                for row in csv.DictReader(file, delimiter='\t'):
                    kind = {'PFL3': 'inputs', 'DNa02': 'outputs'}.get(row['cell_type'])
                    side = row['side']
                    if kind and side in groups[kind] and int(row['root_id']) in lookup:
                        index = lookup[int(row['root_id'])]
                        groups[kind][side].append(index)
                        identities.append(dict(index=index, id=row['root_id'],
                                               type=row['cell_type'], side=side, role=kind))
            if any(not groups[kind][side] for kind in groups for side in groups[kind]):
                raise ValueError('Missing anatomically identified bilateral PFL3/DNa02 groups')
            columns = ['Presynaptic_ID', 'Postsynaptic_ID', 'Presynaptic_Index',
                       'Postsynaptic_Index', 'Excitatory x Connectivity']
            table = pq.read_table(connectivity, columns=columns)
            arrays = {name: table[name].to_numpy() for name in columns}
            pre = arrays['Presynaptic_Index']
            post = arrays['Postsynaptic_Index']
            roots = np.asarray(ids, dtype=np.int64)
            if pre.min() < 0 or post.min() < 0 or max(pre.max(), post.max()) >= len(ids):
                raise ValueError('Connection index outside complete neuron list')
            if not np.array_equal(roots[pre], arrays['Presynaptic_ID']) or not np.array_equal(roots[post], arrays['Postsynaptic_ID']):
                raise ValueError('Connectivity indices do not match neuron CSV identities')
            signed = arrays['Excitatory x Connectivity']
            if not np.isfinite(signed).all():
                raise ValueError('Non-finite connection weights')
            matrix = sp.coo_matrix((signed.astype(np.float32) * self.PARAMETERS['synapse_weight_mv'],
                                    (post, pre)), shape=(len(ids), len(ids))).tocsr()
            matrix.sum_duplicates()
            self._coverage = dict(neurons=len(ids), source_connection_records=len(pre),
                                  sparse_connections=int(matrix.nnz), positive_records=int((signed > 0).sum()),
                                  negative_records=int((signed < 0).sum()), zero_weight_records=int((signed == 0).sum()),
                                  isolated_neurons=int(len(ids)-len(np.union1d(pre, post))),
                                  all_csv_neurons_included=True, all_source_records_included=True,
                                  subset=False, normalization='none; signed synapse counts times 0.275 mV')
            self._sources = {name: dict(path=str(path), bytes=path.stat().st_size,
                                       sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                             for name, path in [('neurons', completeness), ('connectivity', connectivity), ('annotations', annotations)]}
            self._groups = groups
            self._identities = identities
            self._weights = torch.sparse_csr_tensor(
                torch.from_numpy(matrix.indptr), torch.from_numpy(matrix.indices),
                torch.from_numpy(matrix.data), size=matrix.shape, device=device)
            self._n = len(ids)
            self._delay = round(self.PARAMETERS['delay_ms'] / self.dt_ms)
            self._refractory_ticks = round(self.PARAMETERS['refractory_ms'] / self.dt_ms)
            self._v = torch.full((self._n,), self.PARAMETERS['rest_mv'], device=device, dtype=torch.float32)
            self._g = torch.zeros(self._n, device=device, dtype=torch.float32)
            self._refractory = torch.zeros(self._n, dtype=torch.int32, device=device)
            self._history = torch.zeros((self._delay, self._n), device=device, dtype=torch.float32)
            self._counts = torch.zeros(self._n, device=device, dtype=torch.float32)
            input_indices = groups['inputs']['left'] + groups['inputs']['right']
            self._input_indices = torch.tensor(input_indices, dtype=torch.int64, device=device)
            self._input_rates = torch.zeros(len(input_indices), device=device, dtype=torch.float32)
            self._left_count = len(groups['inputs']['left'])
            self._output_indices = torch.tensor(groups['outputs']['left'] + groups['outputs']['right'], dtype=torch.int64, device=device)
            self._output_left_count = len(groups['outputs']['left'])
            self._generator = torch.Generator(device=device).manual_seed(self.seed)
            self._stream = torch.cuda.Stream(device=device) if device.type == 'cuda' else None
            if self._stream is not None:
                # All CSR/state tensors above were initialized on the caller's
                # current stream. Eager execution needs the same dependency as
                # CUDA graph capture before reset or simulation can use them.
                self._stream.wait_stream(torch.cuda.current_stream(device))
            self._em = math.exp(-self.dt_ms / self.PARAMETERS['membrane_tau_ms'])
            self._eg = math.exp(-self.dt_ms / self.PARAMETERS['synapse_tau_ms'])
            self._coupling = self.PARAMETERS['synapse_tau_ms'] / (self.PARAMETERS['synapse_tau_ms'] - self.PARAMETERS['membrane_tau_ms']) * (self._eg - self._em)
            # One graph spans one full delay-ring revolution; replay preserves
            # persistent delayed spikes without a host-side ring-index mismatch.
            if self._stream is not None and self.use_cuda_graph:
                try:
                    with torch.cuda.stream(self._stream), torch.inference_mode():
                        self._cycle()
                    self._stream.synchronize()
                    graph = torch.cuda.CUDAGraph()
                    graph.register_generator_state(self._generator)
                    with torch.cuda.graph(graph, stream=self._stream), torch.inference_mode():
                        self._cycle()
                    self._graph = graph
                except Exception as exc:
                    self._graph_error = str(exc)[:500]
                    self._graph = None
            self._loaded = True
            self.reset()
            self._load_seconds = time.perf_counter() - started
            self._allocated_bytes = int(torch.cuda.memory_allocated(device)) if device.type == 'cuda' else None
            return self

    def _cycle(self):
        torch = self.torch
        p = self.PARAMETERS
        for ring in range(self._delay):
            active = self._refractory == 0
            voltage = p['rest_mv'] + (self._v - p['rest_mv']) * self._em + self._g * self._coupling
            self._v.copy_(torch.where(active, voltage, self._v))
            self._g.copy_(torch.where(active, self._g * self._eg, self._g))
            spikes = (self._v > p['threshold_mv']) & active
            # Delayed signed synaptic input follows threshold evaluation.
            self._g.add_(torch.mv(self._weights, self._history[ring]))
            self._v.masked_fill_(spikes, p['reset_mv'])
            self._g.masked_fill_(spikes, 0.0)
            self._refractory.sub_(1).clamp_(min=0)
            self._refractory.masked_fill_(spikes, self._refractory_ticks)
            self._refractory.index_fill_(0, self._input_indices, 0)
            injected = (torch.rand(self._input_rates.shape, device=self.device, generator=self._generator, dtype=torch.float32)
                        < self._input_rates * (self.dt_ms / 1000.0)).float()
            self._v.index_add_(0, self._input_indices, injected * (p['poisson_scale'] * p['synapse_weight_mv']))
            self._history[ring].copy_(spikes)
            self._counts.add_(spikes)

    def reset(self):
        with self._lock:
            if not self._loaded:
                return
            torch = self.torch
            context = torch.cuda.stream(self._stream) if self._stream is not None else _NullContext()
            with context, torch.inference_mode():
                self._v.fill_(self.PARAMETERS['rest_mv'])
                self._g.zero_(); self._refractory.zero_(); self._history.zero_(); self._counts.zero_()
                self._input_rates.zero_()
                self._generator.manual_seed(self.seed)
            if self._stream is not None:
                self._stream.synchronize()
            self._biological_ms = 0.0
            self._steps = 0
            self._last = None

    def step(self, left, right, duration_ms=50.0):
        if not all(math.isfinite(float(value)) for value in (left, right, duration_ms)):
            raise ValueError('Non-finite input')
        if not 0 <= left <= 1 or not 0 <= right <= 1 or not 0 < duration_ms <= 100:
            raise ValueError('Inputs must be [0,1], duration_ms in (0,100]')
        with self._lock:
            if not self._loaded:
                raise RuntimeError('Call load() explicitly before step()')
            torch = self.torch
            cycles = math.ceil(duration_ms / (self._delay * self.dt_ms))
            actual_ms = cycles * self._delay * self.dt_ms
            started = time.perf_counter()
            context = torch.cuda.stream(self._stream) if self._stream is not None else _NullContext()
            with context, torch.inference_mode():
                self._counts.zero_()
                self._input_rates[:self._left_count].fill_(left * self.PARAMETERS['maximum_input_hz'])
                self._input_rates[self._left_count:].fill_(right * self.PARAMETERS['maximum_input_hz'])
                for _ in range(cycles):
                    if self._graph is not None:
                        self._graph.replay()
                    else:
                        self._cycle()
                output_counts = self._counts[self._output_indices].cpu().tolist()
                total_spikes = int(self._counts.sum().item())
                firing_neurons = int((self._counts > 0).sum().item())
            elapsed_ms = (time.perf_counter() - started) * 1000
            left_count = int(sum(output_counts[:self._output_left_count]))
            right_count = int(sum(output_counts[self._output_left_count:]))
            lrate = left_count / self._output_left_count * 1000 / actual_ms
            rrate = right_count / (len(output_counts)-self._output_left_count) * 1000 / actual_ms
            self._biological_ms += actual_ms
            self._steps += 1
            result = dict(forward=math.tanh((lrate+rrate)/100), turn=math.tanh((rrate-lrate)/50),
                          raw_counts=dict(left=left_count, right=right_count, total=total_spikes),
                          readout_hz=dict(left=lrate, right=rrate), firing_neurons=firing_neurons,
                          latency_ms=elapsed_ms, biological_ms=actual_ms, requested_ms=duration_ms,
                          cumulative_biological_ms=self._biological_ms, coverage=self._coverage.copy(),
                          input_kind='anatomical PFL3 groups, externally Poisson driven',
                          decoder='engineered: tanh(sum DNa02 Hz /100) forward; tanh(right-left Hz /50) turn',
                          cuda_graph=self._graph is not None)
            self._last = result
            return result

    def status(self):
        with self._lock:
            return dict(loaded=self._loaded, device=self.device_name, dt_ms=self.dt_ms,
                        parameters=self.PARAMETERS.copy(), coverage=self._coverage.copy(),
                        biological_ms=self._biological_ms, decisions=self._steps,
                        cuda_graph=self._graph is not None, cuda_graph_error=self._graph_error,
                        allocated_bytes=getattr(self, '_allocated_bytes', None),
                        allocated_bytes_scope='total process PyTorch CUDA allocation at load; includes cohosted LLM',
                        load_seconds=getattr(self, '_load_seconds', None),
                        identities=getattr(self, '_identities', []), sources=getattr(self, '_sources', {}),
                        model_scope='Full available v783 brain graph; homogeneous LIF; no VNC/body model or learned curiosity',
                        numerical_scope='exact linear subthreshold integration; dt-discretized threshold, fixed delay and refractory; Bernoulli(dt*Hz) Poisson approximation; scheduling not verified against Brian2',
                        source_commit='91bdd1e7dcf193f3e7ca5a8933497fcef63b7960')


class _NullContext:
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False
