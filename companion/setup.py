"""Download the exact runtime inputs. Run after installing requirements.txt."""
import hashlib, json, shutil, subprocess
from pathlib import Path
import requests
from huggingface_hub import snapshot_download
ROOT=Path(__file__).resolve().parent
REV='38cd8815781275a9b438d2c5812087c82f73a377'
URL='https://files.microcms-assets.io/assets/973fc097984b400db8729642ddff5938/c092ee8e4ec94adeae5d1038425a287b/chevalgrand_voice.mp3'
def download(url,path,expected=None):
    if path.exists() and (expected is None or hashlib.sha256(path.read_bytes()).hexdigest()==expected):return
    path.parent.mkdir(parents=True,exist_ok=True)
    partial=path.with_suffix(path.suffix+'.part')
    with requests.get(url,stream=True,timeout=(20,180)) as r:
        r.raise_for_status()
        with partial.open('wb') as f:
            for data in r.iter_content(2**20):f.write(data)
    if expected and hashlib.sha256(partial.read_bytes()).hexdigest()!=expected:raise ValueError(f'Hash mismatch: {path}')
    partial.replace(path)
def main():
    vendor=ROOT/'vendor/GPT-SoVITS'
    if not vendor.exists():
        subprocess.run(['git','init',str(vendor)],check=True)
        subprocess.run(['git','-C',str(vendor),'remote','add','origin','https://github.com/RVC-Boss/GPT-SoVITS.git'],check=True)
        subprocess.run(['git','-C',str(vendor),'fetch','--depth','1','origin',REV],check=True)
        subprocess.run(['git','-C',str(vendor),'checkout','--detach',REV],check=True)
    if subprocess.check_output(['git','-C',str(vendor),'rev-parse','HEAD'],text=True).strip()!=REV:
        raise SystemExit('Existing GPT-SoVITS revision differs; move it aside before setup. No checkout overwritten.')
    hashes={'uma-AIO-GPT-v2-e100.ckpt':'847f88e3d8bea9dc37fc686a02499e7402d9af6cceb6e6eda6bdbb3b16582716','uma-AIO-SoViTS-v2_e20_s8300.pth':'417d80e4fedb5bd4d9f45d985dc889d4fa738a8644177dea310f894e3c973a06'}
    for name,sha in hashes.items():download('https://huggingface.co/UmaDiffusion/uma-voice-gpt-sovits-v2/resolve/main/'+name,ROOT/'models'/name,sha)
    for repo,patterns in [('TencentGameMate/chinese-hubert-base',['config.json','preprocessor_config.json','pytorch_model.bin']),('hfl/chinese-roberta-wwm-ext-large',['*.json','pytorch_model.bin','vocab.txt'])]:
        snapshot_download(repo,allow_patterns=patterns,local_dir=ROOT/'models'/repo.split('/')[-1])
    download('https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',ROOT/'models/qwen2.5-1.5b-instruct-q4_k_m.gguf')
    snapshot_download('Systran/faster-whisper-small')
    assets=ROOT/'assets';assets.mkdir(exist_ok=True)
    if not (assets/'cheval-grand.vrm').exists():
        import gdown
        gdown.download(id='1-TDrBrutb5UClm-aAIat5FWoZeRDc-ar',output=str(assets/'cheval-grand.vrm'))
    if (assets/'cheval-grand.vrm').read_bytes()[:4]!=b'glTF':raise ValueError('Drive download is not VRM/GLB')
    download(URL,assets/'reference.mp3')
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(assets/'reference.mp3'),'-ac','1','-ar','32000',str(assets/'reference.wav')],check=True)
    import nltk
    for resource in ('averaged_perceptron_tagger_eng','cmudict','punkt_tab'):
        if not nltk.download(resource,quiet=True):raise RuntimeError('NLTK download failed: '+resource)
    import pyopenjtalk
    pyopenjtalk.g2p('こんにちは。') # Download pronunciation dictionary during setup.
    subprocess.run(['npm','ci'],cwd=ROOT/'web',check=True)
    subprocess.run(['npm','run','build'],cwd=ROOT/'web',check=True)
    print('Ready. Run: python companion/run.py')
if __name__=='__main__':main()
