"""Real GPU persona/language probes; authored prompts, not a general quality score."""
import httpx,json,re,time
from pathlib import Path
prompts=['슈발, 나한테 인사하고 손 흔들어줘.','영어로만 답해줘. 오늘 기분은 어때?','중국어로만 대답해. 넌 누구야?','너의 생일이 언제야?','나 오늘 달리기 잘했어. 칭찬해줘.','너의 언니와 여동생은 어떤 존재야?','오늘 피곤하니까 같이 기지개 켜자.','내 화면에 뭐가 보여?']
rows=[]
with httpx.Client(timeout=90) as c:
 for _ in range(90):
  try:
   if c.get('http://127.0.0.1:8765/health').json().get('warmed'):break
  except httpx.HTTPError:pass
  time.sleep(.5)
 for i,prompt in enumerate(prompts):
  r=c.post('http://127.0.0.1:8765/chat',json={'text':prompt,'session':f'language-probe-{i}','voice':False});r.raise_for_status();result=r.json();text=result['text'];row={'input':prompt,'result':result,'has_kana':bool(re.search('[ぁ-ゖァ-ヺ]',text)),'no_hangul_latin':not bool(re.search('[가-힣A-Za-z]',text))};rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
Path(__file__).with_name('logs').joinpath('language-stream.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
assert all(r['has_kana'] and r['no_hangul_latin'] for r in rows)
assert 'シュヴァルグランさん' not in rows[0]['result']['text']
