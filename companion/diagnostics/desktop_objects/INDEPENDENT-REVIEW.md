# Independent desktop-object integration review

2026-09-06. **REVISE pending interaction-disable/drag cancellation.** Reviewed store, native object window, host, main integration, seat-contact API, export preset and setup license changes. Source-only review; actual Windows object rendering/contact remains coordinator-owned.

Store validates finite bounded coordinates/scales, stable canonical IDs and limits, and requires each placed object to fit one usable monitor. Host owns only its created native windows, destroys hidden/removed/parked windows, and releases its seating contact before explicit move/resize/remove/hide operations. Shutdown is idempotent. Object assets use the included Kenney Furniture Kit CC0 license; export includes that license and setup copies it alongside the binary while recording asset hashes.

The seat API uses a distinct anchor-only surface, validates support/path/work-area safety, and requires horizontal approach before switching the pet to its sit pivot. It does not promise free navigation between platforms. Seat-center contact is a pose preview, not full 3D collision/occlusion integration across independent windows. The object camera was corrected to zero horizontal offset during review, making the seat edge project horizontally as represented by the seat surface. Different object/pet projection and scale still require actual visual acceptance; source socket coordinates alone cannot establish anatomically aligned seating. Computer use records hand reachability but remains explicitly labelled a pose preview.

Found global Stop omitted the object lifecycle: a waiting request without a director request ID could survive `living.cancel`, or a using stage could continue renewing the working pose. Root added `objects.cancel_interaction` before `living.cancel` in `_cancel_current`; verified the landed fix. Character/new-chat paths using that method inherit cancellation.

Remaining required correction sent to host owner: cancel an active/queued interaction when local behavior, autonomy or surface mode is disabled, and when the user starts dragging the pet. Current busy gating only postpones a waiting interaction, so it can unexpectedly resume after drag/re-enable; using can continue despite the disabled setting. Existing object dragging cancellation is correct but does not cover pet dragging.

No runtime or asset edits by this reviewer. Final verdict can be updated after the bounded lifecycle correction; actual Windows rendering, contact alignment and interaction validation remain separate.

## Lifecycle revision

**APPROVED for source integration as revised.** Verified host `tick()` cancels before stage handling when behavior/autonomy/surface mode is disabled and when pet dragging begins. This closes the remaining queued-interaction resumption finding. The previously verified global Stop hook and frontal seat camera remain present. Actual Windows rendering, physical alignment and complete object-interaction execution still require their separately scoped evidence.

## Facing/foreground revision and new visual design

Re-read the subsequent host changes: active jobs participate in the work-pose busy gate, and foreground activity while facing cancels the object interaction rather than resuming against a heading target cancelled elsewhere. **APPROVED for this bounded source delta.**

Independently viewed the three reference photos at `/tmp/mate-prop-references/` and all six current `premium-previews/{chair,sofa,computer}-{front,threequarter}.png` Cycles renders. **VISUALLY APPROVED as reference-informed original prop designs.** Rounded upholstery/seams, chair castors/armrests, thin monitor and individual keys, and the restrained wooden desk give readable furniture silhouettes. The corrected monitor stand is below the LCD and the chair preview contains the full caster base. These are not exact reproductions of the product photos: the sofa is softer and sage-toned, and chair details are simplified. Optional refinement is slimmer sofa arms/back closer to the reference.

This visual verdict covers the inspected standalone Cycles renders only. Godot material parity, desktop-scale legibility, premium-model socket calibration, contact alignment and cross-window occlusion remain separate actual-app acceptance items. No asset/renderer/runtime edits by this reviewer.

## Premium seat raycast challenge

Independently inspected both native-seat overlays, `audit_premium_seat_geometry.py`, projection script and raycast JSON. **APPROVED for the narrow geometric inference:** sampled bilateral cushion tops project 3.11 px (chair) and 2.48 px (sofa) above the authored socket. Blender/glTF axis conversion and the stated orthographic projection are consistent. The front cushion lip is at different depth, so its apparent gap is not itself evidence of a 30–50 px air gap. This does not measure avatar buttock/thigh mesh contact; actual anatomical contact remains unresolved. The sofa/chair are visibly large relative to the avatar. Center-vs-bilateral rays establish a center gap/depression, but an exact 7 mm seam width needs construction evidence beyond these sparse rays.

## Packaged-resource and workstation-spacing amendments

**APPROVED for the bounded source changes.** `_load_asset()` now accepts either a ResourceLoader-resolved resource or a physical GLB before calling `load()`, so exported imported-resource remaps are no longer incorrectly rejected. Filename restrictions and PackedScene/Node3D validation remain intact. Actual PCK resource loading is coordinator-owned validation.

Computer chair local Z changes from 0.64 to 0.60 m. Its seat socket is transformed with the actual chair, yielding Z=0.52 m; keyboard sockets stay on the desk. This moves the chair and seated user four centimetres closer without moving only the goal markers or changing the avatar rig. The corresponding contact-scene expectation is updated. Final reach/posture/occlusion remain actual shared-scene acceptance; this source review does not substitute for that run.
