# Refresh telemetry publication review

Verdict: **APPROVED**. Exact final identities are in `review-telemetry-source-hashes.json`.

Living records completed refresh count, target-refresh duration and completion timestamp, then publishes a deep copy under the scene-navigation diagnostics already sampled by the Windows probe. Scene counters and each valid live furniture window's projection-profile scalars are included. Source inspection confirms current profile fields are scalar counts, costs, timestamps and success flags; shallow per-window copying is sufficient for that schema, followed by deep publication copying. No refresh scheduling, target selection, publication policy, or probe acceptance threshold changes in this addition.

The independent actual-Living fixture passes its previous ownership and stale-request checks and adds exact seven-call accounting, nonnegative timings, matching scene rebuild count, exact profile-field forwarding, and copy independence. Mutating the live window profile and Living's nested diagnostic dictionaries does not change the previously published scene snapshot. Results are `review-telemetry.json/log`.

The duration ends before diagnostic copying/publication, so it measures target refresh rather than every instruction in `_refresh_targets`. Window and scene costs are the latest observed values, and the copied timestamps identify when those operations occurred; a telemetry row is not proof that every reported operation ran during that render frame. Repeated per-frame sampling may carry the same snapshot until the next refresh. Actual Windows timing attribution remains root's next test. No Windows process or runtime source was changed by this reviewer.
