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
