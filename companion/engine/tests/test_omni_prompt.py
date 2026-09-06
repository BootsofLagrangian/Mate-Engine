"""CPU-only checks of the Omni provider's prompt assembly against the real Qwen2.5-Omni processor.

Loads tokenizer + feature extractor only (no model weights, no CUDA). Skipped when
the local Thinker checkpoint directory or transformers is unavailable.
"""
import numpy as np
import pytest
from engine import COMPANION_ROOT
from engine.history import HistoryStore
from engine.profiles import load_profiles
from engine.providers.omni import OmniProvider, AUDIO_PLACEHOLDER
from engine.turns import make_request

MODEL_DIR = COMPANION_ROOT / 'models/qwen2.5-omni-3b-thinker'
pytestmark = pytest.mark.skipif(not (MODEL_DIR / 'preprocessor_config.json').is_file(), reason='local Omni checkpoint not installed')


@pytest.fixture(scope='module')
def provider():
    pytest.importorskip('transformers')
    p = OmniProvider(HistoryStore(max_turns=4), device='cpu', history_audio_turns=1)
    p.load_processor_only()
    return p


def test_messages_and_features_for_text_and_audio_history(companion_root, provider):
    profile = load_profiles(companion_root / 'characters', companion_root)['alpha']
    tone = (0.05 * np.sin(np.arange(16000) / 10)).astype('float32')
    provider.history.append('s', 'alpha', {'kind': 'audio', 'audio': tone}, {'text': '一回目。', 'emotion': 'neutral', 'gesture': 'idle'})
    provider.history.append('s', 'alpha', {'kind': 'audio', 'audio': tone[:8000]}, {'text': '二回目。', 'emotion': 'neutral', 'gesture': 'idle'})
    provider.history.append('s', 'alpha', {'kind': 'text', 'text': 'テキスト'}, {'text': '三回目。', 'emotion': 'happy', 'gesture': 'nod'})
    req = make_request(turn_id='t', character='alpha', profile=profile, session='s', audio=tone[:4000], audio_seconds=0.25)
    messages, audios = provider.build_messages(req)
    # Only the newest history audio keeps its waveform; the older one degrades to a placeholder.
    assert [len(a) for a in audios] == [8000, 4000] and audios[1] is req.audio
    assert messages[1]['content'][0]['text'] == AUDIO_PLACEHOLDER
    assert any(part['type'] == 'audio' for part in messages[-1]['content'])
    assert 'アルファ' in messages[0]['content'][0]['text']
    inputs = provider.prepare_inputs(req)
    audio_token = provider.processor.tokenizer.convert_tokens_to_ids('<|AUDIO|>')
    assert int((inputs['input_ids'] == audio_token).sum()) > 0
    assert inputs['input_features'].shape[0] == 2  # two waveforms fed as features
    # Text-only turn produces no audio features at all.
    text_req = make_request(turn_id='t2', character='alpha', profile=profile, session='none', text='こんにちは')
    text_inputs = provider.prepare_inputs(text_req)
    assert 'input_features' not in text_inputs and int((text_inputs['input_ids'] == audio_token).sum()) == 0
    # No transcript of the audio appears anywhere in the prompt.
    prompt = provider.processor.tokenizer.decode(inputs['input_ids'][0])
    assert '音声での発言' in prompt and 'テキスト' in prompt


def test_fixture_capture_is_exact_processor_prompt_and_does_not_change_inputs(companion_root, provider, tmp_path, monkeypatch):
    import hashlib
    import json
    import time
    import torch
    from engine.providers import omni
    from engine.prompt_capture import capture_fixture
    profile=load_profiles(companion_root/'characters',companion_root)['alpha']
    req=make_request(turn_id='capture-real-processor',character='alpha',profile=profile,session='capture-fresh',text='fixture request',voice=False)
    req.furniture_catalog=({'id':'computer','verbs':['use','place']},)
    directory=tmp_path/'user-data/diagnostics';directory.mkdir(parents=True)
    (directory/'prompt-capture-request.json').write_text(json.dumps({'capture_id':'b'*32,'character_id':'alpha',
        'text_sha256':hashlib.sha256(req.text.encode()).hexdigest(),'expires_unix':time.time()+60}))
    monkeypatch.setattr(omni,'capture_fixture',lambda *args,**kwargs:capture_fixture(*args,**kwargs,root=tmp_path))
    first=provider.prepare_inputs(req)
    captured=json.loads((directory/'prompt-captures'/('b'*32+'.json')).read_text())
    messages,_=provider.build_messages(req)
    assert captured['messages']==messages
    assert captured['rendered_prompt']==provider.processor.apply_chat_template(messages,add_generation_prompt=True,tokenize=False)+omni.JSON_PREFIX
    assert captured['capabilities']['furniture_catalog']==[{'id':'computer','verbs':['use','place']}]
    second=provider.prepare_inputs(req)  # marker consumed: diagnostics now inactive
    assert torch.equal(first['input_ids'],second['input_ids'])
