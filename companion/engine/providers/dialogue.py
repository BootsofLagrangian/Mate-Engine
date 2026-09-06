"""Incremental dialogue envelope parsing, including narrow typographic delimiter repair.

Only a closing typographic quote immediately before a known metadata key may
be repaired. No missing field/content is invented. Potential delimiter tokens
are withheld until disambiguated, so repairs never retract published dialogue.
"""
import json
import re
from stream_pipeline import partial_text

JSON_PREFIX = '{"text":"'
_FIELDS = ('emotion', 'gesture', 'intensity', 'speed', 'repeat')
_FIELD_PATTERN = '(?:' + '|'.join(_FIELDS) + ')'
_CLOSE = re.compile(r'[」”＂][,，](?=\s*"' + _FIELD_PATTERN + r'"\s*:)')
_COMMA = re.compile(r'"\s*，(?=\s*"' + _FIELD_PATTERN + r'"\s*:)')


def parse_dialogue(raw):
    candidate = raw.lstrip()
    if candidate.startswith('```json'):
        candidate = candidate[7:].lstrip()
    elif candidate.startswith('```'):
        candidate = candidate[3:].lstrip()
    if not candidate.startswith('{'):
        return '', None, False
    repaired = _CLOSE.sub('\",', candidate)
    repaired = _COMMA.sub('\",', repaired)
    streaming = repaired
    # A trailing Japanese/smart quote may be a legitimate part of the speech,
    # or the model's mistaken JSON closing quote. Wait for the next delimiter.
    for match in re.finditer('[」”＂]', repaired):
        tail = repaired[match.end():]
        pending = tail == ''
        if tail.startswith((',', '，')):
            rest = tail[1:].lstrip()
            pending = any(('"' + field + '"').startswith(rest) for field in _FIELDS)
        if pending:
            streaming = repaired[:match.start()]
            break
    text = partial_text(streaming)
    obj = None
    if repaired.startswith('{'):
        try:
            value, _ = json.JSONDecoder().raw_decode(repaired)
            if isinstance(value, dict) and all(k in value for k in ('text', 'emotion', 'gesture')):
                obj = value
        except json.JSONDecodeError:
            pass
    return text, obj, repaired != candidate
