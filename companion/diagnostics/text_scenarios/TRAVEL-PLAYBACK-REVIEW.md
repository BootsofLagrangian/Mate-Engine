# Travel/playback diagnostic review

**APPROVED** after narrowing ownership. Independent review of the root-authored
`simultaneous_travel_playback_samples` counter and README; no runtime behavior,
model input, or acceptance criterion changes.

The first version could attribute unrelated travel to a queued command. The
reviewed version requires the current trial's exact intent ID for direct
`move_to`, or the furniture interaction's matching `command_id` and
`scene_approaching` stage. Legacy furniture travel additionally requires its
`request_id` to equal the active Director ID, matching the request that
`DesktopObjectsHost` actually creates. Pending commands and appearance reloads
alone cannot qualify travel.

Counting also requires actual voice playback and either active scene navigation
with nonzero committed displacement or legacy walking velocity above 1 px/s.
The engine process-frame ID prevents repeated samples in one frame from inflating
this counter. Scene navigation is initialized before scenario readiness; missing
displacement diagnostics safely default to zero. This remains sampled evidence,
not synchronized duration or a guarantee of continuous movement. The older,
broader active-command counter remains separately labeled.

Validation: Godot 4.5.2 Linux `--headless --check-only --script
tools/run_text_scenario.gd` with `--path companion/native` passed (exit 0).
Reviewed the actual furniture request/stage assignments. No Windows run, backend
restart, or inference request was performed for this review.

Reviewed SHA-256:

- `native/tools/run_text_scenario.gd`: `a9d9da95028c60a0bde2c63a4aed5488455487a0ebb13013d7565f4327a91295`
- `diagnostics/text_scenarios/README.md`: `ad6cd4e4f21671419177baac81280cdfa6a92f502f3c4c5862aa2b2c9e60d7df`
