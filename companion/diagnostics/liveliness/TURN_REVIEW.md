# Turning: separate baseline disposition

REVISE for turn quality; the passing quiet/stance baseline does not approve stationary whole-body turns or interrupted pose velocity continuity.

Exact selected raw rows are preserved in `turn-baseline-peaks.json` from the authored Cheval 60 Hz trace. At 132.30 seconds the head reaches 155.244 degrees/s, torso approximately 140 degrees/s, while the desktop origin remains x=674 and both gait stance flags are false. The avatar is swiveling in anticipation. The stance metric excludes turns and therefore cannot establish grounded support during this action.

At 133.1167 seconds, during drag preemption, head acceleration reaches 2331.65 degrees/s². Skeleton-space head speed falls from 37.865 to 0.0756 degrees/s in one frame. This is an interrupted pose transition, distinct from whole-avatar heading and from the settled quiet-head criterion. Stopping OS travel immediately passed; continuous body motion on interruption needs separate verification.

Current heading code targets ±82 degrees based only on lateral velocity, caps speed at 140 degrees/s and acceleration at 360 degrees/s², and rotates the whole avatar around its presentation anchor. It contains no step-turn foot support contract. Lowering the rate alone cannot validate a planted-foot pivot.

Proposed scoped engineering gates, to agree before the revised run:

- Record explicit avatar yaw, heading velocity and acceleration, desired heading, actual window velocity and projected sole references on every frame. Preserve unfiltered body/head derivative peaks.
- Bound deliberate heading to 90 degrees/s and 180 degrees/s² at 30/60 Hz, including target reversal and return to front. These are product tuning gates, not biological norms.
- Hold desktop departure until heading is within 15 degrees of the intended path, or explicitly animate a turning step; record anticipation lead separately from a static gaze target.
- A stationary turn must identify a support foot and retain that observed projected foot within 4 px while the other foot performs a visible repositioning step. Do not count intervals with both stance flags false as passing support evidence. If the implementation cannot provide that behavior, report the limitation and prefer smaller oblique headings.
- Evaluate travel and interruption pose continuity separately from emergency OS stopping. Record each joint velocity before/after interruption and compare against a predeclared bounded blend; the baseline 37.865-to-0.0756 degrees/s head velocity drop must not be hidden by classifying the frame as nonquiet.
- For user-requested use of depth, require evidence of a coherent 3D path/heading and perspective or orthographic projection contract before treating Z motion as gait improvement. Added Z alone does not establish contact support or naturalness.

No turn screenshots were captured by this headless matrix. The coordinator owns the forthcoming Windows viewport sequence. Numeric baselines establish the mechanism, not its visual acceptability.


## Revised runtime numerical disposition

The final lifecycle-fixed implementation passes the prospective heading, departure and observed fully weighted support gates across all three models at 30/60 Hz (240 checks/0failures including existing main integration checks). Explicit mid-turn speaking preemption also passes. See `turn-summary.json` and README for exact coverage and raw acceleration limitations. The former REVISE findings are addressed at the mechanism level by acceleration-limited heading, alternating 3D support/swing targets, heading-ready departure and outgoing joint-velocity carry. This numerical result does not replace the pending Windows visual acceptance.
