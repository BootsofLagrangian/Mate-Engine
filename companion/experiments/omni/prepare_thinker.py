"""Create a Thinker-only index over unchanged upstream safetensor shards."""
import json,math
from pathlib import Path
from safetensors import safe_open
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'models/qwen2.5-omni-3b';target=ROOT/'models/qwen2.5-omni-3b-thinker';target.mkdir(exist_ok=True)
index=json.loads((source/'model.safetensors.index.json').read_text())
weights={k:v for k,v in index['weight_map'].items() if k.startswith('thinker.')}
size=0
for filename in set(weights.values()):
 path=source/filename
 if not path.is_file():raise FileNotFoundError(path)
 with safe_open(path,framework='pt',device='cpu') as f:
  for key in weights:
   if weights[key]==filename:
    item=f.get_slice(key);size+=math.prod(item.get_shape())*{'F32':4,'F16':2,'BF16':2,'I64':8}[item.get_dtype()]
for path in source.iterdir():
 if (path.suffix in ('.json','.txt') and path.name!='model.safetensors.index.json') or path.name in set(weights.values()):
  dest=target/path.name
  if not dest.exists():dest.symlink_to(path)
(target/'model.safetensors.index.json').write_text(json.dumps({'metadata':{'total_size':size},'weight_map':weights},indent=2))
print({'thinker_weight_bytes':size,'shards':sorted(set(weights.values())),'weights_unchanged':True})
