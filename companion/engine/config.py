"""Environment-driven settings. Everything is read at call time so tests can monkeypatch."""
import os
from pathlib import Path
from . import COMPANION_ROOT, REPO_ROOT

SANDBOX_MODES = ('read-only', 'workspace-write')


def env(name, default=None):
    value = os.getenv(name)
    return default if value is None or value == '' else value


def provider_name():
    return env('MATE_ENGINE_PROVIDER', 'omni')


def tts_url():
    return env('MATE_TTS_URL', 'http://127.0.0.1:9880')


def user_data_dir():
    return Path(env('MATE_USER_DATA', str(COMPANION_ROOT / 'user-data')))


def motion_bank_path():
    return Path(env('MATE_MOTION_BANK', str(REPO_ROOT / 'Assets/StreamingAssets/cheval-motions.json')))


def characters_dir():
    return Path(env('MATE_CHARACTERS_DIR', str(COMPANION_ROOT / 'characters')))


def default_character():
    return env('MATE_DEFAULT_CHARACTER', 'cheval-grand')


def job_settings():
    """Codex job policy. Jobs are unavailable until MATE_JOB_ROOT names an existing directory."""
    root = env('MATE_JOB_ROOT')
    sandbox = env('MATE_JOB_SANDBOX', 'read-only')
    problems = []
    if not root:
        problems.append('MATE_JOB_ROOT is not configured')
    elif not Path(root).is_dir():
        problems.append(f'MATE_JOB_ROOT does not exist: {root}')
    if sandbox not in SANDBOX_MODES:
        problems.append(f'MATE_JOB_SANDBOX must be one of {SANDBOX_MODES}, got {sandbox!r}')
    return {
        'root': str(Path(root).resolve()) if root and Path(root).is_dir() else root,
        'sandbox': sandbox,
        'codex': env('MATE_CODEX_BIN', 'codex'),
        'model': env('MATE_JOB_MODEL'),
        'timeout_seconds': float(env('MATE_JOB_TIMEOUT', '1800')),
        'available': not problems,
        'problems': problems,
    }


def history_turns():
    return int(env('MATE_HISTORY_TURNS', '6'))


def history_sessions():
    return int(env('MATE_HISTORY_SESSIONS', '32'))
