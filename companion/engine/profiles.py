"""Character profiles, asset resolution and the generic prompt builder.

Profiles live in companion/characters/{id}.json. Nothing here knows a specific
character; every identity fact comes from the profile file.
"""
import json
import math
import re
from pathlib import Path
from . import COMPANION_ROOT
from . import config
from .intent import normalize_intent
from .motions import MOTION_ID

ID_PATTERN = re.compile(r'^[a-z0-9][a-z0-9-]{0,63}$')
EMOTIONS = ('neutral', 'happy', 'sad', 'relaxed', 'surprised')
DEFAULT_GESTURES = ('idle', 'nod', 'shake_head', 'shy', 'wave', 'think', 'bow', 'stretch')
DEFAULT_MOTION_STYLE = {'amplitude': 1.0, 'tempo': 1.0, 'idle_interval': 12}
BEHAVIOR_STYLE = {'idle_interval_s': (12.0, 4.0, 120.0), 'gaze_hold_s': (2.0, 0.3, 8.0),
                  'response_delay_s': (0.25, 0.0, 2.0), 'curiosity': (0.5, 0.0, 1.0),
                  'posture_strength': (0.5, 0.0, 1.0)}


class ProfileError(ValueError):
    pass


def valid_id(character_id):
    return isinstance(character_id, str) and bool(ID_PATTERN.fullmatch(character_id))


def _resolve_inside(root: Path, relative):
    """Resolve a profile-relative path and refuse anything escaping the companion root."""
    if not isinstance(relative, str) or not relative or relative.startswith(('/', '\\')) or '..' in Path(relative).parts:
        return None
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return None
    return candidate


class Profile:
    def __init__(self, data, path, root=COMPANION_ROOT):
        if not isinstance(data, dict):
            raise ProfileError(f'Profile {path.name} must be an object')
        self.data = data
        self.path = path
        self.root = root
        self.id = data.get('id')
        if not valid_id(self.id):
            raise ProfileError(f'Invalid character id in {path.name}')
        if path.stem != self.id:
            raise ProfileError(f'Profile file {path.name} does not match id {self.id}')
        if not isinstance(data.get('name'), str) or not data['name'].strip():
            raise ProfileError(f'Profile {self.id} has no name')
        for key in ('canonical_facts', 'roleplay_guidance', 'examples'):
            if not isinstance(data.get(key, []), list):
                raise ProfileError(f'Profile {self.id}: {key} must be a list')
        assets = data.get('assets') or {}
        if not isinstance(assets, dict):
            raise ProfileError(f'Profile {self.id}: assets must be an object')
        self.assets = assets
        if not isinstance(data.get('motion_style', {}), dict):
            raise ProfileError(f'Profile {self.id}: motion_style must be an object')
        if not isinstance(data.get('behavior_style', {}), dict):
            raise ProfileError(f'Profile {self.id}: behavior_style must be an object')
        ambient_loop = data.get('ambient_loop', '')
        idle_actions = data.get('idle_actions', [])
        if not isinstance(ambient_loop, str) or (ambient_loop and not MOTION_ID.fullmatch(ambient_loop)):
            raise ProfileError(f'Profile {self.id}: ambient_loop must be a motion ID or empty')
        if not isinstance(idle_actions, list) or len(idle_actions) > 8 or any(
                not isinstance(name, str) or not MOTION_ID.fullmatch(name) for name in idle_actions):
            raise ProfileError(f'Profile {self.id}: idle_actions must contain at most eight motion IDs')
        self.ambient_loop = ambient_loop
        self.idle_actions = list(dict.fromkeys(idle_actions))

    @property
    def name(self):
        return self.data['name']

    @property
    def motion_style(self):
        style = dict(DEFAULT_MOTION_STYLE)
        custom = self.data.get('motion_style') or {}
        for key in style:
            value = custom.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0:
                style[key] = value
        return style

    def vrm_path(self):
        return _resolve_inside(self.root, self.assets.get('vrm') or f'assets/{self.id}.vrm')

    @property
    def behavior_style(self):
        custom = self.data.get('behavior_style', {})
        result = {}
        for key, (default, low, high) in BEHAVIOR_STYLE.items():
            value = custom.get(key, self.motion_style['idle_interval'] if key == 'idle_interval_s' else default)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                value = default
            result[key] = max(low, min(high, float(value)))
        return result

    def reference(self):
        """Voice reference for GPT-SoVITS: (wav path, transcript). None when unavailable.

        Order: profile assets, then assets/{id}-reference.wav, then the legacy
        assets/reference.wav + config.json pair used by the original companion.
        """
        text = self.assets.get('reference_text')
        candidates = [self.assets.get('reference_audio'), f'assets/{self.id}-reference.wav']
        for relative in candidates:
            path = _resolve_inside(self.root, relative) if relative else None
            if path and path.is_file() and isinstance(text, str) and text.strip():
                return path, text.strip()
        legacy_audio = self.root / 'assets/reference.wav'
        legacy_config = self.root / 'config.json'
        if self.id == 'cheval-grand' and not self.assets and legacy_audio.is_file() and legacy_config.is_file():
            try:
                legacy_text = json.loads(legacy_config.read_text()).get('reference_text')
            except (OSError, ValueError):
                legacy_text = None
            if isinstance(legacy_text, str) and legacy_text.strip():
                return legacy_audio, legacy_text.strip()
        return None

    def job_line(self, kind):
        """Short spoken Japanese line for job ack/done/failed; None disables speech."""
        value = self.data.get({'ack': 'job_ack', 'done': 'job_done', 'failed': 'job_failed'}[kind])
        return value.strip() if isinstance(value, str) and value.strip() else None

    def catalog_entry(self):
        reference = self.reference()
        vrm = self.vrm_path()
        return {
            'id': self.id,
            'name': self.name,
            'avatar_url': f'/characters/{self.id}/avatar',
            'avatar_available': bool(vrm and vrm.is_file()),
            'voice_available': reference is not None,
            'motion_style': self.motion_style,
            'behavior_style': self.behavior_style,
            'ambient_loop': self.ambient_loop,
            'idle_actions': self.idle_actions,
            'source': self.data.get('source'),
            'examples': len(self.data.get('examples', [])),
        }


