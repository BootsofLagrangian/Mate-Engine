"""Browser pages must not reach the native client's local work-agent socket."""
import pytest
from starlette.websockets import WebSocketDisconnect


@pytest.mark.parametrize('origin', ['https://untrusted.example', 'http://localhost:8876', 'null', ''])
def test_browser_origin_rejected_before_hello(client, origin):
    with pytest.raises(WebSocketDisconnect) as caught:
        with client.websocket_connect('/ws', headers={'origin': origin}) as ws:
            ws.receive_json()
    assert caught.value.code == 1008
    assert not client.app.state.connections


def test_native_client_without_origin_is_accepted(client):
    with client.websocket_connect('/ws') as ws:
        assert ws.receive_json()['type'] == 'hello'
