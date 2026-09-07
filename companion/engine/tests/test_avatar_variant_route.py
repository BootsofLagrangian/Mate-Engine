import json


def test_avatar_variant_download_does_not_fallback_or_change_identity(client, companion_root):
    path = companion_root / 'characters/alpha.json'
    data = json.loads(path.read_text())
    data['avatar_variants'] = [
        {'id': 'wet', 'label': 'Wet', 'vrm': 'assets/alpha-wet.vrm'},
        {'id': 'missing', 'label': 'Missing', 'vrm': 'assets/not-installed.vrm'},
    ]
    path.write_text(json.dumps(data))
    variant = b'glTF-variant-distinct-content'
    (companion_root / 'assets/alpha-wet.vrm').write_bytes(variant)
    default = client.get('/characters/alpha/avatar').content
    assert client.get('/characters/alpha/avatar?variant=default').content == default
    assert client.get('/characters/alpha/avatar?variant=wet').content == variant
    for variant_id in ('unknown', 'missing', '../beta'):
        assert client.get('/characters/alpha/avatar', params={'variant': variant_id}).status_code == 404
    profile = client.get('/characters/alpha').json()
    assert profile['id'] == 'alpha'
    variants = {item['id']: item for item in profile['avatar_variants']}
    assert variants['wet']['avatar_url'] == '/characters/alpha/avatar?variant=wet'
    assert variants['wet']['avatar_available'] is True
    assert variants['missing']['avatar_available'] is False
    assert client.get('/characters/alpha/avatar').content == default


def test_appearance_skill_native_optin_selected_profile_and_revocation(client, companion_root, monkeypatch):
    from test_intents import provider, chat, collect
    from engine.providers.omni import OmniProvider
    path = companion_root / 'characters/alpha.json'
    data = json.loads(path.read_text())
    data['avatar_variants'] = [{'id':'wet','label':'Wet','vrm':'assets/alpha-wet.vrm'}]
    path.write_text(json.dumps(data))
    (companion_root / 'assets/alpha-wet.vrm').write_bytes(b'glTFwet')
    intent = {'kind':'change_appearance','variant_id':'wet'}
    seen = []
    provider(client, monkeypatch, intent, seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        message = {'type':'world_context','character_id':'alpha','interests':[], 'appearance_supported':True,'active_variant_id':'wet'}
        ws.send_json(message); first=collect(ws,lambda e:e['type']=='world_context')[-1]
        ws.send_json(message); assert collect(ws,lambda e:e['type']=='world_context')[-1]['revision']==first['revision']
        events=chat(ws)
        assert len([e for e in events if e.get('intent')==intent])==2
        system=OmniProvider(client.app.state.history).build_messages(seen[-1])[0][0]['content'][0]['text']
        assert 'change_appearance' in system and 'Current active installed costume variant_id: "wet"' in system
        for invalid in ({'appearance_supported':1},{'active_variant_id':'missing'}):
            ws.send_json({**message,**invalid}); assert collect(ws,lambda e:e['type']=='error')[-1]['type']=='error'
        ws.send_json({**message,'appearance_supported':False,'active_variant_id':'default'})
        collect(ws,lambda e:e['type']=='world_context')
        assert all('intent' not in e for e in chat(ws,'unsupported'))
        ws.send_json({'type':'select_character','character':'beta'})
        collect(ws,lambda e:e['type']=='character_selected')
        ws.send_json({**message,'character_id':'beta','active_variant_id':'default'})
        collect(ws,lambda e:e['type']=='world_context')
        assert all('intent' not in e for e in chat(ws,'other-character','beta'))


def test_appearance_intent_has_no_urls_or_extra_fields():
    from engine.intent import normalize_intent
    variants=({'id':'default'},{'id':'wet'})
    valid={'kind':'change_appearance','variant_id':'wet'}
    assert normalize_intent(valid,appearance_variants=variants)==valid
    for bad in ({**valid,'url':'file:///model.vrm'},{**valid,'variant_id':'missing'},{**valid,'variant_id':True}):
        assert normalize_intent(bad,appearance_variants=variants) is None
    assert normalize_intent(valid) is None


def test_appearance_inflight_support_revocation_strips_action(client, monkeypatch):
    import threading
    from test_intents import provider, collect
    entered, release = threading.Event(), threading.Event()
    provider(client, monkeypatch, {'kind':'change_appearance','variant_id':'default'}, entered=entered, release=release)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        context={'type':'world_context','character_id':'alpha','interests':[],'appearance_supported':True}
        ws.send_json(context);collect(ws,lambda e:e['type']=='world_context')
        ws.send_json({'type':'chat','text':'着替えて','turn_id':'revoke','character':'alpha','voice':False})
        assert entered.wait(2)
        ws.send_json({**context,'appearance_supported':False})
        collect(ws,lambda e:e['type']=='world_context')
        release.set()
        events=collect(ws,lambda e:e['type']=='done')
        assert all('intent' not in e for e in events)
