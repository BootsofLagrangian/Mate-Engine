#!/usr/bin/env bash
# Uses the pinned custom template, checks import errors, and includes launchers/licenses.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-release}" != release ]; then
  echo "This wrapper exports release builds. Use the Godot editor for debug exports." >&2
  exit 2
fi
exec python3 "$HERE/../../setup_native.py" --build
