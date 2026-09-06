# Finite action overlap helper

`native/scripts/action_overlap.gd` owns two bounded finite timelines, not skeletal sampling or IK. MotionPlayer owns the outgoing/incoming action descriptors and samples both at the returned performed time each frame. Do not replace the outgoing sample with a frozen pose. Durations/times are wall seconds after speed/repeat scaling.

API agreed with the motion owner:

```gdscript
overlap.start(name, duration, channels, support = "foot", start_time = 0.0)
overlap.queue(name, duration, lead_seconds = 0.35,
    channels = ["head", "arms", "torso"], support = "foot")
var frame = overlap.advance(delta)
overlap.reset() # cancel, character/model reset, incompatible interruption
```

`start` returns Boolean; invalid replacements leave current state unchanged. `queue` returns `{accepted,gated,reason}` and refuses a second pending action. `advance` returns `outgoing`, `incoming`, `current`, `queued`, `promoted`, `finished` and the timeline clock. Each nonempty sample has `{name,time,start_time,duration,support,weight_by_channel}`. After promotion, the former incoming action appears as `outgoing`, retaining its original start/time. A long frame that crosses both deadlines finishes both instead of restarting either.

Incoming overlap starts at `max(queue_time, outgoing_end - effective_lead)`. Lead is capped at one second and half the incoming duration. Shared channels use complementary smoothstep weights; disjoint outgoing channels remain at full weight while their samples continue advancing. Incoming-only channels fade in. The caller remains responsible for final pose smoothing and applying compatible hand-goal weights.

Channels are `head`, `arms`, `torso`, `legs`, `root`; supports are `foot`, `sit`, `lean`. A support change, or either action declaring leg/root ownership, gates the incoming action to the outgoing deadline. Callers must correctly declare any root translation/support-changing motion; a name alone cannot establish compatibility. Full-body/support transitions are not authorized to overlap by this helper.

When attaching to an existing action, initialize at its original start time, then advance by already elapsed time before queuing. Keep separate descriptors for consecutive same-name actions, since speed/intensity/repeat may differ.

Validation: Linux Godot 4.5.2 headless `test_action_overlap.gd` passed **125 checks, zero failures**. Checks cover wave→nod overlap, live outgoing samples, complementary bounded shared weights, disjoint arms, preserved promotion timing, normal and long-frame completion, active/pending cancellation, support/leg gates, late queueing, short incoming duration, invalid input, queue capacity and 30/60/120 Hz timing. This is helper validation; integrated visible body/hand continuity is the motion owner's separate acceptance work.

Independent root review: **APPROVED for the timeline/channel helper**. Inspected
bounded queue admission, live outgoing/incoming sample times, complementary
shared weights, disjoint channels, support gates, late queue and long-frame
promotion. The 125 checks exercise these semantics. Integration must still fade
an outgoing-only limb when A ends, apply the actual live samples rather than a
snapshot, and handle a long frame finishing both actions. No visible animation or
contact quality is inferred from this helper-only approval.

## Runtime integration and moving steering

`MotionPlayer.queue_gesture(name, lead_seconds, channels, intensity, speed, repeat)`
now samples both finite bank actions continuously. Shared channels crossfade;
exclusive channels remain live. Hand IK goals and wave wrist articulation use
both timelines, including the incoming action before promotion. The existing
pose smoothing and hand velocity limit retain continuity as bank endpoints
return to neutral. This is currently a finite bank contract: custom editor
motions and VRMA sources reject explicitly. Root/leg or support-incompatible
requests use the helper's boundary gate.

`play_gesture_sequence(first, second, lead_seconds=0.5, preview=true)` exposes the
same mechanism for manual inspection. Preview ownership lasts through both
motions. `probe_action_sequence.gd` covers wave→nod, nod→wave, and repeated wave
on all three rigs at 30/60 Hz, including pre-end starts and priority release.

