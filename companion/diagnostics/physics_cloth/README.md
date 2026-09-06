# Secondary-bone contact and cloth feasibility

The native pet preserves authored VRM spring physics. **Extra hand/forearm proxies are disabled by default** after deeper temporal review found a large Rice walking jump with unrestricted hard contacts. Only diagnostic code explicitly opts into the experimental shallow-contact response. See [PHYSICS-QUALITY-REVISION.md](PHYSICS-QUALITY-REVISION.md). These proxies move with the current humanoid pose; the existing VRM Verlet integrator applies the collision response. Authored spring stiffness, gravity and drag are retained. Humanoid animation bones and a sleeve's own arm are excluded. Loading another avatar removes only this module's proxies, preserving other imported and seated-floor colliders.

`native/scripts/vrm_spring_contacts.gd` uses a fixed-length sphere intersection because a radial push followed by length normalization can re-enter the collider. It does **not** collide every rendered skin triangle, push the animated hand away from a torso, or give furniture a general physics body. Gaps between the sparse hand/forearm spheres, self collision, and impossible constraints remain possible. This is targeted secondary-bone contact, not a claim that all clipping is removed.

## Superseded initial authored-motion comparison

**Historical evidence only:** this first controlled probe did not restore nonhumanoid local bone poses between manual ticks as Godot’s live SkeletonModifier does. Its endpoint counts cannot establish production appearance or stability. The original records are retained rather than overwritten.

`authored-motion-contact.json` records Cheval Grand, Rice Shower and Eishin Flash playing the existing authored `uma_walk` and `sit_idle` VRMAs. Each cell uses 360 fixed 1/60-second spring ticks; the first 60 are warmup. The only A/B difference is removing the newly added proxies from the baseline. The probe disables the automatic skeleton modifier and calls the same imported spring integrator at the controlled timestep.

Across the six cells, measured endpoint-versus-proxy penetration samples fall from 644–4,233 to zero at a 10-micrometre threshold. Worst baseline overlap is 19–95 mm; corrected worst overlap is below 0.00004 mm. These are spring endpoint sphere metrics, **not skinned-triangle intersection measurements**. Average spring tick cost increased by 0.30–0.38 ms on this machine. The old measured displacement did not increase in these six cells, but the corrected trajectory later exposed a Rice walking jump; that old stability interpretation is withdrawn.

`eishin-seat-baseline.png` and `eishin-seat-contacts.png` are the actual rendered frame 180 from the matched Eishin sitting cells. The skirt changes around the wrists while the source body motion is identical. These probe captures do not include a furniture seat or the separate seated-floor constraint.

## Mambo and Hachimi

The extracted mini meshes have weighted hair/skirt bones but originally had no VRM secondary-animation groups. `author_mini_springs.py::add_mini_springs(doc)` now authors conservative VRM 0.x groups during the existing converter, before final hashing. This is **new Mate tuning, not original game physics**. Existing authored groups are retained unchanged. Mambo has eight hair roots and twelve skirt roots; Hachimi has seven and ten. Both have four head/hips/thigh collider groups. Gravity is nonzero, drag is relatively high, and no humanoid animation bone is made dynamic.

The converter calls the utility for dry and wet variants and records its source hash. `mini-springs.json` records a 360-displayed-frame head-sway test (yaw ±18°, roll ±8°) per published dry rig. This exercises actual imported springs and meshes; it does not produce cloth-mesh folds. `spring-contacts.json` covers all five published avatars and cleanup; `spring-contacts-before-mini-authoring.json` preserves the initial zero-spring mini inventory.

## Actual cloth experiment

`native/tools/probe_cloth_physics.gd` constructs a separate **288-vertex, 512-triangle skirt proxy**, pins 32 waist vertices, and runs Godot 4.5.2's built-in Jolt SoftBody3D against a moving spherical hand proxy and pelvis. It runs in an isolated project; the pet's physics backend and costumes are unchanged. The exported pet has not been switched to this experimental garment.

The six-second active trial uses the WSL Mesa D3D12 **NVIDIA RTX 4090** renderer, not the initial software-rendered attempt. The live mesh deforms by up to 0.270 m under gravity/contact, remains finite, and pinned waist error is below 0.000001 m. `cloth-skirt-proxy.png` is the actual result and shows coarse folds. `cloth-d3d12.json` retains the measured result: approximately 325 rendered frames/s in this small scene; the Godot physics-process monitor averaged 3.51 ms (p95 13.26 ms), versus 1.09 ms in the preceding warmed scene without cloth. The baseline is warmed while the cloth interval begins immediately after cloth creation, and the moving hand starts the two intervals at different phases. This is exploratory timing from one sequential local trial, with WSL scheduling and rendering in the loop; it is not a production cloth CPU budget or full-pet benchmark. GPU timestamp results were all zero on this driver and are **unavailable**, not evidence of zero GPU cost.

The first experiment used llvmpipe and also compared vertex indices before SurfaceTool's final indexing; its invalid pinned-vertex result is retained in `cloth-first-attempt.log`. The corrected experiment pins and compares the actual final mesh's vertices. The first mini probe passed Array values to an API requiring Vector3 and is retained as `mini-first-attempt.log`; its apparent finite result is not used as validation.

Reproduce the visible isolated cloth trial from the companion directory:

```sh
python3 diagnostics/physics_cloth/run_cloth_probe.py
```

A production costume needs a garment-specific simulation mesh, waist/shoulder pin mapping, body/hand colliders, cloth-to-render-mesh transfer, and tuning during walking/sitting. The current imported models frequently combine body and costume into one skinned surface, so blindly substituting SoftBody3D for the complete mesh would deform the face/body too and lose the normal skeletal binding. Fine wrinkles need a denser or separate render surface and suitable cloth topology; this coarse proxy only establishes that real deformation/contact works with the available native engine.

## Primary references

- [VRM 0.x secondary animation specification](https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/README.md): spring roots, gravity and collider groups; the converter emits this existing format.
- [VRM 1.0 spring-bone specification](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_springBone-1.0/README.md): spring endpoint sphere collisions against sphere/capsule colliders; this is bone physics, not general mesh cloth.
- [Godot 4.5 SoftBody3D API](https://docs.godotengine.org/en/4.5/classes/class_softbody3d.html): deformable meshes, pinned points and the recommendation to use Jolt for soft bodies.
- [Godot 4.5 soft-body tutorial](https://docs.godotengine.org/en/4.5/tutorials/physics/soft_body.html): bone-attached pinned cloak example and mesh subdivision/import considerations. The page flags some tutorial content as not yet updated for 4.5; runtime behavior above was independently exercised on 4.5.2.
