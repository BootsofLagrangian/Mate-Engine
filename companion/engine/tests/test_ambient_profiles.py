from pathlib import Path

import pytest

from engine.profiles import Profile, ProfileError, build_system_prompt


def make_profile(**extra):
    return Profile({'id': 'test', 'name': 'Test', **extra}, Path('test.json'))


def test_optional_ambient_configuration_is_catalogue_data():
    default = make_profile().catalog_entry()
    assert default['ambient_loop'] == '' and default['idle_actions'] == []
    profile = make_profile(ambient_loop='custom_rest', idle_actions=['look_once', 'stretch_once', 'look_once'])
    entry = profile.catalog_entry()
    assert entry['ambient_loop'] == 'custom_rest'
    assert entry['idle_actions'] == ['look_once', 'stretch_once']
    # Idle scheduling belongs to the host, not an extra prompt/model request.
    assert 'custom_rest' not in build_system_prompt(profile)


@pytest.mark.parametrize('extra', [
    {'ambient_loop': '../other'}, {'ambient_loop': True}, {'ambient_loop': 'x' * 33},
    {'idle_actions': 'look'}, {'idle_actions': ['../look']}, {'idle_actions': [1]},
    {'idle_actions': ['look'] * 9}, {'idle_actions': ['']},
])
def test_invalid_ambient_references_rejected(extra):
    with pytest.raises(ProfileError):
        make_profile(**extra)
