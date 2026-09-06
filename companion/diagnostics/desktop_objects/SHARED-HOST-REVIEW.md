# Independent shared furniture host review

2026-09-06. **REVISE post-commit transform timing; combined-view fit remains unverified.** Read current `desktop_objects_host.gd` and main integration without runtime edits or Windows launch. Calibration and contact-scene implementations were reviewed separately.

Shared furniture uses the pet's actual World3D/camera, uniform physical scale from object pixels/metre versus camera pixels/metre, a desktop-floor reference, and a depth translation placing the furniture seat at the calibrated avatar seat depth. Workstation facing derives from the arrangement's world direction; both hand goals use shared world keyboard sockets. Canonical posed bounds are transformed into current avatar space for seated work-area admission. These are consistent contracts, not merely an assumed overlay.

**Required frame-order correction:** `_update_contact_transform()` currently runs at the beginning of `objects.tick()` during main processing. The autonomy child commits the window's position afterward. Thus furniture geometry retains coordinates computed against the previous native-window origin during that rendered frame, despite claiming a fixed desktop-floor position. Update its transform after the actual window commit, analogous to final gait compensation, and keep socket/support metadata coherent without a reentrant move. Otherwise moving approach/seat frames can shift the furniture by each committed displacement.

**Fit concern requiring evidence or correction:** activation shifts transparent window space to center the avatar pivot, preserving existing avatar desktop coordinates, but does not fit the combined avatar/furniture geometry. `contact_bounds()` is not consumed by main's fitting code. A wide sofa/workstation can therefore clip against the root viewport even when each separate object window previously fit. Inspect actual shared captures and reject or fit arrangements that do not fit; source AABB availability alone is insufficient.

Cancellation clears interaction state before callbacks, releases/frees the shared scene, reverses the stored transparent-window reframe, restores the standalone furniture, cancels navigation and stands up for occupied states. Model/foreground/disable/pet-drag handling remains explicit. Source restoration logic is coherent, but final shared-stage cancellation and shutdown must be exercised; earlier separate-window tests do not establish this new path.

The canonical seat anchor is a calibrated static contact reference. It does not guarantee all garment/skinned vertices stay above a cushion, and physical default-scale admission can legitimately reject a seat. Preserve that distinction when interpreting the active development run. No final Windows or anatomical contact verdict is supplied here.

## Development run 2 investigation

**REVISE: wrong support identity accepted as object contact.** Post-commit contact-transform callback and combined viewport admission have now been implemented, addressing the original source findings. However, the actual `windows-objects-shared-dev2` record exposes a separate material failure.

At approximately 83.1 seconds, computer use reports attached support kind `window`, surface ID `window:22408:104CC@...`, and screen point near (1666,202). The intended object's keyboard is near y=1200. During the preceding seating stage, root Y moves from 672 to -360 at roughly the configured 75 px/s. That is consistent with navigation to an unrelated window support, not proof of an instantaneous fit-feedback displacement. Chair contact measured 0.41 px error; it does not validate the computer path.

The host currently promotes `seating` to `using`/`seated` on generic `_sit_attached`, without requiring the requested `object:<id>:seat` identity. Require that identity before promotion and throughout occupancy; cancel or explicitly retry when the intended support is lost. Otherwise unrelated support can count as furniture attachment.

A plausible loss trigger in source is the anchor-only `_validate_support()` comparison `seat != current`: exact dictionary equality is applied to freshly projected floating-point seat coordinates, while ordinary surfaces use a 0.1 px tolerance. Per-frame world/pixel round trips can change those coordinates slightly. This hypothesis should be checked with field deltas; use a bounded coordinate tolerance while preserving the intended locked contact, not a blanket permission to follow moving furniture. Wrong-support rejection is required independently of this hypothesis.

The approximately 1069 px seat error and 3 m wrist errors are genuine failures in the retained run. No shared-feature approval until the corrected path is exercised and visually inspected.

## Owned-seat correction review

**APPROVED for the bounded support-identity fix, not the complete furniture feature.** Re-read the 0.1 px coordinate comparison, retained original seat reference, `_seat_contact_owner` fallback lock, and host identity guards. Loss of an owned seat no longer permits generic support acquisition while sitting; explicit cancel or returning to foot pose clears ownership. Seating promotion and continued seated/using states require the exact requested object-seat surface. The host also rejects loss of the matching pending contact before attachment.

