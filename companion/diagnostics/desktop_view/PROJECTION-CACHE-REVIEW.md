# Native prop projection cache review

**APPROVED**, independent source review and focused rerun by Astra Face, 2026-09-07.

The cached-success key includes the actual reference camera transform/projection/viewport, desktop origin, requested object transform, mesh node/resource identities and global transforms, geometry revision, current native window size/position and crop camera transform/projection. Mesh change signals invalidate in-place edits; geometry collection and leaving shared projection clear the key. Failed fits do not install a reusable key. A requested transform change cannot be hidden by the old scene transform because both appear in the comparison.

Independently ran `test_projection_cache.gd` with Godot 4.5.2 headless: **70 checks, zero failures**. Actual imported computer cached/forced-full crop and socket equality passed, alongside camera, viewport, origin, mesh, chair setup/scale, yaw, clip-range and shared/private transitions. Ten unchanged calls caused no vertex extraction or reprojection. Hidden occupied-window reuse was covered.

Counters and last-request/last-fit timestamps are observational. This establishes cache correctness for the supported static imported prop geometry and setter paths; it does not measure Windows frame-time improvement or claim support for animated skin/blend-shape geometry.

Final telemetry follow-up is explicitly **APPROVED**: `_fit_shared_projection` calls the unchanged compute function once, records current-call duration, completion timestamp and result on every return, then returns that same result. Owner final fixture remains 70/0. The external scene probe's `started_ticks_msec` simply records its existing elapsed-time origin, allowing absolute projection timestamps to be mapped without attributing a retained prior fit cost to a later sample.