Travel uses `prepare_locomotion(direction_px)`, `locomotion_ready()`, and
`finish_locomotion()`. Departure requires a 10° body lead and at most 72° remaining
heading error, rather than a finished turn. Stationary `face_front()` still uses
TurnStepper. During planned travel, DesktopGait alone owns legs: cached world
foot points AND foot bases survive root yaw, while angular arc distance advances
step phase alongside measured desktop displacement. Swing landing direction is
screen travel transformed into skeleton coordinates; swing foot orientation
anticipates travel heading. This is grounded lateral desktop travel, not free
3D navigation.

Reproduce viewport sequences with:

```sh
DISPLAY=:0 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script tools/render_coarticulation.gd -- concurrent
DISPLAY=:0 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script tools/render_coarticulation.gd -- sequence
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script tools/probe_action_sequence.gd
```

Own runtime checks passed 18 pair cases, 18 steady gait cells, and all three
mid-turn model replacements. Independent actual-host chain acceptance remains
the authority for simultaneous OS travel/yaw and world support measurements.

### Quantized desktop travel

The first concurrent candidate exposed a real slow-arrival stutter: each final
integer OS pixel directly advanced the authored clip phase, producing a held
arm pose followed by a one-frame rotation step. The sampled phase now follows
an unwrapped measured-distance target (`gait.phase_distance`) with an exact
critically damped pursuit (18/s). Both clip and leg swing consume the same
continuous `gait.phase`; planted foot compensation still applies the complete
actual OS displacement immediately. This adds a short phase lag, not invented
travel distance. `probe_quantized_gait.gd` exercises real rigs at six integer
pixels/second and 30/60 Hz; all six cases maintain continuous arm movement.
The independent actual-host comparison removed 106 detected held-step-held
patterns in the selected chain, and the previously identified arrival spike
became a continuous 43→37→37→39→37→34°/s arm trajectory.

Arm local inertial carry is capped at 360°/s; other channels retain 120°/s.
IK parent/child counterrotation can exceed a head-sized local cap while the
composed hand moves moderately. Preserving those components improved the
standalone wave release from 121.6→54.5°/s to 121.6→117.2°/s, without changing
head limits. `probe_action_release.gd` reproduces standalone versus paired
wave endpoint measurements.

### Reusable authored walking sources

`register_locomotion_clip(name, preserve_hips=true)` opts any loaded VRMA into
shared distance-phase playback and grounded leg ownership. The registry replaces
runtime assumptions about two particular walk names. When requested, source hip
translation is centered over 120 uniform cycle samples and bounded to 3.5% of
character hip height. This retains authored sway/bob without importing an
absolute source offset or world travel. Common transitions then compose the
pose, and the same final leg IK maintains contact.

The repaired local UMA neutral walk was compared on all three rigs against the
existing Quaternius walk and an Overte forward walk. Quaternius' composed head
points 13–17 degrees downward; UMA neutral is approximately level without a
synthetic head correction. Initial neutral/down FBX conversions contained arm
spins from Euler interpolation; those candidates were rejected and preserved.
Euler-filtered export removes that defect. `probe_authored_walk.gd` runs the
repaired source with retained hip motion through 18 rig/scale/speed contact
cells. `render_walking_attention.gd` accepts `WALK_CANDIDATE`, `WALK_CHARACTER`,
and `WALK_HIPS=1` for explicit source comparisons. Final source selection and
hashes live in the walking asset acquisition records and catalog.

Final local walk selection uses the subsequent direct Unity-quaternion bake
(`uma_homewalk_direct.vrma`, SHA-256
`8f0b44c9fbee138f9923185a6dc373e0a11349c7d20c523163c941ebfe329573`),
which removes the filtered export's remaining small Euler approximation.
Original translations/rest are retained. The direct candidate passed a bounded
three-rig contact rerun and an actual concurrent-turn viewport sequence;
independent source measurement places head pitch at -0.875..2.085 degrees.

On successful catalog refresh the host calls
`clear_locomotion_registrations()` before re-registering advertised capabilities.
This removes revoked custom locomotion permissions and hip-center caches while
retaining legacy walk/formal fallbacks. Loaded clips remain available as ordinary
previews; loading alone does not grant locomotion ownership.
