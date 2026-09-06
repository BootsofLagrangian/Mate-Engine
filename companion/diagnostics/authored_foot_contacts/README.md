# Authored seating contact retargeting

The installed UMA `sit_enter` / `sit_idle` / `sit_exit` rotations and pelvis timeline remain the primary motion. This change compensates contact for a different furniture seat height and the admitted 1.20× backward staging path. It does not replace the source with a procedural sitting animation.

`MotionPlayer.seated_transition_requirements("enter")` now supplies `source_seat_clearance_local` and the full `source_full_endpoint_hips_local`. The clearance uses the canonical source endpoint underside, full source hip translation, and measured rest sole floor. It does **not** subtract source frame zero's preparatory bend. The host may use this for newly created furniture; existing user-configured furniture is not resized by the motion layer.

`AuthoredFootContacts` captures a fixed live/source reference at entry and exit. Planned contact preserves source foot X/Z displacement and subtracts the host root displacement on the same source timeline. Foot lift releases contact between 1.5% and 4% of target leg length; source pitch and roll remain live. An existing two-bone LegIK corrects the ankle while preserving that foot basis. Acquisition fades contact ownership, while a signed floor constraint prevents fading a shoe through the floor. The correction spends its bounded vertical budget first and limits the remaining X/Z vector so its total norm cannot exceed 20% of leg length. Requested limits and actual reach errors remain observable, including unreachable/high-chair cases.

The runtime skins at most 26 cached directional shoe-support vertices per side, including lateral corners; it does not skin the full body each frame. This directional set is an approximation, **not a mathematical enclosure of arbitrary deformations**. The acceptance probe separately skins every foot-influenced shoe vertex on both sides and checks actual geometry throughout the tested trajectories. Four heel/toe markers remain separate source/live telemetry. Missing/model-replaced/cancelled ownership clears references. Bounds samples reuse the same fixed reference and contain no contact integration state.

## Final measured scope

`normal-final.json` and `oblique-final.json` cover 48 complete finite paths: Cheval, Rice, Eishin × 30/60 Hz × source-compatible/0.48 m seat clearance × scale 1/yaw 0° or scale 0.6/yaw 65°. Each path uses 1.20× source X/Z travel and includes seated/standing hold and entry/exit handoffs. Both runs have zero failures. Gates remain full-shoe penetration <1 mm, acquired source-relative contact residual <3 mm, no correction-limit frames, and endpoint marker displacement <3 mm.

- Worst finite-path full-shoe penetration: 0.081 mm; subsequent hold: 0.186 mm.
- Worst acquired source-relative XYZ residual: 0.724 mm. This includes retained reach-limited numerical behavior; it is not claimed to be exact planted contact.
- Worst entry/exit handoff marker displacement: 0.340 mm.
- Peak measured Motion processing in these headless runs: 1.922 ms. This excludes diagnostic full-shoe skinning and does not establish packaged Windows frame timing.

`mini-final.json` deliberately retains four failed exact-contact cases on Mambo at 30/60 Hz with 1.20× source X/Z. The strict 20%-leg correction cap is reached, leaving up to **2.868 mm** source-relative residual. Whole-shoe penetration stays below 0.199 mm and handoffs below 0.064 mm. The earlier approximately 1 mm estimate preceded the total-vector-budget fix and is superseded. The cap was not enlarged to pass this case. Unextended source staging is an option only if the host's actual furniture collision admission allows it; this report does not claim that admission.

A source-compatible miniature seat clearance (0.0909 m on Mambo) also exposed an old fixed 0.25 m API minimum. The existing clearance range now scales with target rest hip height, preserving the previous limits on the reference 0.90387 m rig.

Independent review artifacts in this directory cover signed downward correction, zero ownership, clear source lift, forward/reversed/out-of-order phase sampling and replay after bounds preparation, and the total correction norm under an oversized diagonal request. See the reviewer's decision for its exact scope.

## Reproduction

