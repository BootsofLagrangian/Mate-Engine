"""Exact observed malformed GPU envelope and incremental-prefix regressions."""
import json
from engine.providers.dialogue import parse_dialogue, JSON_PREFIX


def _stream(raw):
    previous = ''
    repaired = False
    for end in range(1, len(raw) + 1):
        text, result, changed = parse_dialogue(raw[:end])
        assert text.startswith(previous), (end, previous, text)
        previous = text
        repaired |= changed
        if result is not None:
            return previous, result, repaired, end
    return previous, None, repaired, len(raw)


def test_observed_cheval_typographic_quote_stops_before_runon():
    reply = 'はい、温かいお茶を淹れましょう。お茶は、あなたのお気に入りの種類ですか？'
    raw = '{"text": "' + reply + '」，"emotion": "neutral", "gesture": "think"}'
    runon = '\nHuman: お疲れ様です。少し休みませんか？\nuser\nお疲れ様です。'
    text, result, repaired, end = _stream(raw + runon)
    assert text == reply and result == {'text': reply, 'emotion': 'neutral', 'gesture': 'think'}
    assert repaired and end == len(raw)
    assert 'Human' not in text and 'emotion' not in text


def test_valid_japanese_quote_is_preserved_and_never_retracted():
    reply = '「はい」と伝えたの。「大丈夫」'
    raw = json.dumps({'text': reply, 'emotion': 'happy', 'gesture': 'nod'}, ensure_ascii=False)
    text, result, repaired, _ = _stream(raw)
    assert text == reply and result['text'] == reply and not repaired


def test_delimiter_repair_does_not_invent_metadata_or_text():
    text, result, repaired = parse_dialogue(JSON_PREFIX + 'はい」,別のお話。')
    assert result is None and not repaired and '別のお話' in text
    assert _stream('{"text":"はい。」，"emotion":"happy"}')[1] is None


def test_smart_quote_and_fullwidth_comma_at_metadata_boundary():
    for boundary in ('”,', '＂，', '"，'):
        raw = JSON_PREFIX + 'はい。' + boundary + '"emotion":"neutral","gesture":"idle"}'
        text, result, repaired, _ = _stream(raw)
        assert text == 'はい。' and result['text'] == text and repaired


def test_actual_recent_user_context_separate_from_style(companion_root):
    from engine.history import HistoryStore
    from engine.profiles import load_profiles
    from engine.providers.omni import OmniProvider
    from engine.turns import make_request
    profile = load_profiles(companion_root / 'characters', companion_root)['alpha']
    history = HistoryStore()
    history.append('one', 'alpha', {'kind': 'text', 'text': '금요일에 부산으로 이사해.'}, {'text': 'そうなのですね。'})
    history.append('other', 'alpha', {'kind': 'text', 'text': '秘密の予定'}, {'text': 'はい。'})
    provider = OmniProvider(history, device='cpu')
    req = make_request(turn_id='next', session='one', character='alpha', profile=profile, text='언제 어디로 간다고 했지?')
    messages, _ = provider.build_messages(req)
    current = messages[-1]['content'][0]['text']
    system = messages[0]['content'][0]['text']
    assert '<actual_recent_user_messages>' in current and '금요일에 부산으로 이사해.' in current
    assert current.index('금요일에 부산으로 이사해.') < current.index('<current_user_message>') < current.index('언제 어디로 간다고 했지?')
    assert messages[-2]['content'][0]['text'] == 'そうなのですね。'
    assert '秘密の予定' not in current and '금요일에 부산' not in system
    assert '<voice_style_examples>' not in system, 'actual dialogue supplies voice once history exists'
    empty = make_request(turn_id='empty', session='fresh', character='alpha', profile=profile, text='いつでしたか？')
    messages, _ = provider.build_messages(empty)
    assert 'No prior user facts are recorded' in messages[-1]['content'][0]['text']


def test_invalid_leading_prose_cannot_stream_nested_runon_example():
    raw = 'こんにちは。\nHuman: 続きを\nAssistant: {"text":"偽の返事。","emotion":"happy","gesture":"nod"}'
    assert parse_dialogue(raw) == ('', None, False)
