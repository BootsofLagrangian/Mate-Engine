import json
import pytest
from engine.profiles import Profile, ProfileError, build_system_prompt, load_profiles, normalize_result, user_instruction
from engine.history import HistoryStore
from engine.audio import AudioError, decode_wav_base64
from conftest import profile_json, wav_base64


def test_profile_ids_and_filenames_are_validated(companion_root):
    path = companion_root / 'characters' / 'Bad Name.json'
    path.write_text(json.dumps(profile_json('Bad Name', 'x')))
    with pytest.raises(ProfileError):
        Profile(json.loads(path.read_text()), path, companion_root)
    mismatch = companion_root / 'characters' / 'other.json'
    mismatch.write_text(json.dumps(profile_json('alpha', 'x')))
    problems = []
    loaded = load_profiles(companion_root / 'characters', companion_root, problems=problems)
    assert set(loaded) == {'alpha', 'beta', 'gamma'}
    assert len(problems) == 2


def test_asset_paths_cannot_escape_companion_root(companion_root):
    data = profile_json('alpha', 'x', assets={'vrm': '../../etc/passwd', 'reference_audio': '/etc/passwd', 'reference_text': 'x'})
    profile = Profile(data, companion_root / 'characters' / 'alpha.json', companion_root)
    assert profile.vrm_path() is None
    # reference falls through to assets/alpha-reference.wav, which exists in the fixture
    ref = profile.reference()
    assert ref and ref[0] == companion_root / 'assets' / 'alpha-reference.wav'


def test_reference_fallback_chain(companion_root):
    # The original reference is Cheval's voice, never a generic fallback.
    (companion_root / 'assets' / 'reference.wav').write_bytes((companion_root / 'assets' / 'alpha-reference.wav').read_bytes())
    (companion_root / 'config.json').write_text(json.dumps({'reference_text': 'legacy text'}))
    gamma = load_profiles(companion_root / 'characters', companion_root)['gamma']
    assert gamma.reference() is None
    from engine.profiles import Profile
    cheval = Profile({'id': 'cheval-grand', 'name': 'Cheval'}, companion_root / 'characters/cheval-grand.json', companion_root)
    assert cheval.reference() == (companion_root / 'assets/reference.wav', 'legacy text')
    cheval.assets = {'reference_audio': 'assets/missing.wav'}
    assert cheval.reference() is None, 'an explicit broken asset must not silently fall back'


def test_prompt_builder_is_generic_and_uses_examples(companion_root):
    profiles = load_profiles(companion_root / 'characters', companion_root)
    prompt = build_system_prompt(profiles['beta'])
    assert 'ベータ' in prompt and 'アルファ' not in prompt and 'シュヴァル' not in prompt
    assert '{"text": "こんにちは。", "emotion": "happy", "gesture": "wave"}' in prompt
    assert 'Japanese' in prompt and 'gesture: idle,nod' in prompt
    assert '音声' in user_instruction(profiles['beta'], 'audio') and 'ベータ' in user_instruction(profiles['beta'], 'text')
    # Optional user_role changes how the counterpart is addressed
    custom = Profile(profile_json('zeta', 'ゼータ', user_role='トレーナー'), companion_root / 'characters' / 'zeta.json', companion_root)
    assert '人間のトレーナー' in build_system_prompt(custom)
    assert 'の発言例:' not in build_system_prompt(custom)


def test_normalize_result_allowlists_and_optional_action_parameters():
    out = normalize_result({'text': ' はい。 ', 'emotion': 'bogus', 'gesture': 'rm -rf', 'intensity': 1.2, 'speed': 9, 'repeat': 2})
    assert out == {'text': 'はい。', 'emotion': 'neutral', 'gesture': 'idle', 'intensity': 1.2, 'repeat': 2}
    for bad in ({'text': ''}, {'text': None}, [], {'gesture': 'wave'}):
        with pytest.raises(ValueError):
            normalize_result(bad)


def test_history_is_bounded_and_isolated():
    store = HistoryStore(max_turns=2, max_sessions=2)
    for i in range(3):
        store.append('s1', 'alpha', {'kind': 'text', 'text': str(i)}, {'text': 'r'})
    assert [u['text'] for u, _ in store.get('s1', 'alpha')] == ['1', '2']
    assert store.get('s1', 'beta') == [] and store.get('s2', 'alpha') == []
    store.append('s1', 'beta', {'kind': 'text'}, {})
    store.append('s2', 'alpha', {'kind': 'text'}, {})  # evicts the least recently used key
    assert store.get('s1', 'alpha') == []
    assert len(store.sessions()) == 2
    store.reset('s1')
    assert store.get('s1', 'beta') == []


def test_wav_decoding_limits():
    audio, seconds = decode_wav_base64(wav_base64(seconds=0.5, rate=44100))
    assert abs(seconds - 0.5) < 1e-3 and abs(len(audio) - 8000) <= 2
    with pytest.raises(AudioError):
        decode_wav_base64(wav_base64(seconds=31))
    with pytest.raises(AudioError):
        decode_wav_base64('not base64!')
    with pytest.raises(AudioError):
        decode_wav_base64('aGVsbG8=')  # valid base64, not a WAV
