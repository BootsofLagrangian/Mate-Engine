# Desktop objects and shared contact scene

`DesktopObjectsHost.configure(app)`, `tick(delta)` after LivingBehavior and idempotent `shutdown()` own the furniture lifecycle. Main passes `blocks_roaming()`/`is_dragging()` into autonomy and calls `cancel_interaction()` on explicit stop and new foreground requests. Panel operations are `catalogue`, `rows`, CRUD/visibility/edit methods and `interact(id, verb)`.

Instances have stable persisted IDs, bounded finite placement/scale, at most eight records, and must fit a usable monitor. Hidden/removed/parked instances have no active native render. Visible objects publish expiring `object:<id>` inspect interests; idle curiosity may look at them, while seat/work interactions are explicit. The native object windows accept only their own drag input and never inject global input.

## Geometry and appearance

Original reference-informed curved premium GLBs and embedded PBR textures are described by `native/assets/desktop_objects/premium/objects.json`. See `visual-redesign.md` and packaged `PROVENANCE.txt` for design references, authorship and hashes. Kenney CC0 assets remain a fallback. Native windows use frontal orthographic projection, four-sample antialiasing and actual mesh-vertex grounding one pixel above the viewport floor.

Base dimensions are chair260×300, sofa500×340 and computer360×300. Initial size derives from the avatar's physical pixels/metre and the actual object projection. The current path keeps physical scale and configures a bounded seated floor constraint from the actual shared seat-to-floor distance before pose calibration. This uses the existing secondary-motion collision interface and leg contact solver; its full runtime acceptance remains separately measured. This is not a claim that every user-resized rig/seat combination fits. Too-small or oversized arrangements return a failure instead of widening a seat or hiding geometry.

## Explicit contact sequence

The request closes the panel and waits for quiet, supported movement. `DesktopObjectContactScene` creates the same asset in the avatar's World3D, plus a chair for computer use. During approach the native unoccupied object remains visible. The actor walks to the shared scene's seat coordinate on the current reachable horizontal support.

At arrival the host checks the combined avatar/furniture viewport extent, reframing transparent window space with an equal compensating avatar-pivot change when necessary. This changes the window rectangle without moving the visible character on the desktop. A frame that cannot contain the arrangement is rejected. The native furniture window is hidden and the shared scene becomes visible, so character and object use one camera and depth buffer.

The actor turns smoothly toward the seat's orientation through `set_contact_heading()` and waits for readiness, bounded by6s. Computer layout uses35degrees scene yaw and a chair facing215degrees, toward the monitor. Other seats face forward. The canonical sit pose then blends for0.8s before the window approaches the support point. The pelvis support remains a narrow anchor-only surface, separate from walking platforms. Subpixel projection roundoff is tolerated to0.1px; a moved/removed seat still detaches. An owned seat request cannot fall back to an unrelated desktop window, and every seated/using stage verifies the exact object support identity.

`avatar.calibrate_seated_pose()` supplies a stable measured support anchor and posed mesh bounds; main caches by rig/clip instance. Standing navigation is unchanged. Seated navigation uses measured vertical bounds while retaining the previous full-turn horizontal reserve. Calibration details and actual visual acceptance belong to their separate probes.

## Shared render timing and computer use

`contact_scene_active()`, `contact_socket_world(name)`, `contact_socket_screen(name)` and `contact_bounds()` expose the active scene. Socket screen coordinates are global Godot desktop pixels. The host refreshes scene placement after actual `frame_moved` commits as well as during tick, preventing a rendered frame of desktop drift. Desktop-fixed furniture bounds are checked separately; they are not translated as hypothetical pet movement bounds.

Computer use is seated and finite (10s). Both hands use existing geometric IK toward `keyboard_left` and `keyboard_right`; `hand_reachable` is their conjunction, with individual `left_hand_reachable` and `right_hand_reachable` fields. The actor looks toward `inspect`. This is a local pose interaction, not typing, screen reading or real application work. Successful geometry checks alone do not establish a natural rendered pose; actual same-depth-buffer Windows captures are required.

## Release and evidence scope

Stop/new chat, character switch, disabled behavior/autonomy/surfaces, pet/object drag, occupied-object move/resize/hide/remove, timeout and shutdown release owned interaction state, restore the native object and transparent-window frame, and stand the actor when appropriate. Foreground work cancels preparatory facing/pose and computer use. The seated floor constraint clears on release, including failed activation. No general promise is made that starting a conversation preserves an object seat.

Current focused host tests cover lifecycle, heading ordering, postcommit shared-scene stability and oversized-view rejection. Earlier standalone mesh/UI/store test counts are implementation milestones, not final interaction acceptance. The first shared Windows development run rejected physical-default contacts; it is preserved under `logs/windows-objects-shared-development`. Final acceptance must cite subsequent actual rig identity, shared-root captures, rendered seat/hand contact, default fit and lifecycle results.

Future `hold`/`tool` verbs remain reserved hooks only. No handheld rendering, arbitrary application automation or permission semantics are implied by the current furniture API.

## Physical workstation reach check

The shared computer chair sits at local Z=0.60 m (seat socket Z=0.52 m), four centimetres nearer the desk than the initial arrangement. Keyboard targets remain on their authored geometry. `test_shared_work_reach.gd` loads all three real rigs, applies the canonical floor-constrained seated pose, aligns the actual shared seat, and solves both hands at physical scale. The production arrangement passes six strict reach flags with maximum world residual 7.03e-8 m; the original placement failed Rice’s right-hand reach flag. Retained before/final logs document that change. This isolated canonical check does not replace the packaged post-draw wrist and visual acceptance tests.
