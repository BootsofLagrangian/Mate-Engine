# Production scene adapter review

REVISE pending the bounded findings below. Read-only review of `desktop_scene_navigation_host.gd`, the scene routing and speech ownership additions in ObjectsHost/main, and `probe_windows_scene_navigation.gd`. This is independent of the implementation and does not reinterpret the first Windows run as a pass.

1. **Owned speech still blocks seat admission.** Host/navigation permit their matching turn's speech, but main still publishes speaking/foreground/dialogue hold into DesktopAutonomy's blocked context. `can_request_seat_contact` and `request_seat_contact` reject that blocked state. An approach that reaches its seat while its own reply continues can therefore fail admission. A fix must preserve unrelated-turn, panel, microphone, drag and pointer interruptions.
2. **Missing route render capture.** The direct scene route loop awaits rendering but never calls `sample_frame`, despite setting recording true. Its own PNG/CSV evidence therefore omits the tested route.
3. **Heading error is not turning.** A moving avatar with frozen, misaligned heading passes the current maximum heading-error assertion. Measure actual yaw change over time concurrent with translation.
4. **Perspective handoff coordinates are invalid.** The copied `global pixels / local projection PPM` coordinate is only valid in its original front orthographic fixture. In the new perspective fixture, compare actual canonical world joint positions across handoffs instead.
5. **Obstacle admission is not actual clearance proof.** The route supplies an obstacle but never checks measured rendered foot/body clearance against it. Add an actual path clearance check for the declared controller capsule contract, or explicitly exclude that claim.

The corrected terminal selector is sound: it requires the exact command ID, terminal record type, and nonempty string outcome. Cancellation clears the interaction before reentrant scene callbacks. The adapter sends committed world displacement to gait after validating viewport/workarea admission; no original asset mutation was found. Local planner/adapter regression counts remain separate evidence. No final naturalness or speech/action-overlap acceptance is made here.

## Corrected-source follow-up

APPROVED for the bounded source and measurement scope after rereview. All five findings above are corrected: the exact same-turn LLM interaction can admit contact only in ready_contact/seating, while panel, microphone, drag and pointer constraints remain active; route frames are captured after rendering; actual successive yaw changes are accumulated only during measured movement; expanded obstacle clearance is checked against actual rendered foot positions; and canonical world joints now define perspective handoffs. The fixture pins its FOV/distance.

Creation no longer relies on unprojecting an unrendered native viewport to determine size. It uses the imported asset reference pixels/metre and records a one-time physical conversion so record scale times unit scale initially equals pet scale. Semantic perspective placement uses the actor's world ground Y and camera-right projected onto XZ, without using padded-window pixels as world depth. These changes do not establish that every placement is reachable; normal projected-fit/collision admission remains necessary.

The concurrent-turn metric totals qualifying intervals; it is not an uninterrupted-duration proof. Renaming its sustained wording and the old desktop-metre handoff field to canonical world metres is recommended for precise reporting. No new runtime blocker was found. Actual Windows output, naturalness and live speech overlap remain separate acceptance evidence.
