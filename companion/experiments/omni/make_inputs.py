"""Synthetic Korean INPUT fixtures only; character OUTPUT remains original SoVITS."""
import json,hashlib
from pathlib import Path
import torch,soundfile as sf
from transformers import VitsModel,AutoTokenizer,set_seed
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'logs/omni-inputs';OUT.mkdir(parents=True,exist_ok=True)
CASES=[
 ('p00','안녕하세요. 오늘 하루는 어땠어요?','greeting; asks how your day was'),
 ('p01','저는 커피 말고 따뜻한 차를 마시고 싶어요.','wants warm tea, NOT coffee'),
 ('p02','오늘 시험에 합격해서 정말 기뻐요.','happy because passed an exam'),
 ('p03','오늘 시험에 떨어져서 너무 슬퍼요.','sad because failed an exam'),
 ('p04','오른손을 천천히 흔들어 주세요.','asks for slow right-hand wave'),
]
torch.set_num_threads(4);set_seed(42)
p=ROOT/'models/mms-tts-kor';model=VitsModel.from_pretrained(p).to('cuda');tokenizer=AutoTokenizer.from_pretrained(p)
rows=[]
for name,text,meaning in CASES:
 inputs=tokenizer(text,return_tensors='pt').to('cuda')
 with torch.inference_mode():audio=model(**inputs).waveform[0].float().cpu().numpy()
 path=OUT/(name+'.wav');sf.write(path,audio,model.config.sampling_rate)
 row=dict(id=name,path=str(path),text=text,expected_meaning=meaning,seconds=len(audio)/model.config.sampling_rate,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source='facebook/mms-tts-kor, synthetic input, seed42');rows.append(row);print(row,flush=True)
(OUT/'manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
