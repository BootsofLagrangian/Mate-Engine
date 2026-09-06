# Canonical scene navigation adapter

`main.request_scene_approach(target_world, obstacle_bounds)` plans a bounded world-X/Z route on the current physical ground Y. `cancel_scene_approach(reason)` stops it; explicit user cancellation calls this even without a furniture interaction. `DesktopSceneNavigationHost` owns the actual stable foot world point through the shared camera, temporarily suspends legacy desktop-surface movement, verifies full projected body bounds before retaining each OS-window commit, and forwards actual world displacement/distance to the authored gait.

A fixed 0.25-second acquisition precedes translation. Movement does not wait for the body to finish turning; continuous heading and acceleration-limited speed reduction handle heading error. Invalid replacement geometry validates separately and leaves the previous route intact. Drag, microphone, preview, unrelated speech/work, disabled autonomy and pointer interaction stop travel. The exact current LLM reply's furniture command may overlap its own speech; no unrelated request inherits that exception.

Objects route perspective approaches through this adapter, retaining original authored entry X/Z through their world staging point. At arrival they validate the actual world foot, orient toward the furniture, and release the world-foot override directly into the finite source entry. Target furniture mesh-part bounds are included as conservative solids. Hollow-space false rejection is possible; target furniture is never silently ignored. Workstation geometry can explicitly block an inaccessible source-authored staging point.

Checks: controller 4,252/0; real Cheval + actual Motion + production adapter 248/0 (`desktop_objects/probe_scene_host.gd`, actual orthographic camera and broad simulated workarea); source staging 37/0; command ownership 27/0. The adapter fixture checks real X/Z foot movement, unfinished-yaw/travel overlap, endpoint callback, and urgent drag cancellation. It does not establish Windows perspective/compositor or chair access.

`native/tools/probe_windows_scene_navigation.gd` is the external Windows acceptance script. It preserves prior authored probe traces, records actual perspective world joints and owned images, tests a controlled curved obstacle route and user stop, then real chair entry/exit and computer contact or explicit blockage. Root runs it sequentially. Default idle exploration still uses the prior desktop policy until scene furniture acceptance is complete; no default 3D exploration claim is made yet.

Follow-up after the first Windows run: the route probe now saves actual post-draw frames, measures successive yaw changes during translation (not merely heading error), and tests every retained foot against the expanded obstacle. Perspective transition handoffs use canonical world joints; the old pixel/PPM reconstruction is not a metric. Fixture FOV/distance are pinned to 45 degrees/3.6 m.

Furniture sizing reads the authored reference PPM rather than querying an unrendered temporary native camera. Creation records explicit sizing diagnostics. Perspective creation and semantic near/left/right placement preserve physical ground Y and use scene metres, independent of the padded native canvas. Same-turn speech contact admission has an additional narrow main context exception only at ready_contact/seating; panel, mic, drag, pointer and unrelated speech remain blocked.

## Default local scene exploration

Perspective floor mode now advertises up to six stable `scene:ground:N` interests, derived from canonical ground positions, actual solid navigation and conservative projected body/workarea admission. These use the unchanged director quiet timing and the same named `move_to` path as user/model intents. `scene_exploration_enabled=false` opts out. Window-top support and explicit non-scene targets retain legacy movement.

Generic scene arrival retains an explicit `ground_latched` foot-world owner while idle, separately from route/completion ownership. This prevents old screen-taskbar support from pulling the avatar back after a Z trip. Subsequent curiosity routes can depart from that idle world point. Manual drag, disabled surface mode, character/mode teardown release ownership; ordinary idle speech/pointer attention does not move the world point. The actual-rig harness holds XYZ for five seconds with deliberately stale legacy taskbar support, 254 checks total/0 failures.

A six-interest schedule exposed a selection resonance: eligible cycle numbers could repeatedly choose the last moved target, suppressing further movement. A deterministic alternate eligible floor target now avoids that repetition without changing timing. Sixteen simulated minutes produce ten local trips with at least 50 seconds between starts. This test supplies no model/client and is scheduling evidence, not a Windows visual claim.

`probe_windows_default_scene_idle.gd` separately observes fresh production defaults for 150 seconds after readiness/corridor placement. It issues no chat or direct movement requests. It requires actual perspective configuration, local scene targets, a >=5cm depth trip with matching local Director arrival, and five seconds of <=5mm XYZ drift with the scene-ground latch retained. Per-frame JSONL and one-second owned PNGs are retained. It reports no observed conversation events/turns, explicitly not a packet-interception audit. Original settings are restored and reread from disk for canonical JSON comparison. Windows execution belongs to root.

### September 7 runtime corrections awaiting Windows revalidation

The forward walk has no minimum travel speed while facing backwards. Travel gain
is `smoothstep(0,1,max(0,cos(heading_error)))`: body turning begins first, translation
starts within the forward hemisphere, and the remaining turn overlaps travel.
User stop ends the route and its authored locomotion but retains the current
virtual-ground XYZ latch. Drag, character changes, disabled mode and shutdown
still release ownership.

Obstacle extraction splits triangle-connected physical components instead of
using one AABB for a material batch containing disconnected furniture pieces.
Every component remains an obstacle. Authored seating tries horizontal root-distance
factors 1.00–1.25 in 0.05 increments, selecting the first fully navigable staging
point. Joint curves, clip timing and authored root progress are unchanged. The
recorded Cheval chair fixture requires 1.20 (3.75 cm extra world approach at scale
0.6); smaller candidates hit real front casters. This is bounded retargeting,
not a claim of chair pulling or general contact physics.

Source checks: `probe_scene_host.gd` 269 checks/0 failures (retained ObjectDB
exit warning), `probe_chair_solids.gd` 2/0. The scene-host fixture checks actual
rig XYZ, no rearward forward-walk travel, concurrent yaw and five-second stop
retention. These do not replace Windows physical seating/render acceptance.

Virtual-floor admission uses the measured heading-swept mesh envelope, preserving
world Y and finding the nearest safe X/Z placement within 0.25 m. Already-safe
anchors are unchanged. This runs once on mode/admission (including an unsafe drag
release), before turning; it is recorded as placement, not a walked distance or
hidden per-frame floor correction. The observed default Cheval case needs about
1.34 cm inward Z because perspective shoe depth changes the projected bottom
while turning. The idle Windows probe uses this same production placement policy
for its disclosed own-window corridor setup.

Placement admission additionally rejects any full standing-capsule segment crossing
actual furniture solids, including corrections with individually free endpoints.
The idle observer only awaits automatic Living placement after its disclosed
normal drag-release corridor setup; it does not invoke adoption or movement.
