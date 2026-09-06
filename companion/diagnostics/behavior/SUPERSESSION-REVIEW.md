# Same-support destination replacement — independent root review

APPROVED after implementation and focused-test inspection. Implementer: autonomy
agent; reviewer: root. This supersedes the interim immediate-stop/no-settle design.

A new valid destination during walking now retains the current velocity and
brakes with bounded acceleration before requesting the next turn. The native
controller checks both the new destination and the stopping endpoint v²/(2a)
against the current foot-support span, usable work area and path. It integrates
braking with the trapezoidal velocity average, continues reporting real movement
to gait, and permits the queued destination only after braking completes. The
ordinary 2.5-second cancellation settle is omitted for this qualified handoff;
normal anticipation and the heading-ready gate remain.

User stop, voice, dragging, pointer interaction, invalid geometry and lost/expired
replacement commands retain immediate stopping. Supersession emits one outcome
for the old trip. Queued freshness and the fixed navigation completion deadline
remain independent. Root found a stale handoff identifier across character
changes; the implementer cleared it in `set_character` and added a regression.

Verified suites: director 9746/0, autonomy 3636/0, surfaces 769/0. The cases cover
monotonic bounded braking, safe endpoint admission, emergency interruption,
expired replacement, current queue arbitration and character cleanup. Root also
verified Living forwards only the optional replacement point from the director.
This approval does not substitute for continuous bone/foot or Windows rendering
checks, which are recorded in the motion-chain acceptance.

Current limit: another retarget during the short braking interval invalidates the
prior queued replacement and uses the immediate-stop fallback. The smooth-braking
contract covers one validated same-support replacement, not arbitrary rapid input
streams. New instructions remain queued and are not silently ignored.
