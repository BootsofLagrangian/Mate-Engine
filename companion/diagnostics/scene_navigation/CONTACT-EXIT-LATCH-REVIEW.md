# Completed contact exit latch review

Independent source review by Astra Face, 2026-09-07.

Initial verdict: **REVISE**. The exact endpoint is captured before contact cleanup and adopted afterward. Cleanup emits synchronous command/interaction/changed callbacks. A callback can accept a new legacy Director route or begin another furniture interaction without setting `navigation.active` or the scene completion callable. The initial `adopt_contact_exit` guards would then reclaim the foot and disable legacy processing after that newer work. Post-callback ownership validation must include those controllers, and living disable must prevent adoption.

The geometry portion is consistent: the API rejects stale models and a fit requiring any positional correction, checks the unchanged point against actor-expanded solids, and assigns the captured point exactly. It does not normalize the accepted point onto a different floor. The owner fixture `/tmp/scene-exit-latch.log` reports 278 checks, zero failures, including actual-rig/chair five-second hold. This initial result does not cover the callback ownership gap above. No Windows validation was performed by this reviewer.

## Corrected verdict: APPROVED

The owner now captures the Director active ID and queued IDs before completion callbacks. Adoption checks that token afterward, rejects a new furniture interaction/presentation or active legacy target, and retains the existing scene-route, model, drag and surface guards. Disabled living also rejects. This resolves the reported callback reclaim paths without forbidding unchanged preexisting Director state. The accepted world point remains exact, with geometry validation before mutation.

Inspected the corrected source and `/tmp/scene-exit-latch.log`: 281 checks, zero failures, including newer queued user work, new furniture interaction and disabled-living rejection. The fixture ObjectDB exit warning is retained. Approval covers the bounded source change and recorded fixture scope; actual Windows completed-exit continuity and subsequent navigation remain separate acceptance.

## External probe follow-up

**APPROVED** source design for the post-chair assertion in `probe_windows_scene_navigation.gd`. It replaces the incompatible legacy attached-floor expectation with the production `contact_exit_world` record followed by five seconds of measured actual foot XYZ drift below 5 mm, scene latch/holding, inactive navigation, no completion owner and idle interaction stage. It injects neither normalization nor adoption. Object removal precedes the hold, so that lifecycle operation is included. Initial corridor `settled_floor` remains unchanged. Entry preparation metadata is copied after real seating for later profiling. This approval is limited to these changes, not other cumulative capture edits or a claimed Windows result.

The later strict-computer terminal correction is also **APPROVED**. Full computer acceptance now counts all matching terminal records and requires exactly one with outcome `completed`. An idle state after failed restoration cannot pass. Failed terminal validation still drains captures, analyzes the sequence, and attempts the ground hold before the final combined verdict. Independently ran Godot 4.5.2 `--headless --check-only` on the external probe: exit 0. No Windows launch occurred.
