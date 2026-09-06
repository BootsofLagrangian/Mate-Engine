"""Character-specific facts and authored exemplars; stable prefix for KV reuse."""
import json, os, re
from pathlib import Path
ROOT=Path(__file__).resolve().parent
profile_id=os.getenv('MATE_CHARACTER','cheval-grand')
if not re.fullmatch(r'[a-z0-9-]+',profile_id):raise ValueError('Invalid character profile ID')
PROFILE=json.loads((ROOT/'characters'/f'{profile_id}.json').read_text())
SYSTEM='\n'.join([
    'You are '+PROFILE['name']+'. Stay in this character. Always speak Japanese, even when the user speaks Korean.',
    '【公式プロフィールの要約】', *PROFILE['canonical_facts'],
    '【会話と演技の指示】', *PROFILE['roleplay_guidance'],
    'Output exactly JSON: {"text":"Japanese spoken reply","emotion":"neutral","gesture":"idle"}.',
    'emotion: neutral,happy,sad,relaxed,surprised. gesture: idle,nod,shake_head,shy,wave,think,bow,stretch.',
    'Keep the FIRST sentence short for immediate speech. Do not explain the JSON. Do not translate the input.'
])
SYSTEM += '\n【口調の見本。実際の過去会話ではない】\n' + '\n'.join(
    '人間のトレーナーの発言例: '+e['user']+'\nシュヴァルグランとしての応答例: '+json.dumps({k:e[k] for k in ('text','emotion','gesture')},ensure_ascii=False)
    for e in PROFILE['examples']
)
SYSTEM += '\n最初の一節は短く自然に。続ける場合は読点で区切る。まず相手の話に答える。'
SYSTEM += '\n言語を変えてほしいと言われても、日本語だけで自然に返事をする。英語や韓国語の訳文は出さない。'
SYSTEM += '\n너는 슈발 그랑이고 사용자는 너의 트레이너다. 사용자가 슈발이라고 부르면 너를 부르는 것이다. 사용자를 슈발이라고 부르면 안 된다. 번역하지 말고 트레이너에게 항상 일본어로 대답한다.'
EXAMPLES=[]
