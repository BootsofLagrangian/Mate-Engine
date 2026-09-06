# Standing projection closure

Current bounded implementation passes 54 orthographic cells and 18 perspective cells, each with 121 heading samples across three real rigs and scales 0.6/1.0. Orthographic cameras cover yaw 0/45/90 and pitch 0/45/70; perspective covers yaw 0/45/90 at pitch 45. Reports and exact source hashes are in `floor-closure-manifest.json`.

The cached actual rest-mesh convex silhouette replaces phantom AABB corners. Horizontal/top navigation reserve covers heading changes; the lower support edge uses the current heading. A bounded measured-slope solve aligns that edge to the existing locked desktop support. Perspective placement intersects the physical foot-centre ray with its latched world-Y plane. It excludes seated/presentation transitions and does not grant arbitrary scale/view/drag changes attachment rights.

Autonomy invokes final crop/pivot placement before publishing its single committed movement signal. Living consumes the measured world displacement once for gait compensation; orthographic desktop translation is mapped through the tilted camera separately. The fixtures assert the actual final pivot difference, zero duplicate consumption, exact committed origin displacement, support retention and unchanged safety checks.

Final maximum rest-outline gaps are 0.990 px orthographic and 0.988 px perspective, within the pre-existing 1.01 px integer-reference allowance. Support-reference and committed-origin errors are zero. Perspective world-delta error is below 1e-9 m and latched plane error below 1e-6 m. No detached or unsafe frames occurred. This is deterministic rest-geometry placement evidence: no live skinned sole, full foot physics, frame-time performance, or visual naturalness claim.

Failures remain preserved: `floor-fixed-development-results.json` is the rejected swept-bottom hovering candidate; `floor-support-perspective-closure.json` records the old post-crop residual; `floor-support-perspective-five-step-development.json` records 5/18 failed unit-gain corrections. The final measured-slope solve passes the same gates. Files labelled stale/blocked fixture are setup errors, not discarded runtime failures.

Reproduce from repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/desktop_view/probe_floor_support.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/desktop_view/probe_floor_support_perspective.gd
```

Windows prerequisite: export the current source set in the manifest, then run the owned-window motion chain at yaw/pitch 45 and inspect its turn/walk frames. `_projected_anchors().foot` now denotes the desktop support reference; `foot_center` retains the physical pivot for projection-only tests. Root owns Windows execution. A canonical perspective world-Y floor and the desktop image edge are different constraints; this solve reconciles them by moving the pivot along the ground plane, never by pretending screen Y is world Y.
