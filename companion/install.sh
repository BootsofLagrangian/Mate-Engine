#!/usr/bin/env bash
set -euo pipefail
companion_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
companion_env="$companion_dir/../../.venv"
command -v uv >/dev/null
command -v ffmpeg >/dev/null
command -v npm >/dev/null
[[ -x "$companion_env/bin/python" ]] || uv venv --python 3.11 "$companion_env"
uv pip install --python "$companion_env/bin/python" 'torch==2.6.0+cu126' 'torchaudio==2.6.0+cu126' --index-url https://download.pytorch.org/whl/cu126
uv pip install --python "$companion_env/bin/python" 'https://github.com/abetlen/llama-cpp-python/releases/download/v0.3.19-cu124/llama_cpp_python-0.3.19-cp311-cp311-linux_x86_64.whl'
uv pip install --python "$companion_env/bin/python" -r "$companion_dir/requirements.txt"
"$companion_env/bin/python" "$companion_dir/setup.py"
