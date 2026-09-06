# Continuous main-scene transition audit

Current disposition: **APPROVED for the final deterministic concurrent transition/contact scope** in the latest `uma-walk-final/` matrix. Actual Windows visual acceptance remains coordinator-owned. Earlier failed candidates below are preserved; functional arrival checks alone do not establish smooth animation.

The probe instantiates the real main scene and its signal wiring, supplies local authored profiles and UMA home idle, and follows production ordering: motion pose update, main/context update, autonomy window commit, then gait compensation. Headless runs use a rounded simulated desktop origin. The trace measures the final result after compensation, including projected joint positions plus that origin; it does not substitute IK residuals for observed motion.

After acquiring a real simulated floor support, the sequence rests in authored idle, makes three alternating 360-pixel journeys with stops, then replaces a destination while already moving. This exercises idle → turn → walk → stop → opposite turn → walk, repeated phases and a nonurgent moving reversal. Planned final coverage is three rigs at 30/60 Hz and scales 0.6/1.0. The prior authored-idle and turn-only matrices remain separate milestones.

`joints.jsonl` records world quaternions, angular velocity vectors/accelerations and desktop projected steps for hips, torso, head, both arms and both legs. It also records gait/turn/ambient contact ownership and sole references. `analyze.py` summarizes every boundary and its surrounding frames without filtering high peaks. A claimed support epoch continues across owner changes when either owner still claims support; blending/unclaimed intervals are reported separately. The existing <=4-pixel support-drift engineering criterion applies only to actual claimed support, not to free swing.

## Reproduced baseline findings

- Slow walk release revealed an underlying clip through a second frozen-leg blend. A previously stationary shoe jumped to 189 then 268 degrees/s; knee speed rose from 5.7 to 124 then 177 degrees/s. Removing the competing blend and retaining contacts through the final slow samples reduced this example to shoe 0 → 0 → 0.01 degrees/s and knee 5.72 → 4.45 → 3.69 → 3.98.
- Moving destination replacement stopped desktop movement immediately, reducing a knee from 112 to 5 degrees/s. Nonurgent replacement needs bounded braking; urgent speech/drag stopping is a different contract. Motion's velocity cache also needed to use final post-window-compensation poses rather than the earlier pose pass.
- Beginning a turn during an existing blend initially reset knee speed from 42.7 to 1.49 degrees/s for one frame. Correct initial transition timing now gives 41.84 → 38.88 → 33.51 in the reproduced case.
- Turn completion leaves a one-frame ownership gap before the host starts the walk clip. The shoe jumps from 0 to 148 degrees/s (2.46 degrees in one 60 Hz frame), and the other knee drops from 34 to 0. The final turned pose must remain owned or enter a continuous transition until the next consumer applies it.

No universal biological acceleration threshold is inferred from these observations. Exact pose/velocity discontinuities, ownership changes and contact drift are reviewed separately, and all raw peaks are retained. A forthcoming Windows viewport sequence remains necessary for visual acceptance.

