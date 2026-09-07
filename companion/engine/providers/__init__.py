"""Provider registry. Heavy providers import their dependencies only when instantiated."""
from .base import Provider, TurnRequest, ScriptedProvider


def create_provider(name, history):
    if name == 'omni':
        from .omni import OmniProvider
        return OmniProvider(history)
    if name == 'stub':
        from .stub import StubProvider  # test-only deterministic provider
        return StubProvider(history)
    raise ValueError(f'Unknown MATE_ENGINE_PROVIDER: {name!r} (expected omni or stub)')


__all__ = ['Provider', 'TurnRequest', 'ScriptedProvider', 'create_provider']
