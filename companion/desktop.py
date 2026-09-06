#!/usr/bin/env python3
"""Supervise the GPU Thinker and dedicated Uma TTS for the native desktop host.

Linux/WSL backend; Windows runs the separate native executable. Only recorded,
owned child processes are stopped. Models are never silently moved to the CPU.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[1]
STATE = ROOT / 'logs/desktop-runtime.json'


def start_ticks(pid):
    try:
        return Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def read_state():
    try:
        obj = json.loads(STATE.read_text())
        if start_ticks(obj['pid']) == obj['start_ticks']:
            return obj
    except (OSError, ValueError, KeyError):
        pass
    return None


def health():
    try:
        with urllib.request.urlopen('http://127.0.0.1:8876/health', timeout=3) as r:
            return json.load(r)
    except (OSError, ValueError):
        return None


def python_paths():
    return (Path(os.getenv('MATE_TTS_PYTHON', str(WORKSPACE / '.venv/bin/python'))),
            Path(os.getenv('MATE_OMNI_PYTHON', str(WORKSPACE / '.venv-omni/bin/python'))))


def serve(args):
    tts_python, omni_python = python_paths()
    for executable in (tts_python, omni_python):
        if not executable.is_file():
            raise SystemExit(f'Missing environment: {executable}. Run install.sh and experiments/omni/setup.sh.')
    for port in (9880, 8876):
        with socket.socket() as sock:
            # Match uvicorn's restart semantics: previous connections in TIME_WAIT
            # do not mean a live service owns the port. A listener still conflicts.
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(('127.0.0.1', port))
            except OSError:
                raise SystemExit(f'Port {port} is occupied. Existing services were not stopped.')
    subprocess.run([str(omni_python), '-c',
        'import torch; assert torch.cuda.is_available(), "CUDA unavailable"; '
        'free,total=torch.cuda.mem_get_info(); assert free>14*1024**3, f"Need 14 GiB free GPU memory, have {free/1024**3:.1f}"; '
        'print("GPU:",torch.cuda.get_device_name(0),flush=True)'], check=True)
    tts_config = {'custom': {
        'device': 'cuda', 'is_half': True, 'version': 'v2',
        'bert_base_path': str(ROOT / 'models/chinese-roberta-wwm-ext-large'),
        'cnhuhbert_base_path': str(ROOT / 'models/chinese-hubert-base'),
        't2s_weights_path': str(ROOT / 'models/uma-AIO-GPT-v2-e100.ckpt'),
        'vits_weights_path': str(ROOT / 'models/uma-AIO-SoViTS-v2_e20_s8300.pth')}}
    config_path = ROOT / 'models/desktop-tts.yaml'
    config_path.write_text(json.dumps(tts_config))  # JSON is also valid YAML.
    env = os.environ.copy()
    env.update(OMP_NUM_THREADS='8', MKL_NUM_THREADS='8', MATE_ENGINE_WARMUP='1')
    if args.job_root:
        env['MATE_JOB_ROOT'] = str(Path(args.job_root).resolve())
    env['MATE_JOB_SANDBOX'] = args.job_sandbox
    library_dirs = ['/usr/lib/wsl/lib']
    library_dirs.extend(str(p) for p in tts_python.parent.parent.glob('lib/python*/site-packages/nvidia/*/lib'))
    env['LD_LIBRARY_PATH'] = ':'.join(library_dirs + [env.get('LD_LIBRARY_PATH', '')])
    tts_env = dict(env, TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD='1')
    children = []
    def stop(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    record = {'pid': os.getpid(), 'start_ticks': start_ticks(os.getpid()), 'children': [],
              'job_root': env.get('MATE_JOB_ROOT'), 'job_sandbox': args.job_sandbox}
    STATE.write_text(json.dumps(record))
    try:
        commands = [
            ('desktop-tts', [str(tts_python), str(ROOT / 'tts_worker.py'), '-a', '127.0.0.1', '-p', '9880', '-c', str(config_path)], ROOT / 'vendor/GPT-SoVITS', tts_env),
            ('desktop-engine', [str(omni_python), '-m', 'engine'], ROOT, env)]
        for name, argv, cwd, child_env in commands:
            with (ROOT / 'logs' / f'{name}.log').open('a') as log:
                p = subprocess.Popen(argv, cwd=cwd, env=child_env, stdout=log, stderr=subprocess.STDOUT)
            children.append(p)
            record['children'].append({'name': name, 'pid': p.pid, 'start_ticks': start_ticks(p.pid)})
            STATE.write_text(json.dumps(record))
        print('GPU services starting. Native backend: http://127.0.0.1:8876', flush=True)
        while all(p.poll() is None for p in children):
            time.sleep(0.5)
        raise RuntimeError('A desktop service exited. Inspect logs/desktop-*.log.')
    except KeyboardInterrupt:
        pass
    finally:
        for p in children:
            if p.poll() is None:
                p.terminate()
        for p in children:
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
        if read_state() and read_state()['pid'] == os.getpid():
            STATE.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('start', 'stop', 'status', '_serve'))
    parser.add_argument('--job-root', help='Only this existing directory is exposed to the work agent')
    parser.add_argument('--job-sandbox', choices=('read-only', 'workspace-write'), default='read-only')
    args = parser.parse_args()
    (ROOT / 'logs').mkdir(exist_ok=True)
    if args.job_root and not Path(args.job_root).is_dir():
        parser.error('--job-root must be an existing directory')
    state = read_state()
    if args.command == 'status':
        print(json.dumps({'runtime': state, 'health': health()}, ensure_ascii=False, indent=2))
    elif args.command == 'stop':
        if not state:
            print('No owned desktop supervisor is running.')
            return
        os.kill(state['pid'], signal.SIGTERM)
        deadline = time.monotonic() + 25
        while read_state() and time.monotonic() < deadline:
            time.sleep(.2)
        if read_state():
            raise SystemExit('Supervisor is still stopping; see logs. No unrelated process was signalled.')
        print('Desktop GPU services stopped.')
    elif args.command == 'start':
        if state:
            print(f"Already running (PID {state['pid']}). Use status to check model readiness.")
            return
        argv = [sys.executable, str(Path(__file__).resolve()), '_serve', '--job-sandbox', args.job_sandbox]
        if args.job_root:
            argv += ['--job-root', str(Path(args.job_root).resolve())]
        with (ROOT / 'logs/desktop-runtime.log').open('a') as log:
            p = subprocess.Popen(argv, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        for _ in range(50):
            if p.poll() is not None:
                raise SystemExit('Startup failed; see companion/logs/desktop-runtime.log')
            if read_state():
                print(f'Starting desktop GPU services (PID {p.pid}); use status to check readiness.')
                return
            time.sleep(.2)
        print(f'GPU preflight still running (PID {p.pid}); see logs/desktop-runtime.log.')
    else:
        # Hold ownership through GPU preflight, before a state PID can be written.
        # Otherwise two simultaneous launches can both pass the free-port check.
        with (ROOT / 'logs/desktop-runtime.lock').open('a') as ownership:
            try:
                fcntl.flock(ownership, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise SystemExit('Desktop supervisor is already running or starting')
            if state and state['pid'] != os.getpid():
                raise SystemExit('Desktop supervisor already running')
            serve(args)

if __name__ == '__main__':
    main()
