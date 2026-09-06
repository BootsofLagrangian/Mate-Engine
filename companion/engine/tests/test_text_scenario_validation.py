import pytest
from run_text_scenario import validate_scenario


def test_scenario_assertions_remain_data_and_do_not_inject_calls():
    value={'version':1,'steps':[{'text':'着替えて','expect_intent':{'kind':'change_appearance','variant_id':'wet'}}]}
    assert validate_scenario(value) is value
    with pytest.raises(ValueError):validate_scenario({'version':1,'steps':[{'text':'着替えて','intent':{'kind':'change_appearance','variant_id':'wet'}}]})


@pytest.mark.parametrize('bad',[True,float('nan'),float('inf'),0,91,'60'])
def test_scenario_timeout_is_bounded_numeric(bad):
    with pytest.raises(ValueError):validate_scenario({'version':1,'steps':[{'text':'hello','timeout_s':bad}]})


def test_scenario_rejects_unbounded_or_empty_steps():
    for steps in ([],[{'text':'hello'}]*9,[{'text':' '}],[{'text':'x'*4001}]):
        with pytest.raises(ValueError):validate_scenario({'version':1,'steps':steps})


def test_conversation_no_intent_assertion_is_boolean_and_mutually_exclusive():
    step={'text':'Just discuss it','expect_no_intent':True}
    assert validate_scenario({'version':1,'steps':[step]})['steps'][0]==step
    for change in ({'expect_no_intent':1},{'expect_no_intent':'true'},{'expect_intent':{'kind':'furniture'}}):
        with pytest.raises(ValueError):validate_scenario({'version':1,'steps':[{**step,**change}]})