Focused fixture source covers oscillating 0.0001 px projection noise, actual moved-seat detachment, ten seconds without unrelated fallback, and wrong-support rejection in occupied stages. The retained development-3 record confirms the computer no longer exhibits the ~1069 px displacement: calibrated seat error is 0.400 px. Its hand errors remain 0.0263/0.0285 m and are correctly failures; sofa admission also remains unresolved. These failures must not be absorbed into this bounded support-fix approval. No new Windows run by this reviewer.

## Final-package Cheval chair/sofa visual checkpoint

Independently inspected `windows-objects-floor-v2-cheval-full/chair-shared-depth.png` and `sofa-shared-depth.png`. **VISUALLY APPROVED for these two static contacts at Cheval scale 0.6.** The furniture now has coherent proportions relative to the avatar; pelvis/thigh placement meets the cushion, boots align plausibly with the furniture floor line, and shared-depth occlusion is credible. The earlier oversized presentation is absent. Report snapshot records shared seat-anchor errors of 0.919 px and 0.423 px respectively, with no failures at inspection time.

The run was still completing occupied mutations/computer use. This checkpoint does not approve those pending cases, the other two rigs, or continuous transition quality. It is specifically an inspection of the two actual packaged root-viewport images, not an assumed composite or standalone design render.

## Completed Cheval packaged run

**APPROVED for the completed Cheval scale-0.6 case.** Independently read final `windows-objects-floor-v2-cheval-full/report.json`: 100 checks, zero failures. Occupied move/resize/hide/remove, explicit user stop, finite computer completion, idempotent owned-window cleanup and settings restoration all pass. Computer use records both wrists reachable, world residuals approximately 1.79e-7/1.37e-7 m, and calibrated seat error 0.408 px. Exactly one matching use outcome is `completed`.

Independently viewed `computer-use-shared-depth.png` in addition to the prior chair/sofa images. The seated user faces the screen, hands meet the keyboard, the chair visibly supports the pose, and the arrangement renders with coherent shared depth and scale. This closes the previously failed Cheval computer case. Other-rig acceptance remains pending; this is not a claim of general cloth collision or every possible object scale/placement.

## Completed Rice packaged contact run

**APPROVED for Rice scale 0.6 contact-only acceptance.** Independently read `windows-objects-floor-v2-rice/report.json`: actual Rice model identity and scale verified, 55 checks with zero failures. Chair/sofa calibrated seat errors are 0.686/0.281 px; computer seat error is 0.850 px. Both wrists are reachable, with zero reported projected residual and world residuals 2.98e-8/4.47e-8 m. Exactly one matching computer use completes. Explicit chair stop, owned-window shutdown and settings restoration also pass.

Independently viewed all three actual shared-depth root-viewport captures. Chair and sofa proportions are coherent, the seated thighs/pelvis meet the cushions without the prior large apparent float, and boots align plausibly with the furniture floor. The computer view places the hands at the keyboard and the seated body toward the display. Rice's long ribbon ends bend outward near the floor and trail behind the chair; these frames do not establish general garment/furniture collision. No visual blocker in these three captures.

This contact-only run does not repeat Cheval's occupied move/resize/hide/remove matrix. Other rigs and scale 1.0 remain outside this verdict until independently inspected.

## Completed Eishin and aggregate packaged acceptance

**APPROVED for Eishin contact-only cases at scales 0.6 and 1.0.** Independently read `windows-objects-floor-v2-eishin/report.json` and `windows-objects-floor-v2-eishin-scale1/report.json`: each verifies the requested loaded Eishin rig and scale and passes 55 checks with zero failures. Chair/sofa/computer calibrated seat residuals are 0.164/0.451/0.393 px at 0.6 and 0.390/0.308/0.161 px at 1.0. Both wrists are reachable in each case, with zero reported projected residual and world residuals at most 1.08e-7 m. Each run has exactly one matching completed use outcome.

Independently viewed all six actual chair, sofa and computer shared-depth captures. Seated placement, furniture proportions, shoe/floor alignment and keyboard-facing posture are coherent at both scales. The scale-1.0 desk approaches the left viewport edge but remains visibly contained; the sofa and complete avatar also fit. No visual blocker in these captures. Garment occlusion limits anatomical inspection; this approval does not assert general cloth/furniture collision.

Together with the independently reviewed Cheval and Rice records, the final four cases provide **265 checks, zero failures**: Cheval 0.6 full lifecycle (100), Rice 0.6 contact-only (55), Eishin 0.6 contact-only (55), and Eishin 1.0 contact-only (55), on the parent-reported unchanged PCK candidate 80303. Occupied move/resize/hide/remove coverage belongs to Cheval only. This closes the requested furniture contact/visual acceptance scope, without extending it to arbitrary placements/scales, continuous motion naturalness, or the separately pending standing/world/voice regressions.
