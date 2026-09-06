# Appearance round-trip failure diagnosis

The preserved Windows run `logs/windows-appearance-skills-external-mambo` failed
8 of 30 checks. Its first costume change executed successfully; the return did
not. These are separate causes, not eight independent runtime defects.

The wet action was delivered at 5971 ms. The requested VRM hash loaded at 6641 ms,
and native completion was acknowledged at 6675 ms. That same state publication
changed world revision 4 to 5. The final reply arrived at 9125 ms with its already
issued intent removed by the stale-context guard. PCM first arrived at 8693 ms,
after the short native reload had finished. Zero speech/action overlap here is a
measurement, not failure to execute or play speech.

The return-to-default action at 12107 ms and final reply at 12590 ms contained no
intent. Exact-turn provider state for `t2-12307`, captured before restarting,
contains `"intent":{}` alongside the Japanese promise to return. There was no
intervening world update; the next revision occurred at 23172 ms. This second
failure is model skill omission, not parser loss or a stale revision.

The backend change preserves only the exact action already transmitted to the
same active turn as historical `done` metadata, marked `intent_replay:true`.
Unissued stale intents remain rejected; reset, cancellation, character selection
and supersession still revoke delivery. The native's existing stable intent ID
prevents a repeated reload. Completion remains native feedback, not `done` itself.

The shared engine instruction now distinguishes direct conversational answers
from executable acknowledgments, and makes appearance changes independent of
geometry-target availability. Examples contain only current installed variant
IDs, including a default-return example when available. No Korean phrase is routed
to an action in Python. Real-model improvement requires a new preserved run; fake
provider tests establish lifecycle behavior only.

The companion JSON contains the original report hash, selected event records and
captured exact-turn raw output. It contains no PCM payload or microphone recording.
