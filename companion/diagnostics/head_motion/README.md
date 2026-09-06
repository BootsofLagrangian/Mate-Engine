# Head motion diagnosis (2026-09-06)

Uninterrupted idle reproduced excessive head derivatives before the fix. It was not solely an artifact of rapidly replacing gestures. The procedural noise used `FastNoiseLite.frequency = 0.35` with coordinates `elapsed * 20`, feeding head amplitudes 1.5/2.5/1.2 degrees through an exponential 16/s filter. Small amplitude did not mean slow movement. Replacing those inputs with slow analytic sinusoids removed this measured idle problem while preserving bank gestures.

The accompanying probe loads real VRMs and invokes the actual `MotionPlayer._process` with deterministic 30/60 Hz deltas for 20 simulated seconds per scenario. Seed 2251, one trajectory per model/rate/scenario; no selection over seeds. All three supplied rigs were tested. Summaries exclude the first second. Head **global** rotation includes the spine/chest/neck contributions; neck global step is also retained. Angular velocity is a quaternion rotation vector divided by delta; acceleration is the difference between consecutive angular velocity vectors divided by delta. `atan2` is used instead of `acos(dot)` to avoid float precision quantization of tiny rotations.

| Scenario | Before peak speed / acceleration, 60 Hz | After peak speed / acceleration, 60 Hz |
| --- | ---: | ---: |
| Frozen | 0 / 0 | 0 / 0 |
| Idle, fixed central gaze | 25.624 / 1392.707 | 1.801 / 2.420 |
| Idle, autonomous gaze | 26.485 / 1360.201 | 2.117 / 2.638 |
| Single full wave, idle off | 9.147 / 38.538 | unchanged |
| Single full nod, idle off | 45.224 / 356.671 | unchanged |
| Single full bow, idle off | 40.863 / 155.911 | unchanged |
| Gaze step at 5 seconds | 44.735 / 963.435 | unchanged |
| Replace wave/nod/bow every 0.9 s | 343.429 / 21207.248 | unchanged |

Units are degrees/second and degrees/second². All three rigs produced the same head metrics to reported precision. At 30 Hz, fixed-gaze idle changed from 23.240 / 828.131 to 1.801 / 2.418. After the fix, full gestures with idle layered on peak at 9.25 / 38.37 (wave), 45.64 / 354.92 (nod), and 39.58 / 154.07 (bow), at 60 Hz.

An exact baseline spike: at 16.916667, 16.933333, 16.950000 s, head quaternions `(x,y,z,w)` were respectively `(-.000371021,.003850064,.002341482,.999989808)`, `(.000194553,.002259016,.001865370,.999995708)`, `(.000827182,.000420393,.001110545,.999999046)`. Steps were .22392532°, .20104294°, .23901405°; middle acceleration was 1392.70740509°/s². Small steps repeatedly changing direction explain the high acceleration. Complete Cheval traces are compressed under `evidence/`; summaries for all rigs and fixed-code/model SHA256 identities are retained there. Baseline code was the live pre-edit source, not a committed revision: the decisive coefficients are recorded above; baseline SHA256 was not captured.

## Interpretation and remaining limits

- The frozen baseline is exactly stationary and the same canonical head result transfers across all three rest-normalized rigs. This supports a procedural input cause rather than a rig-specific head rest-axis error.
- None of these three models has a spring joint named Head or Neck, and no BoneNodeConstraintApplier is instantiated. Actual spring joint inventories are in each summary. Springs affect hair, ears, clothing and tails, so their appearance still needs visual assessment.
- Source inspection finds the addon constraint applier calls `do_process` both from `_process` and a SkeletonModifier signal on Godot 4.5. This is a latent double-evaluation risk for constraint-bearing models, not an explanation for these models. The spring modifier runs separately after procedural poses; the probe disables model processing and therefore does not claim to validate its physical stability or render ordering.
- MotionPlayer writes canonical head/neck once per frame; hand IK touches arms only. VRMA can deliberately override canonical poses in a later blend, but no VRMA was played in these scenarios.
- Main updates gaze after MotionPlayer because motion has priority -10. This introduces a frame of input latency. Gaze projects the moving head location; that is a small feedback path requiring a rendered-pointer check, but the large measured idle derivatives already occur with an explicitly fixed central target. The static cached pet AABB does not itself oscillate with head pose.
- The gaze step is a deliberate target discontinuity, distinct from stationary jitter. The existing two exponential filters still produce a relatively sharp acceleration transient. If visually objectionable, use a bounded-acceleration gaze trajectory or a short quintic target transition; avoid reducing all gesture smoothing to compensate.
- Replacing incomplete gestures every .9 s is a separate discontinuity stress test and remains harsh. It must not serve as the sole naturalness acceptance test. Changing this behavior requires interruption blending rather than only changing idle noise.

Suggested engineering thresholds were sent before the fixed rerun: stationary central-gaze idle peak speed <5°/s and acceleration <30°/s²; autonomous gaze <8°/s and <60°/s². These are regression tolerances for this quiet-idle design, not validated biological thresholds. Both frame rates pass after the fix. Complete wave/nod/bow should preserve intended range and finish once before the next command.

This is a fixed-delta skeletal measurement, **not** actual Windows FPS, a rendered hair stability test, or proof that movement is human. Root agent owns Windows 20-second idle and complete-gesture visual acceptance.

## Reproduce

From `companion/`, Linux:

```sh
./tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script "$PWD/diagnostics/head_motion/probe_head.gd" -- /tmp/head-motion-result "$PWD/assets/cheval-grand.vrm"
```

Windows PowerShell, from `companion` (headless, no second visible window):

```powershell
& .\tools\Godot_v4.5.2-stable_win64_console.exe --headless --path native --script "$PWD\diagnostics\head_motion\probe_head.gd" -- "$PWD\logs\head-motion-windows" "$PWD\assets\cheval-grand.vrm"
```

Repeat with `eishin-flash.vrm` and `rice-shower.vrm`. The optional first argument is the output directory and the second is the absolute model path. `*_idle` gesture scenarios layer idle on; plain gesture scenarios isolate bank motion. All full gestures start at 2 s and are allowed to finish. Rapid gestures are explicitly labeled as a stress scenario.