def load_profiles(directory=None, root=COMPANION_ROOT, strict=False, problems=None):
    """Load every valid profile. Invalid files are skipped (and reported in `problems`) unless strict."""
    directory = Path(directory) if directory else config.characters_dir()
    profiles = {}
    for path in sorted(directory.glob('*.json')):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
            profile = Profile(data, path, root)
        except (OSError, ValueError) as exc:
            if strict:
                raise ProfileError(f'Cannot load profile {path.name}: {exc}') from exc
            if problems is not None:
                problems.append(f'{path.name}: {exc}')
            continue
        profiles[profile.id] = profile
    return profiles


def build_system_prompt(profile, gestures=DEFAULT_GESTURES, include_examples=True, desktop_context=False):
    """Generic persona prompt: identity facts, guidance, JSON contract and in-context examples."""
    data = profile.data
    user_role = data.get('user_role') or 'ユーザー'
    lines = [
        f'You are {profile.name}. Stay in this character. Always speak Japanese, whatever language the {user_role} uses.',
        'Character facts below are ONLY about you. They are never facts about the human user, their birthday, schedule, preferences, or past experiences.',
        '【公式プロフィールの要約】', *[str(x) for x in data.get('canonical_facts', [])],
        '【会話と演技の指示】', *[str(x) for x in data.get('roleplay_guidance', [])],
        f'あなたは{profile.name}。話しかけているのは人間の{user_role}であり、あなた本人ではない。相手の発言を翻訳せず、その意味に日本語で答える。',
        ('Output one JSON object with text, emotion, gesture, and intent when a desktop action is requested. Follow the desktop intent schema below.' if desktop_context else
         'Output exactly JSON: {"text":"Japanese spoken reply","emotion":"neutral","gesture":"idle"}.'),
        'emotion: ' + ','.join(EMOTIONS) + '. gesture: ' + ','.join(gestures) + '.',
        'Optional JSON motion controls: intensity 0..1.5, speed 0.5..2, repeat integer 1..3. Omit unless useful.',
        'Keep the FIRST sentence short for immediate speech. Do not explain the JSON. Do not translate the input.',
    ]
    examples = [e for e in data.get('examples', []) if isinstance(e, dict) and 'user' in e and 'text' in e]
    if examples and include_examples:
        lines.append('<voice_style_examples>')
        lines.append('以下は口調だけの見本。登場する出来事や人物は、実際のユーザーの記憶ではない。内容を回答の根拠にしない。')
        for e in examples[:4]:
            lines.append(json.dumps({'text': e['text'], 'emotion': e.get('emotion', 'neutral'), 'gesture': e.get('gesture', 'idle')}, ensure_ascii=False))
        lines.append('</voice_style_examples>')
    lines.append('実際の会話は、このsystemメッセージの後のuser/assistant履歴だけ。見本の続きを書かない。')
    lines.append('ユーザーの「私・僕・나・내」はユーザー本人を指す。あなたの趣味や設定と混同しない。')
    lines.append('過去の発言を聞かれたら、実際のuser履歴の具体的な内容を答える。曖昧な相づちで済ませない。履歴にない事実は作らず、わからない時は短く確認する。')
    lines.append('A recall question asks WHAT happened, not how you feel about it. Name the concrete event, time or place from actual user messages before adding any emotional reaction. If unavailable, ask for it without guessing.')
    lines.append('JSONの引用符と区切りはASCIIの " と , だけ。textの後にemotionとgestureを書き、' + ('行動依頼ならintentも書いてから、' if desktop_context else '') + '}で終了する。')
    lines.append('最初の一節は短く自然に。続ける場合は読点で区切る。まず相手の話に答える。')
    lines.append('言語を変えてほしいと言われても、日本語だけで自然に返事をする。英語や韓国語の訳文は出さない。')
    return '\n'.join(lines)


def user_instruction(profile, modality):
    user_role = profile.data.get('user_role') or 'ユーザー'
    if modality == 'audio':
        return f'これは人間の{user_role}の音声での発言です。音声の内容に、{profile.name}として日本語で答えてください。返事は指定されたJSONだけ。'
    return f'これは人間の{user_role}の発言です。{profile.name}として日本語で答えてください。返事は指定されたJSONだけ。'


def normalize_result(obj, gestures=DEFAULT_GESTURES, interests=()):
    """Validate model output: dialogue text is mandatory, everything else is allow-listed."""
    if not isinstance(obj, dict):
        raise ValueError('Model output is not a JSON object')
    text = obj.get('text')
    if not isinstance(text, str) or not text.strip():
        raise ValueError('Empty dialogue')
    result = {
        'text': text.strip()[:500],
        'emotion': obj.get('emotion') if obj.get('emotion') in EMOTIONS else 'neutral',
        'gesture': obj.get('gesture') if obj.get('gesture') in gestures else 'idle',
    }
    for key, low, high in (('intensity', 0, 1.5), ('speed', 0.5, 2), ('repeat', 1, 3)):
        value = obj.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool) and low <= value <= high:
            result[key] = int(value) if key == 'repeat' else float(value)
    intent = normalize_intent(obj.get('intent'), interests)
    if intent is not None:
        result['intent'] = intent
    return result
