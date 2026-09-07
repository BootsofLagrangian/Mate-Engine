import json, time
from types import SimpleNamespace
import stream_pipeline as sp

def test_partial_json_escapes_and_unicode():
    parts=['{"text":"あ','、\\','"はい','\\"。','" ,"gesture":"nod"}']
    raw='';spoken=[]
    for part in parts:raw+=part;spoken.append(sp.partial_text(raw))
    assert spoken==['あ','あ、','あ、"はい','あ、"はい"。','あ、"はい"。']
    assert sp.partial_text('{"text":"\\uD83D')==''
    assert sp.partial_text('{"text":"\\uD83D\\uDE0A')=='😊'

def test_phrase_starts_before_sentence_end_and_preserves_text():
    c=sp.PhraseChunker();chunks=[]
    text='はい、トレーナーさん、少し体を伸ばしましょう。'
    first=None
    for i,ch in enumerate(text):
        new=c.push(ch)
        if new and first is None:first=i
        chunks.extend(new)
    chunks.extend(c.push('',final=True))
    assert first < len(text)-1
    assert ''.join(chunks)==text
    assert chunks[0]=='はい、トレーナーさん、'

def test_audio_is_emitted_while_llm_is_still_generating(monkeypatch,tmp_path):
    (tmp_path/'output').mkdir();(tmp_path/'config.json').write_text('{"reference_text":"はい。"}')
    class FakeBrain:
        def stream_reply(self,*_):
            yield 'token',None
            yield 'text','はい、トレーナーさん、'
            time.sleep(.15)
            yield 'text','はい、トレーナーさん、ここにいます。'
            yield 'result',{'text':'はい、トレーナーさん、ここにいます。','emotion':'happy','gesture':'nod'}
    class Response:
        def __enter__(self):return self
        def __exit__(self,*_):pass
        def raise_for_status(self):pass
        def iter_bytes(self,**_):yield b'\x01\x00'*1280
    class Client:
        def __init__(self,**_):pass
        def __enter__(self):return self
        def __exit__(self,*_):pass
        def stream(self,*_,**__):return Response()
    monkeypatch.setattr(sp.httpx,'Client',Client)
    events=[json.loads(x) for x in sp.conversation_stream(FakeBrain(),SimpleNamespace(text='hello',session='test',voice=True),tmp_path)]
    first_audio=next(i for i,e in enumerate(events) if e['type']=='audio')
    final_text=max(i for i,e in enumerate(events) if e['type']=='text')
    assert first_audio<final_text
    done=events[-1];assert done['type']=='done' and done['audio_url'] and not done['voice_error']
    assert done['timings']['first_audio_ms']<done['timings']['llm_done_ms']


def test_brain_stops_at_first_complete_object():
    from app import Brain
    import json
    first={'text':'はい、トレーナーさん。','emotion':'neutral','gesture':'nod'}
    consumed=[]
    class Model:
        def create_chat_completion(self,**kwargs):
            for content in [json.dumps(first,ensure_ascii=False), '\n'+json.dumps(first,ensure_ascii=False)]:
                consumed.append(content)
                yield {'choices':[{'delta':{'content':content}}]}
    brain=Brain();brain.model=Model()
    events=list(brain.stream_reply('안녕','test'))
    assert events[-1]==('result',first)
    assert len(consumed)==1
