# Native integration acceptance — 2026-09-07

The generic native desktop companion is connected through the local LM, supplied dedicated voice, native skill execution and result feedback. This record distinguishes actual Windows observations from isolated geometry and physics tests; it does not certify every rig, layout or full garment collision.

| Capability | Verified evidence | Scope |
| --- | --- | --- |
| Product-default Korean text → Japanese voice → computer use | `text_scenarios/windows-computer-product-completed.json`, 7/0 checks | Export a3bb28a4; actual local model, 81,280 PCM bytes, one completed native terminal and backend acknowledgement. First text476ms, first PCM at backend1089.8ms. Native playback1.283s; physical travel/playback overlap0 in this short-acknowledgement trial. |
| Complete workstation choreography and contact | `scene_navigation/windows-computer-restored-completed.json`, 74/0 | Earlier export663d320c: setup, authored entry, lift/swivel/roll, use, authored exit, actual10cm step-away, empty-chair restoration, exactly one completed terminal, five-second XYZ hold with zero drift. |
| Motion phase timing | `scene_refresh_timing/WINDOWS-CACHE-COMPARISON.md` | Chair entry/exit30/30ms; computer26/31ms maximum interior gaps, against unchanged50ms gates. Cached projection requests44–76µs avoid repeated fullvertex fit. Preparation and asset/planning boundaries are separate. |
| Source integration | Latest native selftest634/0; independent component reviews | Full actor-turning route envelope, same-monitor segment admission, exact obstacle union, source-relative foot correction, held seated transport and bounded rigid-body/lift volumes. |
| Transparent depth, motion blending and autonomous idle | Prior actual Windows tests47/0,31/0,13/0 | Perspective furniture depth/crops; authored walk plus upper-body gestures and overlapping action handoffs;150s product-default autonomous exploration with genuine X/Z trips. See existing desktop_view, motion_seams and scene_navigation evidence. |
| Codex work harness | `work_jobs/`, actual native job18/0 | Brief acknowledgement playback, actual Codex tool progress, exclusive file creation/readback and result playback. Native audio signals are not acoustic-onset measurements. |
| Portable characters and variants | `character_package/`, `avatar_variants/` | Five installed packages; four actual Mambo/Hachimi wet/default LM turns verified loaded hashes, native outcomes, supplied voice and feedback. |

## What changed

The engine retains the outgoing pose and velocity through0.45s motion blends. Authored sitting/standing follows the source contact path with bounded foot correction; chair transport holds the seated body clip while additive leg lift keeps feet clear. The host completes the entire owned interaction before reporting success, including walking away from the empty chair before restoring it.

Planning and runtime now use the same conservative world-axis bounds. Placement includes the actor target hull and checks the complete all-heading approach route within one monitor workarea per segment. A fresh route is revalidated before ownership commits. Initial legacy-to-scene normalization is bounded, stays on the same ground, checks solids and records displacement; already scene-owned feet remain exact. Live entry still checks its actual outgoing pose, velocities and blended bounds.

Unchanged native prop projection is cached with camera, transforms, mesh revisions, setup and crop invalidation. Scene interests are suppressed during finite furniture ownership and rebuilt after committed ground returns. Generic text-scenario snapshots preserve terminal-time fit, object, foot, route and camera evidence without changing the model prompt.

## Remaining limits

- Initial spatial planning is synchronous. A difficult recorded fixture needed six full candidate plans and about2.45s locally; the successful actual product run needed two validated candidates. A target-only prefilter was measured and would reject none of the expensive detour cases, so it was not added. This is a remaining setup responsiveness limit, not hidden by phase-only frame gates.
- Motion preparation remains about51ms on the measured Windows case. The accepted interior timings are not a universal no-stall guarantee.
- Production garment physics remains imported VRM springs with existing startup rebasing. The corrected automatic22s cape comparison covers idle, walk,110°turn, sitting/standing and reload. Candidate gravity1.2 produces71.19mm maximum stand-up tip movement versus26.09mm baseline and was independently rejected for default adoption. Existing settings remain. See `physics_cloth/CAPE-CONTINUOUS-ACCEPTANCE.md`.
- Body capsules approximate the rig and exclude hands, hair, clothes and accessories. Cloth/backrest penetration, full costume wrinkles, and authored hand-pulling of chairs are not solved by these proofs. Furniture preparation is automatic digital manipulation.
- Mambo source-contact correction retains a bounded2.868mm residual in its separate fixture. Hachimi has a separate passing fixture; do not attribute Mambo's limitation to both rigs.

## Provenance

Actual runs and raw captures remain under ignored `logs/` with executable, build and external-script identities. Failed runs are retained: the first carrier attempt failed final restoration; product-default attempts separately exposed setup-envelope and approach-view failures. Compact evidence records preserve these instead of replacing them with later successes. Full physics videos and raw paired traces remain in ignored research assets; selected images, metrics, exact source hashes and independent reviews are tracked.

`run_text_scenario.py --product-defaults` launches the exported application through the real send-chat path. Expected results never enter the model prompt. The native job probe exercises the real work-agent path. Both restore original settings. The normal launcher is `native/build/Launch-Mate.cmd`; final launch configuration and health are recorded separately under local logs.
