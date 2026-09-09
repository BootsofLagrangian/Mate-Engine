"""Service ordering/bounds and async loading with a fake GPU model; no biology claim."""
import threading
import time
import pytest
from engine.fly_brain_service import FullBrainService, BrainUnavailable

class Model:
    def __init__(self): self.resets=0; self.calls=[]
    def reset(self): self.resets+=1
    def status(self): return {'coverage': {'neurons': 4}}
    def step(self,left,right,duration_ms):
        self.calls.append((left,right,duration_ms));return {'forward':.5,'turn':left-right}

def service(tmp_path):
    s=FullBrainService(tmp_path);s.model=Model();return s

def request(**changes):
    return dict(session_id='native-1',generation=0,sequence=1,left=.2,right=.7,**changes)

def test_mapping_and_owner_reset(tmp_path):
    s=service(tmp_path);r=s.step(request())
    assert s.model.calls==[(.7,.2,18.0)]
    assert r['source']=='full_flywire_gpu_lif' and s.model.resets==1
    p=request();p['sequence']=2;s.step(p);assert s.model.resets==1
    p.update(generation=1,sequence=3);s.step(p);assert s.model.resets==2
    p.update(generation=0,sequence=4)
    with pytest.raises(ValueError,match='generation'):s.step(p)
    assert len(s.model.calls)==3

def test_sequence_and_busy_never_recompute(tmp_path):
    s=service(tmp_path);s.step(request())
    with pytest.raises(ValueError,match='sequence'):s.step(request())
    s._step_lock.acquire()
    try:
        with pytest.raises(BrainUnavailable,match='busy'):s.step(request())
    finally:s._step_lock.release()
    assert len(s.model.calls)==1

@pytest.mark.parametrize('key,value',[('left',True),('left',float('nan')),('right',-1),('right',2),('session_id','../x'),('generation',1.5),('sequence',False)])
def test_invalid_input_does_not_touch_model(tmp_path,key,value):
    s=service(tmp_path);p=request();p[key]=value
    with pytest.raises(ValueError):s.step(p)
    assert s.model.calls==[] and s.model.resets==0

def test_lazy_load_is_single_and_nonblocking(tmp_path):
    gate=threading.Event();calls=[]
    def factory(path):calls.append(path);gate.wait(2);return Model()
    s=FullBrainService(tmp_path,factory);s.warmup();s.warmup()
    assert s.loading and s.model is None
    with pytest.raises(BrainUnavailable):s.step(request())
    gate.set()
    deadline=time.monotonic()+2
    while s.loading and time.monotonic()<deadline:time.sleep(.005)
    assert s.status()['loaded'] and len(calls)==1


def test_sequence_survives_other_session_switch(tmp_path):
    s=service(tmp_path);p=request();p['sequence']=10;s.step(p)
    p.update(session_id='native-2',sequence=1);s.step(p)
    p.update(session_id='native-1',sequence=9)
    with pytest.raises(ValueError,match='sequence'):s.step(p)
    assert len(s.model.calls)==2


def test_http_contract_runs_bounded_model_and_rejects_replay(tmp_path):
    from fastapi.testclient import TestClient
    from engine.server import create_app
    from engine.providers import ScriptedProvider
    app=create_app(provider=ScriptedProvider('hello'),root=tmp_path)
    app.state.fly_brain=service(tmp_path)
    with TestClient(app) as client:
        assert client.get('/autonomy/brain').json()['loaded']
        reply=client.post('/autonomy/brain/step',json=request())
        assert reply.status_code==200 and reply.json()['sequence']==1
        assert client.post('/autonomy/brain/step',json=request()).status_code==400
        invalid=request();invalid['left']=True
        assert client.post('/autonomy/brain/step',json=invalid).status_code==400
