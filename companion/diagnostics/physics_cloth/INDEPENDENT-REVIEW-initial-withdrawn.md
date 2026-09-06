> Historical initial review. Behavioral acceptance was reopened because the manual spring probe did not restore nonhumanoid poses as the live SkeletonModifier does. Do not cite its overlap comparison as runtime evidence. See INDEPENDENT-REVIEW.md.

# Independent physics review

**APPROVED** for the added secondary-bone hand/forearm contacts, conservative mini-rig spring authoring, and separately identified cloth feasibility experiment. Reviewer: `/root/physics_review`. This does not approve a claim that production costumes now have full cloth physics or that every hand/body intersection is solved.

## Runtime and lifecycle

Inspected `vrm_spring_contacts.gd`, the three `VrmAvatar` lifecycle hooks, and the imported collider/secondary/spring integration code. Added proxies affect spring endpoints through the existing integrator. They do not change authored spring stiffness, gravity, drag, joint lists or imported collider resources. Humanoid chains and the same arm's descendant sleeve chains are excluded. A weak reference from each callback to the owner avoids a retained callback ownership cycle.

An independent actual-rig check passed **1,617 assertions, zero failures**: storage-property snapshots before/after configuration and cleanup, repeated configuration without duplicate proxies, exact preservation of pre-existing collider counts, clear/reload detachment, safe retained callbacks after detach, humanoid exclusion, and the real collider callback at uniform scale 0.6/1/1.4 with yaw 45° and translation. Maximum callback length error was below 0.00000006 m. Reproduce from `companion`:

```sh
./tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script ../diagnostics/physics_cloth/review_lifecycle.gd
```

`review-lifecycle.json` and its log retain this independent run. Scale checks cover the new callback's transformed sphere and fixed-length projection; they do not establish scale invariance of the entire existing VRM spring addon.

## Behavior evidence

Inspected the implementer's matched three-rig × two-authored-motion experiment, its source, JSON and actual Eishin seated before/after renders. The comparison disables only the added proxies in the baseline, uses the same imported assets and manually fixed spring timestep, and measures all six cells. Endpoint/proxy overlaps above 10 µm fall from 644–4,233 samples to zero. The rendered Eishin skirt visibly changes around the wrists. This is meaningful response in the actual rig, beyond a mathematical projection test, but its metric is not a skinned-triangle collision test. The source still permits impossible simultaneous constraints and gaps between sparse proxies.

The mini authoring helper was independently exercised against both published mini VRMs: existing secondary metadata remains byte-equivalent as parsed data; first authoring on a copy with empty secondary metadata changes only `secondaryAnimation`; a second call is idempotent. Results are in `review-mini-authoring.json`. The published mini displayed-frame probe has 20/17 imported spring chains and 120/102 added contacts for Mambo/Hachimi, respectively. Both remain finite over 360 sampled displayed frames; maximum sampled tail steps are approximately 5.95/8.45 mm. The helper explicitly identifies this as new Mate tuning, not recovered game physics. These measurements do not establish arbitrary-motion stability or cloth wrinkles.

## Cloth experiment and limitations

Inspected the Jolt probe source, measured JSON and actual rendered proxy. It simulates a newly constructed 288-vertex skirt with 32 pinned waist vertices and moving collision bodies. It does not modify a character costume or switch the production pet to cloth simulation. Its finite deformation and pinned-point error support a native-engine feasibility result.

The 3.51 ms mean physics-process monitor versus 1.09 ms preceding baseline is an exploratory sequential scene observation. The active cloth begins immediately after creation, while the baseline is warmed; phase and sampling duration also differ. This is not an isolated steady-state cloth cost. Physics runs on the CPU; using the RTX 4090 renderer does not imply GPU cloth simulation. GPU timing returned zero and is unavailable. The existing README accurately limits production performance and garment claims.

No blocking defect remains in the reviewed scope. Garment-specific simulation meshes, skin-transfer bindings, body/furniture collision coverage and fine wrinkle topology remain separate implementation work. Exact reviewed source and asset hashes are retained in `review-source-hashes.json`; no Windows application was launched by this reviewer.
