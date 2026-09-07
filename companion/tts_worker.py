"""Run the pinned upstream API with bounded CPU threads."""
import os, runpy, sys
from pathlib import Path
import torch
root=Path(__file__).resolve().parent/'vendor/GPT-SoVITS'
from tts_optimization import apply
print('MATE SDPA attention:', apply(root, os.getenv('MATE_TTS_SDPA','1')=='1'), flush=True)
os.chdir(root)
sys.path.insert(0,str(root))
sys.path.insert(0,str(root/'GPT_SoVITS'))
torch.set_num_threads(int(os.getenv('MATE_THREADS','8')))
# Pinned v2 Japanese frontend references symbols only imported in its __main__.
from text import japanese, symbols2
japanese.symbols = symbols2.symbols
runpy.run_path(str(root/'api_v2.py'),run_name='__main__')
