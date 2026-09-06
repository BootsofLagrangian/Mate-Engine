# Desktop world and interaction extension plan

The generic engine separates character data, conversation, presentation and desktop
geometry. Cheval Grand, Rice Shower and Eishin Flash are test packs, not special
cases required by the world or motion interfaces.

## Existing Mate Engine work reused

The Unity implementation remains in this repository. The native Godot host adapts
the following existing behavior; it does not load Unity assemblies into Godot.

| Existing source | Reused behavior | Native integration |
| --- | --- | --- |
| `Assets/MATE ENGINE - Scripts/AvatarHandlers/AvatarWindowHandler.cs` | Enumerate visible windows, exclude self/minimized/cloaked windows, account for front windows | Windows geometry source and visible platform segments |
| `Assets/MATE ENGINE - Scripts/AvatarHandlers/AvatarLocomotionController.cs` | Move the actual desktop window; constrain projected avatar bounds | DesktopAutonomy and contact anchors |
| `Assets/MATE ENGINE - Scripts/Settings/MonitorHelper.cs` | Monitor and work-area geometry | Taskbar/work-area floor, negative monitor coordinates |
| `Assets/MATE ENGINE - Scripts/Settings/AvatarScaleController.cs` | Wheel/slider scaling, smoothing, pause during drag | Native size controls and recalculated contact/hit bounds |
| `Assets/MATE ENGINE - Scripts/AvatarHandlers/AvatarFoodController.cs` | Spawn/despawn, interaction radius, avatar binding and bounded secondary motion | Reference for future generic props; not a completed native prop system |

Windows geometry describes position and occlusion only. It does not recognize
window contents. A future VLM can publish observations through `observe_interest`
and world-object identifiers; screen interpretation need not be embedded in the
locomotion controller. Window geometry comes from the existing Win32 approach
([EnumWindows documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumwindows)).

## Contact and locomotion

World coordinates use Godot's global desktop pixel origin. The Windows adapter
translates raw Win32 coordinates once at the boundary: on layouts with a monitor
left of or above the primary display, Godot normalizes the virtual desktop origin.
Future raw screen observations must use the same translation. Avatar anchors are projected into window-local pixels. Foot and seat anchors use
stable rest geometry; live hand anchors follow the current humanoid pose. A contact pairs a world
point with a foot, pelvis or hand anchor. Moving the native window then preserves
the relationship between the rendered body and the desktop surface.

The first surface implementation targets horizontal window-top segments and the
work-area floor. Occluded and too-short segments are unusable. Manual dragging,
dialogue and resizing take priority over autonomous movement. Moving or closing
the supporting window requires revalidation and detachment. This is not a full
physics simulation, jumping planner or arbitrary wall-climbing system.

## Local behavior and occasional model directions

The native host now connects `BehaviorDirector`, `LivingBehavior`, user interest
points and `DesktopAutonomy`. Quiet waiting does not invoke the LLM. The local
director schedules long rests, occasional looks, posture changes and exploration,
using the character profile's bounded `behavior_style`. Conversation, recording,
dragging and explicit gesture previews take priority over wandering.

Open **행동** to add a named point, drag its small desktop marker, and choose
**이동** or **살펴보기**. Points persist across launches. Inspecting keeps the pet
in place; moving still requires a reachable destination on its current support.
Placing a marker in empty space does not create a floor or a bridge. The marker
can be hidden independently of its saved target.

An ordinary conversation turn may return `move_to`, `inspect` or `rest` with a
listed target ID. User commands, model directions and local exploration enter the
same cancellable intent queue. User commands take priority; repeated action/done
metadata does not start an action twice. Spoken acknowledgements drain before
walking resumes. The model receives bounded names and IDs, while the native
controller owns geometry and checks reachability. Unknown, expired or removed
targets do not execute. A small model can still verbally promise an unavailable
action; rejecting the command does not guarantee correct dialogue semantics.

External observations can use `observe_interest(id, point, confidence, ttl, kind,
label)`. They expire, are bounded in number, and cannot overwrite user or support
IDs. This is the connection point for future recognition and prop providers;
neither screen recognition nor prop rendering is implied by receiving an interest.

Motion clips remain reusable humanoid assets. Walking phase follows actual window
displacement; stance IK compensates that movement in the rig's 3D frame. This is
a bounded animation/contact controller, not full-body dynamics. The desktop
support is still a horizontal projected surface. Depth used by leg motion and
body turns is distinct from navigating a general 3D desktop world.

See [native behavior controls](native/README.md)
and the component evidence in `diagnostics/behavior/` and
`diagnostics/liveliness/`.

## Planned: props and tools

These are extension requirements, **not implemented capabilities**. Start with a
magnifying glass and a laptop once contact motion and desktop movement are stable.

- A prop package declares a local visual asset, grip transforms, optional hinge
  joints, supported actions, and contact points. Character overrides adjust the
  grip and reach; the engine resolves humanoid bones independently of the model.
- Reusable actions are `equip`, `use`, `open`, `close`, `place` and `stow`.
  Hand attachments and two-hand IK share the existing motion/contact infrastructure.
- The presentation scheduler arbitrates speech gestures, locomotion, hands and
  props. Transitions and cancellation release attachments and return the body to
  a valid pose instead of leaving a hand locked in space.
- Agent events can request a presentation such as `inspect` with a magnifier or
  `work` with a laptop. Showing a laptop does not itself grant file or computer
  access: actual actions still go through the configured job/tool adapter.
- A placed object can expose a desktop surface and an interest point. Recognition
  and tool results refer to stable object IDs, so future VLM observations can
  connect to the same scene without replacing motion or character packages.

Acceptance for the first props: all three rigs grip correctly without hand/face
penetration; scale and character switching preserve or safely clear attachments;
interruption, failed jobs and missing assets return to a valid idle; one full
equip/use/stow sequence is checked in the actual Windows host.
