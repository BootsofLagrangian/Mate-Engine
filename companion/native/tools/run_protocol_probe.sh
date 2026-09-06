#!/usr/bin/env bash
# End-to-end native protocol probe on Linux, headless. Starts a FAKE TTS (tools/fake_tts.py),
# the engine with the TEST-ONLY stub provider and the engine's fake codex, then runs
# tools/probe_protocol.gd through the installed Godot. No GPU, no display, no real voices.
# Usage: companion/native/tools/run_protocol_probe.sh [engine_port] [tts_port]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
COMPANION="$(cd "$PROJECT/.." && pwd)"
GODOT="${GODOT:-$COMPANION/tools/Godot_v4.5.2-stable_linux.x86_64}"
PY="${PY:-$COMPANION/../../.venv-omni/bin/python}"
PORT="${1:-8879}"
TTS_PORT="${2:-9881}"
JOB_ROOT="${MATE_JOB_ROOT:-/tmp/mate-probe-job-root}"
mkdir -p "$JOB_ROOT"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/godot-xdg/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/godot-xdg/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/godot-xdg/cache}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
[ -x "$GODOT" ] || { echo "Godot not found at $GODOT" >&2; exit 2; }
[ -x "$PY" ] || { echo "python not found at $PY" >&2; exit 2; }

LOG_DIR="${PROBE_LOG_DIR:-/tmp/mate-probe}"
mkdir -p "$LOG_DIR"
"$PY" "$HERE/fake_tts.py" "$TTS_PORT" >"$LOG_DIR/fake_tts.log" 2>&1 &
TTS_PID=$!
(
  cd "$COMPANION"
  MATE_ENGINE_PROVIDER=stub MATE_TTS_URL="http://127.0.0.1:$TTS_PORT" \
  MATE_JOB_ROOT="$JOB_ROOT" MATE_JOB_SANDBOX=read-only \
  MATE_CODEX_BIN="$PY $COMPANION/engine/tests/fake_codex.py" \
  exec "$PY" -m engine --port "$PORT"
) >"$LOG_DIR/engine.log" 2>&1 &
ENGINE_PID=$!
cleanup() { kill "$ENGINE_PID" "$TTS_PID" 2>/dev/null || true; wait "$ENGINE_PID" "$TTS_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
curl -fs "http://127.0.0.1:$PORT/health" >/dev/null || { echo "engine did not start; see $LOG_DIR/engine.log" >&2; tail -20 "$LOG_DIR/engine.log" >&2; exit 3; }
echo "== engine (stub provider + fake TTS + fake codex) on :$PORT, logs in $LOG_DIR"
set +e
timeout 240 "$GODOT" --headless --path "$PROJECT" -s tools/probe_protocol.gd -- --backend "http://127.0.0.1:$PORT" 2>&1 \
  | grep -Ev "^\s*$|RID allocations|leaked|Pages in use|PagedAllocator|resources still in use|ObjectDB|instance_notify_deleted|Leaked instance"
STATUS=${PIPESTATUS[0]}
set -e
exit "$STATUS"
