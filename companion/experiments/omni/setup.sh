#!/usr/bin/env bash
set -euo pipefail
omni_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
omni_root="$(cd "$omni_dir/../../.." && pwd)"
omni_python="$omni_root/../.venv-omni/bin/python"
if [[ ! -x "$omni_python" ]]; then uv venv --python 3.11 "$omni_root/../.venv-omni"; fi
uv pip install --python "$omni_python" torch==2.6.0+cu126 torchaudio==2.6.0+cu126 torchvision==0.21.0+cu126 --index-url https://download.pytorch.org/whl/cu126
uv pip install --python "$omni_python" -r "$omni_dir/requirements-lock.txt" --extra-index-url https://download.pytorch.org/whl/cu126
OMNI_PROJECT_ROOT="$omni_root" HF_HUB_DISABLE_XET=1 "$omni_python" - <<'PY'
import os
from pathlib import Path
from huggingface_hub import snapshot_download
root=Path(os.environ['OMNI_PROJECT_ROOT'])/'companion'
snapshot_download('Qwen/Qwen2.5-Omni-3B',revision='f75b40e3da2003cdd6e1829b1f420ca70797c34e',local_dir=root/'models/qwen2.5-omni-3b',allow_patterns=['model-00001-of-00003.safetensors','model-00002-of-00003.safetensors','*.json','*.txt','LICENSE'],max_workers=2)
snapshot_download('facebook/mms-tts-kor',local_dir=root/'models/mms-tts-kor',allow_patterns=['*.json','*.safetensors'])
PY
"$omni_python" "$omni_dir/prepare_thinker.py"
