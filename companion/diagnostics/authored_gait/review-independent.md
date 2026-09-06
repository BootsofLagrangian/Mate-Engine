# Independent authored gait review

Verdict: **APPROVED** after two concrete state-ownership fixes. Reviewed by a separate agent context on 2026-09-07. Scope: DesktopGait authored contacts/world displacement and optional locomotion selection in LivingBehavior, BehaviorDirector and main `_on_locomotion`. Other ongoing spatial, prop, avatar and facial changes are excluded.

The authored path samples measured source contact intervals, preserves unplanted source rotations, and applies contact correction only during the configured blends. Wrapped intervals remain the same plant across raw phase zero, while a second interval acquires a new source ankle. Metadata validation rejects malformed and overlapping intervals without disturbing an active configuration. The existing gait remains the empty-metadata default.

Two findings were corrected during review:

1. Invalid displacement, support loss or effective-scale changes cleared feet but could retain pending world movement or the preceding support-height offset. These events now clear the affected accumulated state; avatar replacement also resets it. This prevents an obsolete support plane from carrying into new contacts.
2. Installing a new selected gait before `move_to_interest()` allowed that method's synchronous termination of the preceding native target to clear the new choice. Selection is now installed after those callbacks, only when the new target actually starts. Immediate arrival leaves no stale selection.

Independent tests:

- `review_lifecycle.gd`: **30 checks, zero failures**, with the actual Mambo VRM. Covers malformed/overlapping/wrapped/multiple contact intervals, live-style preservation after rejection, phase-zero plant continuity, exact swing rotations, separate-contact reacquisition, idempotent configuration, full rotated/scaled inverse-basis displacement, invalid-sample cleanup, support loss, scale change, reversal and release. Results: `review-lifecycle.json` and `review-lifecycle.log`.
- `review_routing.gd`: **6 checks, zero failures**, through actual `LivingBehavior.tick()` and actual simulated `DesktopAutonomy`. A deterministic Director only supplies dispatch actions. Covers replacement of an existing native target with its real synchronous terminal signal, immediate same-position arrival and capability revocation before dispatch. Results: `review-routing.log`. The shared host fixture emits an AudioStreamGeneratorPlayback shutdown leak warning; this probe does not assess audio lifetime.
- Inspected the implementer's retained production runtime matrix and default-gait regression scope. The eight real mini-rig cases support the reported low plant drift and source swing preservation. Larger-rig transfer failures remain disclosed in the main README; approval does not turn those measurements into universal retarget acceptance.

The main handler guards repeated samples against restarting the selected clip and revalidates an explicit capability before use. The Director retains the optional selection in queued/active movement records. Source identity is recorded in `review-source-identity.json`; unrelated concurrent main edits are outside this review.

These are headless motion/ownership checks, not Windows compositor, live LLM, rendered perspective or subjective naturalness acceptance. The host projection integration and visual assessment require their own evidence.