Run from `Mate-Engine/`:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_authored_contact_path.gd
CONTACT_SCALE=.6 CONTACT_YAW=65 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_authored_contact_path.gd
CONTACT_MINI=1 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_authored_contact_path.gd
DISPLAY=:0 MOTION_RENDER_DIR=/tmp/authored-contact-render WALK_CHARACTER=cheval-grand companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script res://tools/render_authored_contact_path.gd
```

The mini command intentionally returns failure for the disclosed correction-limit cases. Normal and oblique commands return zero. Preserve `/tmp/authored-contact-path.json` between normal/oblique runs because the tool uses a shared output path.

`source-hashes.json` records runtime and probe identities. `render-provenance.json` identifies all 130 actual Cheval viewport frames and the contact sheet retained under `companion/logs/diagnostic-traces/authored_foot_contacts/render/`. The inspected sequence shows preparatory bend, backward seat loading, and forward trunk rise with shoe/floor alignment. It is Linux viewport evidence, not Windows acceptance or proof of all-rig visual naturalness.

Failed exploratory attempts are preserved under `companion/logs/diagnostic-traces/authored_foot_contacts/`: the two-point lateral sole miss, acquisition-floor fade penetration, incorrectly nonnegative floor clamp, and miniature fixed-clearance rejection. `probe_authored_contact_mesh.gd` is an early **left-foot exploratory** tool; it is not the final acceptance probe. The final path probe checks both full shoes and explicitly rejects floor-setup failure.

Both Windows temporal probes now record `authored_foot_contacts` on every rendered telemetry row, alongside source/live heel/toe points. Their 20 Hz timing and physical handoff gates, bounded capture queue/loss gates, and asynchronous PNG provenance remain unchanged. Actual packaged trajectory, readback cost, furniture collision, and secondary garments still require the root-owned Windows run.

## Subsequent packaged timing investigation

`windows-grounded-analysis.json` preserves the actual Windows run identity and its failed 57/52 ms interior timing gates. Heel heights improved to approximately 2–3 mm above the fixed physical floor, with no correction-limit flags. The 30 px exit window-origin change was a transparent reframe: projected ankles moved 0 px and true heel/toe positions moved at most 1.75 micrometres at that boundary. Later floor adoption is a separate host issue.

The entry preparation boundary was 256 ms, followed by an initial source-time jump of 0.133306 s. The trace does not attribute that entire cost to Motion. There is no `check`/report serialization call in the entry interval; exit preparation includes a diagnostic check. Added source-only counters split reference, pose/contact samples, secondary samples, mesh-bound measurement and total. `preparation-profile.json` retains 24 passing normal paths and measured 43–60 ms Linux preparation; this is not a Windows result. Bounds preparation now restores contact diagnostics as well as live pose, preventing a time-zero row from incorrectly exposing the last sampled endpoint.

The original mini limitation applies specifically to **Mambo**. A subsequent unchanged-cap **Hachimi** fixture at 30/60 Hz passes all four enter/exit paths: no limited frames, maximum source-relative residual 0.000086 mm, whole-shoe penetration 0.238 mm, handoff displacement 0.051 mm. See `hachimi-mini.json`, copied `hachimi-probe.gd` and its exact provenance. This character-only diagnostic does not alter frozen runtime or Windows probes.

## Cold-cache load ordering

The subsequent packaged `windows-scene-navigation-union-timing` run isolated first entry preparation: reference 102.431 ms and bounds 146.762 ms (131.062 ms in measurement), total 249.224 ms. Exit used reference 0.232 ms and measurement 37.011 ms, total 53.816 ms. Registration could happen before the avatar existed; the former registration-only warmup then did nothing.

Model identity initialization now completes immutable shoe/bounds input warmup when seated clips have already registered. Registration still handles the inverse order. The warmup does not capture a future transition's outgoing pose or reuse an invalid live bound. `prewarm-final.json` tests all three normal rigs with clips-first, model-first, and replacement ordering: 9/0, both input caches ready before sitting, exact pose-matrix/origin difference zero, reference preparation at sitting at most 0.295 ms. Initialization cost moves to model readiness; warm live bounds still take tens of milliseconds. This is a load-order/cache fix, not a demonstrated universal 50 ms Windows frame guarantee. Actual root-owned exported rerun is required.

The initial prewarm fixture's `Quaternion.angle_to` self-comparison produced a nonzero `acos` rounding artifact on identical stored poses. Its failed result is retained as `prewarm-angle-metric-rejected.*`; the final fixture compares the actual transform columns and origin directly, without loosening a pose tolerance.
