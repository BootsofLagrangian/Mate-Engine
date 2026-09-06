# Independent transition-chain measurement review

2026-09-06. **APPROVED for the deterministic headless chain measurement scope.** Realtime controlled-run validity remains **REVISE** pending the pointer-stage correction identified below. Source review only; no new matrix execution or runtime edits.

Reviewed latest `probe_transition_chain.gd` and `analyze.py` additions for concurrent turn/travel and generic wave→nod, nod→wave, and wave→wave overlap. The probe executes actual main methods in the declared Motion→main→autonomy order with final frame-move compensation, but disables automatic scene processing and explicitly steps it. This is actual-main wiring under controlled stepping, not unrestricted production processing or spring-bone acceptance.

Seventeen joint transforms include skeleton global transform and avatar scale; rotations are orthonormalized before differentiation. Desktop projections add the committed rounded window origin. The equivalent 3D desktop-world offsets divide by base camera pixels/metre, appropriately avoiding a second avatar-scale correction because the global joint positions already include that scale. Support epochs retain ankle and sole-reference positions, owner coverage, and unsupported/blending frames. These references are not a full skinned-sole collision measurement.

Concurrent-turn/travel analysis retains raw-frame qualifying time and the separately disclosed trailing ~100 ms committed-position speed criterion. The >=0.25-second / >20 px/s / >10 degrees/s / >=5-degree rule is explicit. Its rolling speed is not instantaneous speed and may include the preceding stage near a boundary; claims should retain the stated interval definition. Raw traces allow review without that classification.

Finite-pair checks require meaningful pre-end overlap, multiple frames with both timelines advancing, complementary outgoing-channel masks, active preview priority, promotion and completion. Actual joint boundaries and raw velocity/acceleration are retained without a biological-smoothness gate. Observed joint motion is descriptive rather than a causal no-incoming-clip comparison, as the analyzer correctly states. Optional future strengthening: evaluate the union of incoming/outgoing mask keys if adding unequal mask schemas.

The author identified inherited pointer-interference counting restricted to `quiet_idle`/`directed_walk`, which are absent from the new chain scenarios. This does not affect the deterministic headless matrix, but could incorrectly label a realtime run controlled. Require all relevant chain stages before using realtime `controlled_run_valid`. Preserve the completed matrix and disclose a probe-only hash change if correcting afterward; raw per-frame pointer flags already remain available.

No blanket naturalness approval, final matrix result validation, or final Windows runtime acceptance is conveyed here.

## Pointer amendment and final summary scope

Verified pointer counting now includes every non-initial-grounding scenario. The realtime metadata blocker is closed; no realtime execution is implied. Inspected `concurrent-phase-final/acceptance-summary.json`: its scope explicitly states deterministic actual-main ordering, rounded simulated origins, three rigs at 30/60 Hz and scales 0.6/1.0, excluding active props. That scope is appropriate. This follow-up checks the source amendment and summary wording, not an independent recomputation of all dense matrix traces or blanket naturalness acceptance.

## UMA walking-posture measurement amendment

**APPROVED for descriptive posture scope.** Reviewed actual asset-ready callback use, production locomotion selection/hips capability checks, navigation gaze target-Y assertion, global rest-relative forward pitch and hips-offset recording. Target-Y alone is not proof of level actual head posture; the separately selected posture statistics measure that. The analyzer explicitly excludes the first half second of each observed `uma_walk` name run. Its age derives from gesture-name changes, not an explicit clip restart timestamp; use that wording or record clip start when evaluating same-name restarts. This source review does not independently validate the new matrix's results.
