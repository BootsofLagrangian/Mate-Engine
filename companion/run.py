#!/usr/bin/env python3
"""Start and supervise the local TTS and companion services; Ctrl-C stops children."""
import os, signal, subprocess, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
VENDOR=ROOT/'vendor/GPT-SoVITS'
children=[]
def main():
    def terminate(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, terminate)
    import yaml, site
    # GPU is the default; CPU remains an explicit opt-in.
    device=os.getenv('MATE_DEVICE','cuda')
    if device == 'cuda':
        import torch
        if not torch.cuda.is_available():
            raise SystemExit('CUDA unavailable. Run install.sh for GPU dependencies or explicitly set MATE_DEVICE=cpu.')
        free,total=torch.cuda.mem_get_info()
        if free < 6*1024**3:
            raise SystemExit(f'Only {free/1024**3:.1f} GiB VRAM free; this stack needs about 6 GiB headroom. Other jobs were not stopped.')
    config={'custom':{'device':os.getenv('MATE_TTS_DEVICE',device),'is_half':os.getenv('MATE_TTS_DEVICE',device)!='cpu','version':'v2','bert_base_path':str(ROOT/'models/chinese-roberta-wwm-ext-large'),'cnhuhbert_base_path':str(ROOT/'models/chinese-hubert-base'),'t2s_weights_path':str(ROOT/'models/uma-AIO-GPT-v2-e100.ckpt'),'vits_weights_path':str(ROOT/'models/uma-AIO-SoViTS-v2_e20_s8300.pth')}}
    config_path=ROOT/'models/tts.yaml';config_path.write_text(yaml.safe_dump(config))
    (ROOT/'logs').mkdir(exist_ok=True)
    env=os.environ.copy();env.setdefault('OMP_NUM_THREADS','8');env.setdefault('MKL_NUM_THREADS','8')
    env.setdefault('MATE_DEVICE',device)
    env.setdefault('MATE_WARMUP','1')
    env.setdefault('MATE_GPU_LAYERS','-1' if device=='cuda' else '0')
    env.setdefault('MATE_TTS_DEVICE',device)
    env.setdefault('MATE_STT_DEVICE',device)
    library_dirs=['/usr/lib/wsl/lib']
    for site_dir in site.getsitepackages():
        library_dirs.extend(str(p) for p in Path(site_dir).glob('nvidia/*/lib'))
    env['LD_LIBRARY_PATH']=':'.join(library_dirs+[env.get('LD_LIBRARY_PATH','')])

    # Legacy upstream checkpoint contains a Lightning configuration object. This is
    # scoped to this TTS child process and the explicitly downloaded model files.
    env['TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD']='1'
    commands=[([sys.executable,str(ROOT/'tts_worker.py'),'-a','127.0.0.1','-p','9880','-c',str(config_path)],VENDOR,'tts'),([sys.executable,'-m','uvicorn','app:app','--host','127.0.0.1','--port','8765'],ROOT,'companion')]
    import socket
    for port in (8765,9880):
        with socket.socket() as sock:
            try: sock.bind(('127.0.0.1',port))
            except OSError: raise SystemExit(f'Port {port} is occupied; stop the previous companion or choose another setup.')
    try:
        for cmd,cwd,name in commands:
            log=open(ROOT/f'logs/{name}.log','a',buffering=1)
            p=subprocess.Popen(cmd,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
            children.append(p);log.close();print(f'{name}: PID {p.pid}',flush=True)
        print('Open http://localhost:8765 (initial model load takes time). Logs: companion/logs/',flush=True)
        while all(p.poll() is None for p in children):time.sleep(1)
        raise SystemExit('A service exited. Inspect companion/logs/*.log.')
    except KeyboardInterrupt:pass
    finally:
        for p in children:
            if p.poll() is None:p.terminate()
        for p in children:
            try:p.wait(timeout=10)
            except subprocess.TimeoutExpired:p.kill();p.wait()
if __name__=='__main__':main()
