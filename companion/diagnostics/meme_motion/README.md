# Reusable playful upper-body motions

`mambo_sway` (4.2 seconds), `hachimi_peek` (4.1 seconds) and `playful_shrug`
(3 seconds) are installed finite VRMA actions. They use the existing normalized
humanoid animation API, so a profile selects them through `idle_actions` and an
LM can request the same catalog IDs. No character-specific engine branch is
needed. Mambo uses the sway and shrug; Hachimi uses the peek and shrug.

These are original, deliberately playful motions, not extracted replicas of
the meme videos. The official [Matikanetannhauser character description](https://umamusume.jp/character/matikanetannhauser)
describes earnest enthusiasm with absent-minded mishaps; the official
[Tokai Teio description](https://umamusume.jp/character/tokaiteio) describes
cheerful confidence and a supple distinctive gait. Those descriptions informed
the contrast between an unhurried offbeat sway and a curious double peek.
The [fan mashup reference](https://www.youtube.com/watch?v=5c6XzR61YCY) establishes
the Hachimi/Machitan pairing; its description mentions bouncing. No video,
soundtrack, image or animation was downloaded from that upload for these assets.

The tested `uma_walk` remains the actual leg locomotion source. These clips own
only spine/chest, neck/head, shoulders and arms. They contain no hips, legs,
translation, eye, jaw or expression channels. Quintic key transitions are baked
at 60 Hz to quaternion VRMA, with the original source hierarchy and rest frames
retained. Head, neck and torso use neutral normalized rest rather than mixing
source ancestor counter-rotations into an unrelated walking pose. A short playful upper-body rise is not advertised as a jump: airborne
motion would require support-aware flight and landing, which these assets do
not implement.

`MotionPlayer.play_upper_body_gesture(id)` independently layers a clip over
walking. Existing half-second fades preserve the live walking clock and leg
ownership. Contact-owned hands/torso reject those channels, while head-only
gestures remain available. For ordinary idle the existing ambient action
controller blends the action over `uma_home_idle` and solves planted feet.
No new per-frame solver, collider, LLM invocation or face modifier is added.

## Provenance and reproduction

The new authored curves live in [motions.json](motions.json). The relaxed
shoulder/arm pose is sampled from the already installed, verified local
`uma_home_idle.vrma` at 0.5 seconds; its SHA256 must equal
`679b086799df59c54fbb3760657b4c42e79bf7c1892c9fe3d99a1797fc27d0d9`.
The bake refuses a changed/missing source. The source was extracted from the
user's local UMA files; the derived VRMA binaries remain ignored and carry
`local-user-assets-not-redistributable` provenance. Only the authored definitions,
builder, manifest entries and compact evidence belong in Git. A local character
package can carry the resulting files with their source/license metadata.

From `companion/`:

```sh
tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script ../diagnostics/meme_motion/build_motions.gd
tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script ../diagnostics/meme_motion/probe_motions.gd
```

The first command writes three `assets/motions/*.vrma` files, updates just their
catalog entries and writes [build.json](build.json). It does not alter the base
UMA source. [validation.json](validation.json) records the deterministic
source-harness result: **367 checks, zero failures**, on Cheval, Rice and Eishin
at 30/60 Hz. Eighteen paired walking-overlay cells had exactly identical hips
and feet to their no-overlay baseline; maximum upper-body displacement was
0.286 m. Nine ambient-action cells retained foot contact within 0.000000423 m.
The largest consecutive authored quaternion change at 60 Hz was 1.030 degrees.
The test also checks finite completion, reset cleanup and contact channel locks.
Input VRM/VRMA hashes are recorded before and after the harness; an additional
assertion rejects changing input bytes during a run. This is source validation,
not packaged Windows acceptance.

[The actual Mambo/Hachimi mini-rig run](meme-rig-validation.json) adds **250
checks, zero failures** on both new VRMs. Its twelve walking-overlay cells again
preserve hips and feet exactly; six ambient cells have maximum foot error
0.000000113 m. The report records the exact candidate avatar hashes, so later
material/atlas changes must not be silently attributed to those same bytes.
Both own-viewport renders were inspected: the mini models face forward,
articulate the sway/peek without moving the support anchor, and retain their
normal expressions. These motions do not manipulate facial shapes.

[Independent review](INDEPENDENT-REVIEW.md) additionally measures the final
composed head orientation. The first candidate inherited the source head and
torso resting rotations as well as the arms, which introduced a larger head
posture change when mixed with walking ancestors. The neutral torso/head bake
removes that source-pose mismatch. The first candidate's assets, baseline
comparison and reports are preserved in ignored
`logs/meme-motion-first-candidate/`; do not treat the local key-step bound as a
bound on the final composed head speed or acceleration.

Optional actual-rig arguments follow `--`; use `MEME_MOTION_REPORT` to retain a
separate report rather than overwriting the initial existing-rig result:

```sh
MEME_MOTION_REPORT=/tmp/meme-rigs.json tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script ../diagnostics/meme_motion/probe_motions.gd -- mambo hachimi
DISPLAY=:0 MOTION_RENDER_DIR=/tmp/mambo-sway WALK_CHARACTER=cheval-grand tools/Godot_v4.5.2-stable_linux.x86_64 --path native --script ../diagnostics/meme_motion/render_motions.gd -- mambo_sway
DISPLAY=:0 MEME_RENDER_WALK=1 MOTION_RENDER_DIR=/tmp/hachimi-walk WALK_CHARACTER=hachimi tools/Godot_v4.5.2-stable_linux.x86_64 --path native --script ../diagnostics/meme_motion/render_motions.gd -- hachimi_peek
```

Own-viewport existing-rig renders are local diagnostics in
`/tmp/meme-motion-render/` (first candidate) and `/tmp/meme-motion-neutral/`
(neutral head/torso candidate); `/tmp/meme-motion-walk/` also contains actual
Mambo/Hachimi walking with the independent upper-body layer. These are local
diagnostics, not redistributed character renders. Linux render
inspection uses llvmpipe in this environment and makes no GPU-performance claim.
