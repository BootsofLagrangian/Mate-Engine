# Final frozen standing regression

APPROVED for the bounded deterministic standing scope. Three rigs at 60 Hz and scale 1.0 pass 102 assertions. The preliminary unchanged probe also passed 99 assertions in `../final-seat-floor-standing/`; both attempts are preserved.

The callback-aware run invokes the real avatar `_capture_secondary_pose` after every motion pose update: 5,452 calls per rig, with 30 cached samples. It asserts that the standing floor constraint stays inactive and has no colliders. This specifically exercises the newly added cache callback, which automatic SkeletonModifier processing would not execute in the disabled-process deterministic host. It does not substitute for rendered spring-bone timing or active seated-floor tests.

Every complete decompressed frame CSV is byte-identical to both the corresponding original UMA348-matrix cell and the prior pose-bounds standing cell. Calibration nonmutation, bounds cleanup, navigation gaze, all five concurrent journeys/reversal stages, three finite gesture pairs and contact drift remain unchanged. The comparison JSON records every path, matching raw-data SHA-256, current source identity, and callback coverage.

The coordinated package file on disk hashes to `80303c7e703a5dbd526d343a2ac1ddd64af4b05ea8cbedd44094eb7c6bda170f`. These runs execute Linux Godot against the frozen source; they do not claim to execute that Windows package. Expanded source fingerprints include seated floor/calibration, world-reader/helper and desktop-object modules. The world reader and owned furniture remain inactive in this standing fixture; their active Windows behavior is coordinator-owned.
