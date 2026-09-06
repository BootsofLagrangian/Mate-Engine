"""Opt-in, one-shot local capture of an explicitly named fresh text fixture.

No HTTP capture endpoint. Never capture audio or a session containing user history.
The normal inference inputs/outputs are unchanged; diagnostic failures are ignored.
"""
import hashlib
import json
import math
import re
import time
from pathlib import Path
from . import COMPANION_ROOT


def capability_summary(req):
    return {'furniture_catalog': [{'id': row['id'], 'verbs': list(row['verbs'])} for row in req.furniture_catalog],
            'furniture_types': list(req.furniture_types), 'interests_count': len(req.world_interests),
            'locomotion_ids': [row['id'] for row in req.locomotion_catalog],
            'appearance_variant_ids': [row['id'] for row in req.appearance_variants]}


def capture_fixture(req, messages, rendered_prompt, *, has_history, root=COMPANION_ROOT, now=None):
    if has_history or req.audio is not None:
        return False
    directory=Path(root)/'user-data/diagnostics'
    marker=directory/'prompt-capture-request.json'
    try:
        if not marker.is_file() or marker.stat().st_size>4096:
            return False
        config=json.loads(marker.read_text(encoding='utf-8'))
        if not isinstance(config,dict) or set(config)!={'capture_id','character_id','text_sha256','expires_unix'}:
            return False
        capture_id=config['capture_id']
        if not isinstance(capture_id,str) or not re.fullmatch(r'[a-f0-9]{32}',capture_id):
            return False
        expiry=config['expires_unix'];now=time.time() if now is None else now
        if isinstance(expiry,bool) or not isinstance(expiry,(int,float)) or not math.isfinite(expiry) or not now<=expiry<=now+900:
            return False
        text_hash=hashlib.sha256(req.text.strip().encode()).hexdigest()
        if config['character_id']!=req.character or config['text_sha256']!=text_hash:
            return False
        payload={'capture_id':capture_id,'turn_id':req.turn_id,'character_id':req.character,'text_sha256':text_hash,
                 'captured_unix':now,'scope':'exact fresh text-only fixture; no audio or prior history',
                 'capabilities':capability_summary(req),'messages':messages,'rendered_prompt':rendered_prompt,
                 'rendered_prompt_sha256':hashlib.sha256(rendered_prompt.encode()).hexdigest()}
        content=json.dumps(payload,ensure_ascii=False,indent=2)
        if len(content)>1_000_000:return False
        output=directory/'prompt-captures'/f'{capture_id}.json'
        output.parent.mkdir(parents=True,exist_ok=True)
        with output.open('x',encoding='utf-8') as f:f.write(content+'\n')
        # Existing output makes this id one-shot even if marker deletion races.
        if json.loads(marker.read_text()).get('capture_id')==capture_id:marker.unlink()
        return True
    except (OSError,ValueError,TypeError,KeyError):
        return False
