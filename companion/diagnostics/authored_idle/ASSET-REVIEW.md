# Independent asset tooling review — 2026-09-06

**APPROVED for the bounded local extraction and prototype conversion scope.** No blocking correctness or source-mutation issue found in the reviewed fixed-input workflow. This is not approval of final runtime motion quality, full Unity animation fidelity, or redistribution of the extracted game assets.

Reviewer: independent face/assets agent; did not implement the reviewed extraction, converter, or runtime changes. Reviewed `export_uma_subset.py`, `AssetStudioSubset.cs`, `UMA-EXTRACTION.md`, `convert_overte_fbx.gd`, `convert_candidates.py`, `bake_humanoid.py`, `sample_unity_curves.py`, the authored probes/render scripts, and relevant `VrmaClip` translation/ambient consumption code.

## Evidence and findings

- The exporter selects exactly 32 motion bundles plus one rig, requires every input, rejects a nonempty output, copies inputs, and loads only the copied bundle directory with dependency resolution disabled. Source bundle access is read-only. Renderer references are cleared on deserialized objects in memory; no original bundle is serialized back. The default native DLL destination is the workspace .NET host, not the original F: installation. CLI working directory is the new helper directory.
- The completed `natural-subset/manifest.json` records 33 sources and 65 outputs with `complete=true`. Independently recomputed all 65 output hashes: all match. The recorded helper hash differs from the formatted tracked helper, but the preserved executed helper and tracked helper are identical after removing comments/whitespace. The extraction document explicitly discloses the later formatting and two-clip rerun. I did not rerun Windows extraction or independently rehash all original F: bundles; the completed exporter records that source recheck.
- Rig local TRS is preserved separately from AssetStudio's FBX basis conversion. The explicit metre conversion and rejection of non-unit scales/matrices in the humanoid bake prevent silent scale loss for the inspected inputs. Animated unmapped ancestors are composed into mapped child transforms before collapsing the hierarchy. This is a materially sound correction over discarding animated helper nodes.
- The Overte calibration trim has a source-specific rest-match and large-first-jump guard. Intermediate source remains available. It does not silently trim every clip. The FBX bridge uses Godot import/export and propagates returned errors; it is a conversion probe rather than a claim of Unity-equivalent interpolation.
- Unity curve sampling implements time-scaled unweighted Hermite interpolation, normalizes sampled quaternion components, and explicitly refuses weighted curves. Five existing focused tests pass (helper folding, eased interpolation, time units, constant tangents, weighted rejection). These tests do not establish whole-clip parity with Unity.
- Candidate probes measure finite poses and contact displacement; the ambient probe checks feet in skeleton space and hips activity. Render scripts capture only their own viewport. These are appropriate prototype diagnostics. Static snapshots and manually stepped motion are not production frame-order, spring-bone, interruption, or naturalness acceptance.

## Scope limitations and optional follow-ups

1. `REPORT.md` and `convert_candidates.py` still describe runtime playback as rotation-only and state no runtime changes. That accurately describes the original prototype stage but is stale as a present-tense account. Date/label that stage or update it before using this report as the final feature description.
2. The bake preserves mapped non-hips translations in VRMA, but the current runtime consumes hips translation only and retargets the remaining joints through normalized rotations. It therefore preserves helper rotation influence, not exact source world positions. Contact IK deliberately changes source leg poses. Keep this distinction in visual claims.
3. `sample_hips_offset()` assumes root-level hips in metres with compatible axes, normalizing by rest hip height. This is justified for these explicitly baked candidates; it is not a general arbitrary-VRMA translation implementation. Translation tracks also do not independently extend clip duration. These selected baked files share sampling times with rotations, so neither issue blocks this subset.
4. Full reproducibility would benefit from hashes for the Python exporter, FBXWrapper and other loaded managed dependencies, compiler, and Godot binary in addition to the currently recorded tool hashes. The fixed helpers and preserved intermediate outputs already make the present run auditable.
5. Explicit path overrides are trusted operator inputs: choosing an F: .NET host can cause the documented adjacent native-DLL copy there, and choosing an output under another original installation is not prohibited. The default reviewed invocation writes only to workspace outputs/tools; the no-original-mutation claim should retain that scope. C# clip filenames likewise rely on the inspected fixed bundle subset, not arbitrary hostile bundle names.

No original game data was edited or redistributed by this review. No runtime edits were made. Final selection of generic home idle and rare character start/loop/end actions remains the motion/coordinator acceptance task.

## Windows authored probe review — initial run

**REVISE the completion assertion before final acceptance.** This verdict applies to `native/tools/probe_windows_authored_idle.gd`, not the approved extraction helpers above.

Reviewed the initial `logs/windows-authored-initial/report.json`: 24 checks, zero recorded failures, 162 saved own-viewport frames, three distinct profile action names, and no accepted start/action/done/error events. Independently viewed frames 00036, 00088, and 00142. They show coherent Cheval hand-to-hat, Rice folded-arm, and Eishin hands-together poses respectively; they do not establish smooth transitions or final runtime quality.

The probe instantiates the actual production scene, lets normal process/render advance, and captures its own root viewport after frame-post-draw. It does not manually advance the motion player or read unrelated desktop pixels. Advancing the idle-action deadline and injecting a user rest intent are correctly disclosed. The evidence demonstrates that the production scheduler can dispatch profile actions under those controlled conditions; it does not measure natural scheduling frequency.

The material gap is the check labelled “finite action returns to base”: `action_name.is_empty()` also succeeds after cancellation or ownership loss. Require observed action progress close to its expected end (or an explicit normal-completion reason), followed by `uma_home_idle` with active blend weight. Also clear per-rig action observation immediately before advancing the deadline, so an earlier occurrence cannot satisfy the intended trigger observation. Initial action-bearing frames span about 3.50, 4.20, and 3.97 seconds respectively, but the report does not record action time/duration to independently establish natural completion.

Normal-path cleanup disconnects the owned websocket, stops the owned world helper, disables autonomy, restores the copied settings dictionary, and flushes it before quitting. Failed boolean checks still reach cleanup. An unexpected script exception is not guarded; a common cleanup/abort path for readiness or output-open failures would improve robustness. No synthetic input is held that needs release. Output directories should remain distinct for preserved evidence; the current explicit output path can overwrite an earlier run if reused.

The separate `probe_windows_intent.gd` change from exact clip count eight to `walk` presence plus `_vrma_pending == 0` is APPROVED for that walk/intent test. It accommodates the expanded catalog without requiring unrelated assets. It establishes required walk readiness and fetch completion, not successful loading of every catalog entry.

No Windows process was launched by this review. Final Windows runtime acceptance remains pending the motion fixes and revised probe rerun.

### Completion assertion revision

**APPROVED as revised.** Re-read the updated probe: action progress is sampled before the 200 ms image-capture gate, selected-action observations/progress are cleared immediately before the deadline advance, and return now requires an empty action name, progress within 0.2 seconds of source duration, the home loop selected, and blend weight above 0.95. Per-frame action time and maximum progress are included in the report. This resolves the premature-cancellation false positive identified above to the stated 0.2-second tolerance; it is not an exact completion-reason assertion.

The initial 24/0 report remains historical and does not retrospectively satisfy the new assertion. No rerun was performed during this review; final evidence must come from the frozen-runtime Windows rerun. Prior optional cleanup/provenance limitations remain unchanged.
