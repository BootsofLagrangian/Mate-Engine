#!/usr/bin/env bash
# Headless import + self-test for the native host. Usage: companion/native/tools/run_selftest.sh
# Exit status: 0 only when the import step produced no script/parse errors AND selftest.gd passed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
GODOT="${GODOT:-$PROJECT/../tools/Godot_v4.5.2-stable_linux.x86_64}"
if [ ! -x "$GODOT" ]; then
  echo "Godot binary not found/executable at $GODOT (set GODOT=...)" >&2
  exit 2
fi
# Godot needs writable XDG dirs; sandboxed shells may not allow ~/.local.
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/godot-xdg/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/godot-xdg/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/godot-xdg/cache}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
LOG_DIR="${SELFTEST_LOG_DIR:-/tmp/mate-selftest}"
mkdir -p "$LOG_DIR"
# Noise the engine prints at exit in headless mode (leak reports) that carries no signal.
NOISE='^\s*$|RID allocations|leaked|Pages in use|PagedAllocator|resources still in use|ObjectDB|instance_notify_deleted|Leaked instance'
# Known addon (root-owned) noise during VRM retarget; everything else that says ERROR/SCRIPT ERROR fails the run.
ADDON_NOISE='bone name:  .(Spine|Chest). already exists|Node not found: "secondary"|skeleton_rename|perform_retarget|vrm_extension.gd|vrm_utils.gd|at: set_bone_name|at: get_node|GDScript backtrace|^\s+\[[0-9]+\] '

echo "== import (headless editor)"
set +e
"$GODOT" --headless --path "$PROJECT" --import >"$LOG_DIR/import.log" 2>&1
IMPORT_STATUS=$?
set -e
grep -Ei "error|warning" "$LOG_DIR/import.log" | grep -Ev "$ADDON_NOISE" || true
if grep -Eq "SCRIPT ERROR|Parse Error|Failed to load script|Compile Error" "$LOG_DIR/import.log"; then
  echo "import: script/parse errors (see $LOG_DIR/import.log)" >&2
  exit 1
fi
if [ "$IMPORT_STATUS" -ne 0 ]; then
  echo "import: Godot exited with status $IMPORT_STATUS (see $LOG_DIR/import.log)" >&2
  exit "$IMPORT_STATUS"
fi

echo "== selftest"
set +e
"$GODOT" --headless --path "$PROJECT" -s selftest.gd >"$LOG_DIR/selftest.log" 2>&1
STATUS=$?
set -e
grep -Ev "$NOISE" "$LOG_DIR/selftest.log" | grep -Ev "$ADDON_NOISE" || true
if grep -Eq "SCRIPT ERROR|Parse Error|Failed to load script|Compile Error" "$LOG_DIR/selftest.log"; then
  echo "selftest: script/parse errors (see $LOG_DIR/selftest.log)" >&2
  exit 1
fi
if ! grep -Eq "^selftest: [0-9]+ passed, 0 failed" "$LOG_DIR/selftest.log"; then
  echo "selftest: did not report a clean pass (see $LOG_DIR/selftest.log)" >&2
  [ "$STATUS" -ne 0 ] && exit "$STATUS"
  exit 1
fi
exit "$STATUS"
