"""Optional full-connectome service. Lazy GPU loading; one bounded inference at a time."""
import math
import os
import re
import threading
import time
from pathlib import Path

SESSION = re.compile(r'^[A-Za-z0-9:_-]{1,96}$')

class BrainUnavailable(RuntimeError):
    pass

class FullBrainService:
    def __init__(self, root, factory=None):
        self.data_dir = Path(os.getenv('MATE_FLY_BRAIN_DATA_DIR', str(Path(root)/'user-data'/'fly-brain')))
        self.factory = factory
        self.model = None
        self.loading = False
        self.error = ''
        self._load_lock = threading.Lock()
        self._step_lock = threading.Lock()
        self._owner = None
        self._last_sequence = -1
        self.last = {}
        self._generations = {}
        self._sequences = {}
        self._status = {}

    def status(self):
        return {'available': self.data_dir.is_dir() or self.factory is not None,
                'loaded': self.model is not None, 'loading': self.loading,
                'error': self.error, 'scope': 'full_available_connectome_gpu_lif',
                'model': dict(self._status), 'last': dict(self.last)}

    def warmup(self):
        with self._load_lock:
            if self.model is not None or self.loading:
                return self.status()
            if not self.data_dir.is_dir() and self.factory is None:
                self.error = 'Full connectome data is not installed'
                return self.status()
            self.loading = True
            self.error = ''
        def load():
            try:
                if self.factory is None:
                    from .fly_brain import FullFlyBrain
                    model = FullFlyBrain(self.data_dir, device='cuda')
                    model.load()
                else:
                    model = self.factory(self.data_dir)
                self._status = model.status()
                self.model = model
            except Exception as exc:
                self.error = f'{type(exc).__name__}: {exc}'[:500]
            finally:
                self.loading = False
        threading.Thread(target=load, daemon=True, name='full-fly-brain-load').start()
        return self.status()

    def step(self, payload):
        session = payload.get('session_id')
        generation = payload.get('generation')
        sequence = payload.get('sequence')
        if not isinstance(session, str) or not SESSION.fullmatch(session):
            raise ValueError('Invalid brain session')
        if any(type(v) is not int or not 0 <= v <= 2**53-1 for v in (generation, sequence)):
            raise ValueError('Invalid request generation or sequence')
        signals = [payload.get(side) for side in ('left', 'right')]
        if any(type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 1 for v in signals):
            raise ValueError('Brain inputs must be finite numbers in 0..1')
        if self.model is None:
            raise BrainUnavailable('Full brain is not ready')
        if not self._step_lock.acquire(blocking=False):
            raise BrainUnavailable('Full brain is busy')
        try:
            if generation < self._generations.get(session, -1):
                raise ValueError('Stale brain generation')
            if session not in self._generations and len(self._generations) >= 16:
                retired = next(iter(self._generations))
                self._generations.pop(retired)
                self._sequences.pop(retired, None)
            if generation == self._generations.get(session, -1) and sequence <= self._sequences.get(session, -1):
                raise ValueError('Stale brain sequence')
            self._generations[session] = generation
            self._sequences[session] = sequence
            owner = (session, generation)
            if owner != self._owner:
                self.model.reset()
                self._owner = owner
                self._last_sequence = -1
            if sequence <= self._last_sequence:
                raise ValueError('Stale brain sequence')
            self._last_sequence = sequence
            started = time.perf_counter()
            result = self.model.step(float(signals[1]), float(signals[0]), duration_ms=18.0)
            result["goal_input_map"] = "goal_left_to_right_PFL3_and_goal_right_to_left_PFL3"
            result["goal_signals"] = {"left": signals[0], "right": signals[1]}
            self._status = self.model.status()
            self.last = {'wall_ms': round((time.perf_counter()-started)*1000,3),
                         'generation': generation, 'sequence': sequence}
            return {**result, 'session_id': session, 'generation': generation, 'sequence': sequence,
                    'source': 'full_flywire_gpu_lif', 'service': dict(self.last)}
        finally:
            self._step_lock.release()