## Reproduce

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_transition_chain.gd -- --output /tmp/transition-chain --model cheval-grand --fps 60 --scale 0.6
python companion/diagnostics/transition_chain/analyze.py /tmp/transition-chain
```

The coordinator owns Windows runs. The probe supports the existing explicit `--realtime`, external `--test-root` and optional own-viewport capture arguments. No Windows session is launched by this review.

## Updated user requirement: concurrent turning and travel

The user clarified that completing a turn before beginning a walk is itself the wrong behavior. The serial candidate matrix in `development/serial-candidate-matrix/` is therefore a preserved development milestone, not final acceptance of the current request. Its six scale-0.6 functional cells pass and six scale-1.0 cells each expose an interrupted second journey. All twelve cells have zero meaningful turn/travel overlap; see `serial-matrix-overlap.json`.

Before testing the revised implementation, the coordinator agreed on these additional criteria: actual desktop speed >20 px/s and absolute heading speed >10 degrees/s together for at least 0.25 seconds per relevant transition, with at least 5 degrees of concurrent heading change. This excludes a tiny residual yaw tail after the turn has effectively finished. Existing projected support-drift criteria and explicit support coverage remain. A compatible finite gesture pair will also be queued before the outgoing gesture completes, measuring actual blend timing and joint continuity rather than merely checking the new gesture's name.


## Raw trace storage

Complete raw CSV/JSONL attempts are now stored under ignored `companion/logs/diagnostic-traces/`, so bulk debug traces are not added to Git. Each result directory has `trace_files.json` with the exact repository-relative local path, byte count and SHA256. `diagnostics/TRACE_STORAGE.json` indexes this relocation. No failed attempt was discarded. Earlier artifact descriptions refer to capture-time filenames; use these indexes to find the preserved files. Reports, checks and selected boundary evidence remain in diagnostics.

## Concurrent candidate matrix: functional pass, continuity revision required

The first frozen concurrent candidate is preserved under `concurrent-final/` (the directory name reflects launch intent, not the verdict). All 12 cells—three rigs, 30/60 Hz, scales 0.6/1.0—pass 312 functional assertions, all 60 meaningful turn/travel intervals, and all 36 finite pair scenarios. Every cell records identical source hashes before and after. The source-only independent measurement review approved this deterministic scope.

The pairs are wave→nod, nod→wave and wave→wave. Both live timelines advance for 0.5 seconds, channel weights and preview ownership remain coherent, and promotion/completion pass. Joint traces describe the actual output; they do not constitute a no-incoming-action causal ablation. Arm-only transition velocity carry fixed the measured final-wave release: the same Cheval 60 Hz world wrist now goes 121.799→117.354 degrees/s, with vector change 5.866, instead of 121.8→54.6 with vector change 91.5. Before/after development attempts remain indexed.

**REVISE:** unfiltered boundary review then found a distinct arrival phase stutter. Deeper inspection distinguishes held pose → one-frame pose step → held pose from a pose that jumps out and returns: the speed returns to zero, but the pose retains the step. Cheval at 60 Hz, scale 0.6, time 25.000: left upper-leg speed 23.60→218.75→17.52 degrees/s and left upper-arm 0→143.85→0 while the desktop origin stays at x=660. The gait reports driven on the step frame and false on the following frame; normal arrival follows at 25.05. Rice and Eishin reproduce the same class of defect. These passing functional checks therefore do not establish continuous motion, and the candidate is not final smoothness acceptance.

The authored-idle regression on this motion revision passes its 132 assertions plus six diagnostic records across three rigs and 30/60 Hz, using installed production contact metadata. Results are separate in `../authored_idle_review/concurrent-regression-*`.

After this matrix completed, the probe's inherited realtime pointer validity filter was corrected to count every measured chain stage except initial grounding. The candidate matrix is headless and unaffected; its original probe hash remains in each report. A later Windows run must use the corrected probe. Bulk raw traces are compressed under ignored logs with per-run `trace_files.json` hashes; none of the failing attempts were discarded.

### Focused phase-pursuit correction

The subsequent Cheval 60 Hz development rerun in `development/phase-pursuit/` confirms the identified cause is corrected: measured-distance target phase now feeds a continuous critically damped sampled phase. Exact first-arrival arm speeds become 43.10→37.14→36.99→38.97→37.43→34.08 degrees/s. `arrival-phase-before-after.json` preserves every frame in the same selected 24.9–25.1-second interval and hashes both complete raw traces. An exploratory detector of walk-arm held→step→held patterns (neighbor speeds <0.5, middle speed >30 degrees/s) drops from 106 to zero; this is a diagnostic comparison, not a newly invented biological pass threshold. The cell retains 26/0 functional checks, all five meaningful overlap intervals, and observed claimed 3D support drift 0.181 mm. Full-matrix approval awaits the coordinated final source freeze and rerun.

### Report storage

Dense reports and complete boundary/epoch analysis are also retained as compressed JSON under ignored logs. Each compact tracked report contains `full_evidence` with the local repository-relative path, compressed SHA-256, original SHA-256 and original byte count. Compact boundary summaries select the four largest joint angular-velocity vector changes explicitly; complete unfiltered boundaries remain in the referenced full evidence. `compact_reports.py` performs this relocation without deleting a previous attempt. Per-frame CSV/JSONL still use `trace_files.json`.

## Final phase-corrected matrix

`concurrent-phase-final/acceptance-summary.json` records 49,110 frames across three rigs × 30/60 Hz × scales 0.6/1.0. All 312 functional assertions pass. All 60 turn/travel intervals pass the prospective criterion, with 0.833–0.933 seconds and 39.6–47.3 degrees of meaningful concurrent rotation. All 36 finite pair scenarios overlap for 0.5 seconds. The diagnosed held–step–held arm pattern is absent in every cell. Maximum observed claimed support drift is 0.335 mm in 3D, or 0.110 projected pixels, including rounded simulated desktop origins. Per-cell support versus unclaimed/blending frame coverage is explicit.

All twelve cells share identical core script hashes and each records unchanged before/after sources. The main scene includes its completed props hooks, with empty default objects; independently changing props modules and object interaction behavior are outside this matrix's scope. The authored-idle regression in `../authored_idle_review/concurrent-phase-regression-*` passes 132 assertions plus six diagnostic records on the same motion revision.

The final verdict concerns the measured transition mechanism and contact continuity. It does not assert universally low derivatives or human biomechanics. Raw all-frame peaks remain visible: world head speed 94.61 degrees/s during a reversal, head acceleration 2026.36 degrees/s² during initial idle acquisition, heading speed 70.00 degrees/s and heading acceleration 100.05 degrees/s². Swinging feet can turn at roughly 310 degrees/s; those samples do not claim planted support. Quiet authored-head gates are covered separately by the authored regression, rather than relabeling acquisition or purposeful turning as quiet. The support references are kinematic ankle/rest-sole points, not full collision/friction or skinned-mesh sole physics. Windows viewport sequences must provide the final visual judgment.

## Latest authored walk replacement matrix

`uma-walk-final/acceptance-summary.json` supersedes the prior phase-corrected motion milestone for the selected walk source. All 12 cells pass 348 assertions, all 60 meaningful concurrent turn/travel intervals and all 36 finite gesture pairs. The probe loads production manifest entries through the real main asset-ready callback, verifies that priority selects `uma_walk`, verifies registered hip preservation, and checks neutral vertical navigation gaze across every nonseated anticipate/walk/arrive frame. The selected original-Unity-quaternion asset SHA-256 is `8f0b44c9fbee138f9923185a6dc373e0a11349c7d20c523163c941ebfe329573`.

Measured actual head pitch during established walking is -1.020° to 2.228° (positive downward), across all three rigs, scales and frame rates. This selection requires state `walk`, active clip `uma_walk`, and at least 0.5 seconds since clip start; acquisition is explicitly excluded from this posture statistic and retained in full traces. The comparable source-only ablation is documented separately: old source 13.40–17.05° downward versus new source -0.875–2.085°. Source-only and actual integrated measurements are not presented as identical experiments.

Centered authored hip motion remains present in the final pose. Claimed contact drift remains at most0.314 mm in observed 3D, or0.103 projected pixels including rounded simulated desktop origin. The previously diagnosed isolated arm phase stutter is absent in all cells. All cells have identical core hashes, unchanged before/after sources, and the same installed asset/manifest. Authored-idle regression remains 132 passing assertions plus six diagnostic records in `../authored_idle_review/uma-walk-regression-*`.

APPROVED for this measured integration scope. Existing fast unclaimed swinging-foot turns remain visible in the raw boundary report; this is not a global acceleration or human-biomechanics claim. Windows visual acceptance remains coordinator-owned.

## Subsequent standing-bounds check

The calibrated seated-bounds follow-up is in [pose-bounds-standing/INDEPENDENT-REVIEW.md](pose-bounds-standing/INDEPENDENT-REVIEW.md). Its three 60 Hz, scale-1 standing cells pass 99 assertions, and their complete frame CSVs are byte-identical to the corresponding UMA matrix cells. This verifies standing nonregression and bounds-selector cleanup; it does not establish actual chair attachment. The additional full traces/reports are included in `../TRACE_STORAGE.json` (279 indexed evidence files at this update).

## Final seated-floor/cache standing nonregression

The frozen-source follow-up in [final-seat-floor-standing-callbacks/INDEPENDENT-REVIEW.md](final-seat-floor-standing-callbacks/INDEPENDENT-REVIEW.md) passes 102 assertions across the three rigs at 60 Hz and scale 1.0. It directly invokes the real secondary-pose cache callback for every frame while verifying that the standing floor constraint remains inactive. Complete frame CSVs are byte-identical to both the UMA matrix and prior bounds-regression cells. The initial 99-check rerun is separately preserved. This is source-level deterministic evidence, not an active Windows spring/furniture/world-reader test.
