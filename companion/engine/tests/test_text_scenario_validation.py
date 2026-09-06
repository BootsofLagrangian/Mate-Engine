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
