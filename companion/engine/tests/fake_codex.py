#!/usr/bin/env python3
"""FAKE codex CLI for tests. Emits the `codex exec --json` JSONL shapes observed with codex-cli 0.153.4.

Behaviour is driven by the prompt read from stdin:
  contains 'FAIL'  -> turn.failed + exit 2
  contains 'SLOW'  -> sleeps 30 s after starting (for cancellation tests)
  contains 'CRASH' -> exits 3 without a turn.completed event
  otherwise        -> one command item, one agent message, turn.completed, exit 0
It also records its argv to $FAKE_CODEX_ARGV when set.
"""
import json
import os
import sys
import time


def emit(obj):
    sys.stdout.write(json.dumps(obj) + '\n')
    sys.stdout.flush()


def main():
    argv = sys.argv[1:]
    if os.environ.get('FAKE_CODEX_ARGV'):
        with open(os.environ['FAKE_CODEX_ARGV'], 'w') as f:
            json.dump(argv, f)
    if argv[-1] != '-':
        sys.stderr.write('fake codex expects the prompt on stdin (-)\n')
        return 64
    prompt = sys.stdin.read()
    emit({'type': 'thread.started', 'thread_id': 'fake-thread'})
    emit({'type': 'turn.started'})
    if 'SLOW' in prompt:
        emit({'type': 'item.started', 'item': {'id': 'item_0', 'type': 'command_execution', 'command': 'sleep 30', 'status': 'in_progress'}})
        time.sleep(30)
    if 'CRASH' in prompt:
        return 3
    if 'FAIL' in prompt:
        emit({'type': 'turn.failed', 'error': {'message': 'fake model refused'}})
        return 2
    emit({'type': 'item.completed', 'item': {'id': 'item_0', 'type': 'command_execution', 'command': 'ls', 'aggregated_output': 'a.txt\n', 'exit_code': 0, 'status': 'completed'}})
    emit({'type': 'item.completed', 'item': {'id': 'item_1', 'type': 'reasoning', 'text': 'hidden'}})
    emit({'type': 'item.completed', 'item': {'id': 'item_2', 'type': 'agent_message', 'text': 'Listed the directory: a.txt. Prompt was: ' + prompt.strip()[:40]}})
    emit({'type': 'turn.completed', 'usage': {'input_tokens': 1, 'output_tokens': 1}})
    return 0


if __name__ == '__main__':
    sys.exit(main())
