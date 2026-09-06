# External temporal-probe capture correction

The original Windows owner run is retained unchanged. Its authored chair entry
and exit completed, but six temporal/combined continuity checks failed under
synchronous per-frame PNG readback/encoding/saving. The route approach assertion
also named only `approaching`, missing the actual `scene_approaching` state.
These failures are not converted to passes; a new Windows run is required.

Telemetry now subscribes to every rendered frame while recording. Image capture
is separately limited to 8 Hz plus stage changes. Viewport readback remains on
the main thread and its measured cost is retained, so genuine readback/runtime
pauses still fail the unchanged maximum-50-ms temporal gates. PNG saving runs
on at most two worker jobs. Queue saturation is recorded and fails a separate
completeness check; it never suppresses a telemetry row. Each image records its
render-frame identity, time, readback/save cost, result and SHA256. Workers drain
before sequence analysis and final reports/exit. CSV output is buffered.

This changes visual sampling coverage: it does **not** claim every rendered
frame has a PNG or has been visually reviewed. The Linux writer test validates
bounded jobs, files and completion, not Windows app performance. The new actual
run must still meet all temporal and motion thresholds.

Four actual weighted base-mesh heel/toe vertices are cached once and evaluated
per frame. Raw source-clip FK marker positions are separately retained in skeleton
local metres; the source excludes host root displacement, blending and IK.
Compare relative trajectories using the recorded skeleton basis/scale and fixed
scene floor, not the moving avatar's stable foot anchor. These four markers are
not the minimum over every shoe vertex. Their source FK matches Godot's actual
skeleton transform evaluation on all three rigs at start/mid/end samples.
