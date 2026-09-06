"""Generic desktop-companion engine: FastAPI + WebSocket server on port 8876.

Character profiles, voice references and motion banks are data. The
language/audio provider is selected with MATE_ENGINE_PROVIDER (default: omni,
loaded lazily on the first turn; `stub` is a deterministic test-only provider).
"""
import sys
from pathlib import Path

ENGINE_DIR = Path(__file__).resolve().parent
COMPANION_ROOT = ENGINE_DIR.parent
REPO_ROOT = COMPANION_ROOT.parent
# The engine reuses the existing companion stream pipeline (chunking, TTS, cancellation).
if str(COMPANION_ROOT) not in sys.path:
    sys.path.insert(0, str(COMPANION_ROOT))

PROTOCOL_VERSION = 1
