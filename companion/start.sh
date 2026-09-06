#!/usr/bin/env bash
set -euo pipefail
companion_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
companion_python="${MATE_PYTHON:-$companion_dir/../../.venv/bin/python}"
if [[ ! -x "$companion_python" ]]; then
  echo "Run companion/install.sh first, or set MATE_PYTHON to your Python executable."
  exit 1
fi
exec "$companion_python" "$companion_dir/run.py"
