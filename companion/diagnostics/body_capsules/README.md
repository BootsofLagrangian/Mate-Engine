# Occupied-chair body capsules

`MotionPlayer.seated_carrier_body_snapshot()` returns an empty dictionary until the carrier owns a valid, freshly processed, fully lifted seated pose. A successful snapshot contains 15 avatar-local capsules (`id`, `a`, `b`, `radius`), the current avatar transform, model/source identity and held source phase. `VrmAvatar.body_capsule_snapshot()` is the read-only lower-level pose snapshot and does not certify future articulation.

The capsules approximate pelvis, torso, neck/head, both thighs/calves/feet and upper arms/forearms using actual posed skeleton endpoints and rest lengths. Hands, garments, hair and accessories are excluded. This is a declared body-volume approximation, not an enclosure of every rendered vertex. External collision admission must scope seat-support and keyboard-contact exemptions; it must not exclude the fixed desk wholesale.

During finite carrier ownership, the current composed humanoid body pose and seated source phase are held. Eyes, jaw, facial blendshapes and spring simulation remain live. Lowered release resumes the source clock at the held phase and uses the existing transition blend. A same-contact restart is rejected without mutation; model, source playback or foot-reference epoch changes invalidate the hold. Radius transforms use an absolute Gram-row-sum bound, including small scaled shear.

`final.json` and `final.log` record five actual rigs: Cheval Grand, Rice Shower, Eishin Flash, Mambo and Hachimi. The test performs authored entry, lift, translated/yawed carriage and lowering. It checks finite positive capsule geometry, immutable returned data, exact pose preservation during snapshot, rigid local endpoints, continuous phase resume and the existing foot/reach checks. All pass. `source-hashes.json` identifies the tested candidate. Independent review is recorded separately.

Replay from the repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_body_capsules.gd
```

Scope limits: the rigid snapshot covers full-lift transport, not the articulated lift/lower path. Fixed-prop angular sweep and actual Windows admission/rendering are separate integration checks. No universal naturalness, full garment collision or Windows frame-time claim follows from this fixture.
