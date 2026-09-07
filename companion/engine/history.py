"""Bounded conversation memory keyed by (session, character).

A session is one WebSocket connection; client-supplied names are namespaced within it.
Characters never share memory, and the store evicts the least recently used
session key once the session cap is reached.
"""
import threading
from collections import OrderedDict


class HistoryStore:
    def __init__(self, max_turns=6, max_sessions=32):
        self.max_turns = max_turns
        self.max_sessions = max_sessions
        self._store = OrderedDict()
        self._lock = threading.Lock()

    @staticmethod
    def key(session, character):
        return (session, character)

    def get(self, session, character):
        with self._lock:
            turns = self._store.get(self.key(session, character))
            if turns is None:
                return []
            self._store.move_to_end(self.key(session, character))
            return list(turns)

    def append(self, session, character, user, assistant):
        """user: {'kind':'text'|'audio', ...}; assistant: dict result. Keeps the last max_turns pairs."""
        with self._lock:
            key = self.key(session, character)
            turns = self._store.get(key)
            if turns is None:
                while len(self._store) >= self.max_sessions:
                    self._store.popitem(last=False)
                turns = []
            turns = (turns + [(user, assistant)])[-self.max_turns:]
            self._store[key] = turns
            self._store.move_to_end(key)

    def reset(self, session, character=None):
        with self._lock:
            for key in list(self._store):
                if key[0] == session and (character is None or key[1] == character):
                    del self._store[key]

    def sessions(self):
        with self._lock:
            return list(self._store)
