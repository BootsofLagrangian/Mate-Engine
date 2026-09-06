# Chair phase host integration review

**APPROVED for bounded source integration**, Astra Face, 2026-09-07. Actual Windows choreography is not approved by this record.

Reviewed Host setup, carrier phases, stationary-envelope and rigid-body admission, restoration, cancellation handoff, semantic repositioning and computer-only stored chair scale. The earlier development findings are addressed:

- Carrier phase start clears previous readiness. Lift waits for a new Motion pose with a bounded failure wait; rigid travel requires ready/frozen state and the admitted model/source identity.
- Lift/lower uses the stationary articulation envelope; each rigid step requires the body sweep against desk/other solids and a projected body/assembly fit. Host yaw interpolation now uses the same shortest-angle path as the sweep helper. These are rig-volume checks, not full garment or hand-contact clearance.
- Normal exit latches the exact completed foot before empty restoration. Its exception is restricted to the matching restoration object, stage, model and exact foot, retaining previous ownership-token guards. Each empty restoration step checks a sweep against the standing actor and other furniture.
- Cancellation clears the carrier and transfers actual chair setup to the native scene before releasing the shared scene. Activation restores that setup. Normal completion follows restoration; stopped/interrupted work is not silently called complete.
- Semantic repositioning uses the complete setup envelope at fixed Y and replans at the candidate pose. Failed candidates restore the previous store/projection. Explicit world-position requests do not take that fallback.
- `seat_scale` is finite, bounded 0.5–1.25 and computer-only. New workstations retain whole-desk proportions while the adjustable chair follows source clearance. Existing records without the field retain their original chair size.

Owner reports: phase fixture 13/0, ground 29/0, stored seat scale 12/0, commands 31/0, real-rig scene/restoration latch 285/0. The phase fixture uses stub Motion/contact commits and is not a rendered collision proof. Motion and geometric helper validation remain separately owned; actual combined and Windows results must be retained before closing choreography acceptance. The roughly 80-second interaction freshness budget does not replace the existing route deadline or exact terminal predicates.

## Cleanup step-away follow-up: APPROVED

Reviewed `_begin_restore_step_away`, its token-bound arrival callback and the native-only optional navigation grid descriptor. The fallback runs once and only for the specific actor-blocking restoration result. It retains the blocked step for revalidation after actual walking, holds furniture stationary during the route, preserves world Y and uses the planner's fine grid with current full solids. Invalid grid fields and controller geometry failures reject before ownership mutation; ordinary requests keep their existing defaults.

The route has an eight-second host deadline. Only the matching active callback with `arrived` and an actual endpoint within 15 mm resumes restoration. That walked endpoint is adopted as owned ground before restoration/completion; stale callbacks and cancellation cannot report completion. Scene callback ownership is cleared before notification. Existing model/Director/restoration identity guards remain in force.

Independently ran `test_restore_walk.gd` under Godot 4.5.2 headless: **12 checks, zero failures**, exit 0. This uses actual rig, Motion, navigation and desk geometry; viewport fitting is stubbed and therefore not established by this test. It covers the recorded obstruction, real roughly 0.10 m route, completed restoration, held endpoint, invalid grid and user cancellation/stale callback behavior. Windows timing, camera fit and visual choreography remain separate acceptance.

## Setup projection consistency follow-up: APPROVED

`_chair_setup_fits` now merges the current scene world AABB with the transformed continuous envelope and projects that world AABB's corners, matching runtime `contact_bounds` framing. This is deliberately conservative and closes the local-corner false admission; viewport dimensions, padding and workarea thresholds are unchanged. Independently ran actual-asset `test_setup_projection_bounds.gd`: **6 checks, zero failures**. It reproduces the old local-corner pass with runtime world-box overflow, verifies rejection, and retains an inward feasible candidate. The separately owned reposition helper must use the same envelope convention; this entry approves only the Host gate.

## Approach workarea admission: APPROVED

The scene adapter validates each rebuilt path before taking ownership. It queries the unchanged all-heading projection hull at each path vertex and requires each adjacent merged rectangle to fit one workarea. At positive depth, a translated vertex's perspective projection lies within its endpoint interval; the all-heading hull additionally covers rotation. Thus this is a conservative straight-segment view bound and does not admit a route through a monitor gap merely because its endpoints fit different monitors.

Host setup now calls the existing ground-adoption policy before planning/moving the chair. Already-owned feet are returned exactly. Unowned feet may receive the existing same-Y correction of at most 0.25 m, after whole-segment solid admission; original world position and projected displacement are explicitly recorded. This is not universally zero movement or transactional actor rollback: the initial correction can remain even if subsequent setup planning fails. No larger or hidden second normalization was added by this delta.

Independently ran `test_approach_route_view.gd`: **5 checks, zero failures**, including the recorded unsafe route, safe inward route, no preflight mutation, monitor-gap rejection and empty-path rejection. Candidate planning callbacks and projection constraints in the separately owned planner remain a separate review scope. No Windows outcome follows from this fixture.
