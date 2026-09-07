import json
from engine.intent import furniture_example_capability, furniture_request_grounding, grounded_furniture_example
from engine.profiles import Profile, build_system_prompt
from test_furniture_intents import CATALOG


def test_use_example_not_hidden_by_earlier_place_only_capability():
    catalog=[{**CATALOG[0],'id':'a_seat','verbs':['place']},{**CATALOG[0],'id':'z_workstation','verbs':['use','place']}]
    assert furniture_example_capability(catalog)['id']=='z_workstation'
    assert '"object_type": "z_workstation"' in grounded_furniture_example(catalog)
    text=furniture_request_grounding(catalog)
    rows=json.loads(text.split('<skill_decision_examples> ')[1].split(' </skill_decision_examples>')[0])
    assert rows[0]['reply']['intent']=={'kind':'furniture','object_type':'z_workstation','verb':'use'}
    assert 'intent' not in rows[1]['reply']
    assert 'CURRENT request' in text


def test_examples_skip_unavailable_and_never_invent_supported_type():
    catalog=[{**CATALOG[0],'id':'hidden','verbs':['use'],'perception':{'available':False}}, {**CATALOG[0],'id':'lamp','verbs':['place']}]
    assert furniture_example_capability(catalog)['id']=='lamp'
    assert '"object_type": "lamp"' in furniture_request_grounding(catalog)
    assert furniture_request_grounding([])==''
    assert furniture_request_grounding([{**CATALOG[0],'verbs':['configure']}])==''


def test_desktop_profile_tone_examples_do_not_compete_with_skill_json(companion_root):
    from engine.profiles import load_profiles
    p=load_profiles(companion_root/'characters',companion_root)['alpha']
    p.data['examples']=[{'user':'hello','text':'こんにちは。','gesture':'wave'}]
    tools=build_system_prompt(p,desktop_context=True).split('<voice_style_examples>')[1].split('</voice_style_examples>')[0]
    chat=build_system_prompt(p,desktop_context=False).split('<voice_style_examples>')[1].split('</voice_style_examples>')[0]
    assert 'こんにちは。' in tools and 'JSON形式や行動の見本ではない' in tools
    assert '"gesture"' not in tools and '"text"' not in tools
    assert '"gesture"' in chat


def test_bilingual_grounding_is_bound_to_arbitrary_capability_not_input_phrase():
    for verb in ('use','place'):
        catalog=[{**CATALOG[0],'id':'portable_new_object','verbs':[verb]}]
        text=furniture_request_grounding(catalog)
        rows=json.loads(text.split('<skill_decision_examples> ')[1].split(' </skill_decision_examples>')[0])
        assert rows[0]['reply']['intent']=={'kind':'furniture','object_type':'portable_new_object','verb':verb}
        assert 'request_ko' in rows[0] and 'request_ja' in rows[0]
        assert ('사용해' in rows[0]['request_ko']) == (verb=='use')
        assert ('使って' in rows[0]['request_ja']) == (verb=='use')
        assert '하지 마' in rows[1]['request_ko'] and 'しないで' in rows[1]['request_ja']
        assert 'intent' not in rows[1]['reply']
        assert '컴퓨터' not in text and 'computer' not in text
