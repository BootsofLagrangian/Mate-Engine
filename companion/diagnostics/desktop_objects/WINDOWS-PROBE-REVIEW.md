# Independent shared-contact Windows probe review

2026-09-06. **REVISE two acceptance guards before final shared-contact acceptance.** Reviewed upgraded `probe_windows_objects.gd`; no Windows run or runtime edits.

Explicit requested/session/actual model identity is checked. The shared branch captures the root viewport after rendering, records shared-depth scope, measures both wrists against world keyboard sockets within 2 cm and projected sockets within 3 px, and checks seated socket alignment. These are meaningful final-pose measurements. Seat alignment still measures the calibrated stable seat anchor, not every live skinned buttock/thigh vertex.

Required: explicitly assert shared-contact mode in the new chair/sofa/computer acceptance cases. Currently a missing shared scene silently uses the legacy separate-window/single-hand branch and can pass despite the new feature being absent. Legacy diagnostics may remain with explicit failure of the new acceptance requirement.

Required: the finite-work-expiry assertion only checks an empty interaction, which can result from foreground cancellation. Require the interaction-finished `completed` outcome or observed full-duration progress. Early cancellation must not count as natural expiry.

`--contact-only` explicitly omits the mutation matrix; retain that scope when reporting counts. Normal cleanup shuts down owned objects idempotently, waits for queued frees, stops mic/world/client, frees the app, then restores settings. Existing-output reuse and abnormal script exceptions remain general probe limitations. Actual shared-host camera/placement integration is separately pending review.

## Guard revision

**APPROVED as revised.** Verified mandatory shared-contact assertions for seated furniture and computer use; legacy fallback can still produce diagnostics but cannot pass the new shared-feature requirement. Work expiry now requires exactly one matching object/use outcome after work starts, explicitly `completed`, together with an empty interaction. Calibrated-anchor wording correctly avoids claiming direct anatomical mesh contact. This closes both probe findings; actual Windows execution and shared-host runtime remain separate acceptance work.

## Persistence comparator revision

**APPROVED for canonical Store round trips.** Reviewed `persistence_equal()` and both JSON/disk call sites. It deep-copies records, compares finite scales within 1e-12 only when resulting integer object rectangles are identical, then requires exact equality of all remaining canonical fields and order. Diagnostic values retain 17 decimal places, absolute scale error and pixel rectangles. This appropriately tolerates serialization precision without permitting a changed rendered object size or position. Inputs are canonical Store dictionaries, not arbitrary unvalidated data. No runtime or Windows execution changes are implied.
