"""Profile shaping at the outbound turn boundary; no GPU or TTS required."""
from pathlib import Path

import pytest

from engine.profiles import Profile
from engine.providers.base import ScriptedProvider, TurnRequest
from engine.turns import Turn


def turn(style, turn_id='chat', provider=None):
    profile = Profile({'id': 'test', 'name': 'Test', 'motion_style': style}, Path('test.json'))
    request = TurnRequest(turn_id=turn_id, character='test', profile=profile, session='test', voice=False)
    events = []
    return Turn(request, provider or ScriptedProvider('はい。'), events.append), events


@pytest.mark.parametrize('turn_id', ['chat', 'job:test:ack', 'job:test:result'])
def test_profile_style_shapes_streamed_and_final_scripted_actions(turn_id):
    results = []
    for amplitude, tempo in [(0.6, 0.8), (1.2, 1.4)]:
        worker, events = turn({'amplitude': amplitude, 'tempo': tempo}, turn_id)
        worker._run()
        actions = [e for e in events if e['type'] in ('action', 'done')]
        assert [e['type'] for e in actions] == ['action', 'done']
        for event in actions:
            assert event['gesture'] == 'nod'
            assert event['intensity'] == amplitude
            assert event['speed'] == tempo
        assert actions[-1]['ok']
        results.append(actions[-1])
    assert results[0]['intensity'] != results[1]['intensity']
    assert results[0]['speed'] != results[1]['speed']


def test_explicit_controls_multiply_once_without_mutating_provider_result():
    worker, events = turn({'amplitude': 0.8, 'tempo': 1.2})
    raw = {'text': 'はい。', 'gesture': 'wave', 'intensity': 1.25, 'speed': 1.5, 'repeat': 2}
    for kind in ('action', 'done'):
        raw['type'] = kind
        worker._forward(raw)
    for event in events:
        assert event['intensity'] == 1.0
        assert event['speed'] == pytest.approx(1.8)
        assert event['repeat'] == 2
    assert raw['intensity'] == 1.25 and raw['speed'] == 1.5
    assert 'turn_id' not in raw and 'ok' not in raw


@pytest.mark.parametrize('style,expected', [
    ({'amplitude': 1e308, 'tempo': 1e308}, (1.5, 2.0)),
    ({'amplitude': 0, 'tempo': 0}, (0.0, 0.5)),
    ({'amplitude': float('nan'), 'tempo': -1}, (1.0, 1.0)),
])
def test_profile_style_output_bounds(style, expected):
    worker, events = turn(style)
    worker._forward({'type': 'action', 'gesture': 'nod'})
    assert (events[0]['intensity'], events[0]['speed']) == expected
