# Cheval cape spread during overhead stretch

The wide four-panel cape is present **with secondary physics completely disabled**. It is primarily the imported cape rig/rest shape following the authored shoulder/chest pose. The tested spring physics bends the tips downward; it does not create the large span or stretch the cape bones. No runtime spring tuning or bone-shape override was made during this audit.

The trigger was the exported Windows build `7cc45564…`, notably `logs/windows-render-room-padding-first/perspective-authored_overhead_stretch-08.png` and `-13.png`. The corresponding orthographic Windows capture also has the wide cape, so the spread is not caused solely by perspective. The apparent whole-body diagonal in the Windows off-axis camera remains a separate camera-placement question: the same source pose viewed by a centered perspective camera remains upright. This audit does not establish that the desktop camera itself is correct.

## Actual modifier comparison

`native/tools/probe_cape_modifier.gd` loads two identical Cheval avatars at the same world origin. One uses the real enabled SkeletonModifier; the other retains the same humanoid source pose with secondary physics disabled. It does not manually emulate spring updates. Both use the existing `authored_overhead_stretch` / `authored_stretch` VRMAs plus a relaxed rest condition. It captures orthographic and centered perspective views, with a 45° yaw / approximately 30° elevation perspective camera.

The run exercised **2,244 actual modifier callbacks**, using Godot 4.5.2 with fixed 1/60-second delta and WSL Mesa D3D12 RTX 4090 rendering. The source pose is held during sequential A/B viewport readback; this is a controlled source-pose/physics comparison, not a byte-identical replay of the full Windows pet's blends and camera crop.

At the one-second overhead-stretch sample, both physics-off and physics-on show the large cape. The largest cape-bone rotation difference is approximately 20.6° at a tip. Across the sampled nonzero times, maximum absolute difference in sampled internal cape-chain segment lengths is below **0.00000023 m**, and maximum scale-component difference is below **0.00000048**. The maximum global tip rotation difference is 31.6°. These establish finite rotational secondary motion with conserved segment length in this sample; they do not establish cloth-triangle strain, collision freedom or garment naturalness in all motions.

Retained evidence in `cape_audit/`:

- `orthographic-authored_overhead_stretch-060-off.png` / `-on.png`: source pose with and without actual spring physics.
- `orthographic-rest-060-off.png` / `-on.png`: arms-down reference.
- `perspective-authored_overhead_stretch-060-off.png` / `-on.png`: centered oblique view.
- `report.json`: per-sample cape bone transforms from the real modifier callback and baseline.
- `summary.json`, `identity.json`, `process.log`: derived bounds, source hashes and runtime identity.

## What the supplied assets contain

The VRM has shoulder-attached `Sp_Sh_Mantle0_L/R_00` chains and chest-attached `Sp_Ch_Mantle0_BL/BR_00` chains. Their imported spring group uses stiffness 2.5, gravity power 0.2 and drag 0.5; the same group also contains the tail. Broadly altering the whole group would therefore change the tail too. The arm-up pose rotates the shoulder parents and carries the cape's baseline shape outward before physics runs.

The installed overhead stretch comes from local UMA `stretch02`. Its curation manifest lists 61 replaced source rotation tracks / 52 mapped humanoid bones. No `Mantle` path is present among its recorded source paths. There is therefore no recovered authored cape animation in this installed clip that can simply be enabled. This does **not** prove the original game lacks cape-specific simulation/configuration.

## Supported next candidates

1. The follow-up extraction recovered actual `Gallop.CySpringDataContainer` settings from `bdy1089_00/clothes/pfb_bdy1089_00_cloth00` through `04`. Cloth00 includes four cape chains / 18 joints, 27 collision entries and four connected-panel links. Its source values differ by joint, with asymmetric angular limits and inside/capsule colliders absent from the supplied VRM. See `CAPE-SOURCE-CANDIDATES.md` for the recovered schema, provenance and nondefault comparison candidates. Native solver units and controller rates remain unresolved; source recovery does not make a scalar-only VRM conversion faithful.
2. If their required constraints cannot be represented faithfully, prepare a separately versioned cloak rig/profile with an authored hanging rest pose and garment-specific weights/anchors. Test arms-down, overhead stretch, arm crossing, turning and sitting before enabling it. Preserve shoulder attachment while allowing the panel body to hang; do not permanently counter-rotate every cape bone to hide the symptom.
3. A real garment simulation would use a cloak-specific simulation mesh, attachment points, bending/stretch constraints and body collision shapes, transferring deformation to the existing render mesh. The separate SoftBody proxy experiment demonstrates engine capability only and is not an approved replacement for this cape.

Increasing global gravity or lowering stiffness without garment-specific evaluation could collapse panels into the body or change unrelated hair/tail behavior. The existing finite imported settings remain the runtime default until a replacement is visually and temporally validated. The [VRM secondary-animation specification](https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/README.md) defines these bone spring parameters; it does not encode a full cloth material or inextensible mesh simulation.
