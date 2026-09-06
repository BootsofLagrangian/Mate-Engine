# Reference-informed premium furniture — 2026-09-06

The requested change replaces the blocky first-pass furniture with three original curved 3D props, informed by downloaded official product photographs. This is authored geometry, not a photograph plane, icon, Kenney recolor, or imported manufacturer CAD model.

## Reference images actually downloaded and inspected

Official product pages and image URLs:

- Muuto Outline 2-Seater: https://www.muuto.com/product/Outline-Sofa-2-Seater — https://cdn.occtoo-media.com/4d81f22f-2795-41f2-b8bf-15e9abf03890/a8bba6fa-3566-5b1c-9059-3fcbe083c771/Outline-sofa-2-seater-remix-163-black-Muuto-5000x5000-hi-res.webp?format=medium
- Herman Miller upholstered Sayl: https://www.hermanmiller.com/products/seating/office-chairs/sayl-chairs/product-details/ — https://www.hermanmiller.com/content/dam/hmicom/page_assets/products/sayl_chairs/it_prd_dtl_sayl_chairs_02.jpg.rendition.480.480.jpg
- Muuto Workshop Table: https://www.muuto.com/product/Workshop-Table — https://cdn.occtoo-media.com/4d81f22f-2795-41f2-b8bf-15e9abf03890/f3d665cb-26ff-5393-94ec-a7c70c5d9004/Workshop-table-200x92-cm-oak-angle-Muuto-5000x5000-hi-res.webp?format=medium

Local inspected reference files: `/tmp/mate-prop-references/{sofa.webp,chair.jpg,desk.webp}`. Manufacturer photographs are visual references only, outside the repository and game bundle. The reference download inventory includes checksums below. Source pages were browsed on 2026-09-06. No redistribution license for manufacturer product photographs is asserted.

## Design translation

- **Sofa:** Outline's separated two-seat cushions, narrow wrap arms, open space below the deck, recessed thin dark legs. Original sage upholstery, softened/puffier cushions and original sewn welt curves. Overall 1.821m wide, seat socket 0.428m high; this intentionally adapts the reference rather than reproducing a branded product exactly.
- **Chair:** upholstered Sayl's tapering back, shaped seat, ivory arm structure, gas lift and five-star caster base. Real curved upholstered surfaces, waterfall seat, sewn edge, bent arm uprights, twin rubber wheels and adjustment paddle. Original proportions and simplified back support, not a manufacturer replica.
- **Computer desk:** Workshop's 130×65×73cm small-table proportions, slim inset top, thin oak apron/legs and linoleum/oak material split. Original thin monitor, individually beveled keycaps, fabric desk pad and rounded mouse. Screen pixels are an original procedural quiet desktop illustration, embedded only on the real 3D LCD surface.

Color family: muted sage fabric, warm ivory frame, light natural oak/linoleum, graphite hardware. Real superellipsoid upholstery, mesh piping and physical bevels carry the silhouette at small desktop size. No dependence on a custom render shader.

## Files and reproduction

Runtime: `native/assets/desktop_objects/premium/{chair.glb,sofa.glb,workstation.glb,objects.json,PROVENANCE.md}`. GLBs embed all textures and standard glTF metallic/roughness materials. Meshes are joined by material to reduce draw calls. No camera/light/floor is exported. Old Kenney assets and license are preserved.

Build: `diagnostics/desktop_objects/build_premium_props.py`, using Blender Python `bpy==5.0.1`, Pillow and NumPy. Example environment:

```sh
uv venv --python 3.11 /tmp/mate-prop-bpy
uv pip install --python /tmp/mate-prop-bpy/bin/python bpy==5.0.1 pillow numpy
/tmp/mate-prop-bpy/bin/python diagnostics/desktop_objects/build_premium_props.py
```

The script also generates two views per prop in `premium-previews/`: `{chair,sofa,computer}-{front,threequarter}.png`. Front camera elevation corresponds to runtime's `(0,.55,3)` offset; Cycles lighting differs from runtime. Textures `fabric.png`, `oak.png`, `screen.png` are original deterministic generated pixels.

## Coordinate and socket contract

Meters, +Y up, +Z front, near-centered X/Z. `objects.json` is authoritative for actual bounds, file sizes and sockets. Sofa feet start 0.005m above zero; runtime must use actual ground/bottom projection, already implemented by the integration owner. Chair's floating-point minimum is approximately zero.

- Chair: `seat [0,.48,.08]`, support width `.43`; `inspect [0,.76,-.17]`.
- Sofa: `seat [0,.428,.12]`, support width `1.46`; `inspect [0,.58,-.19]`.
- Computer: `use [-.055,.77,.185]`, `keyboard_left [-.16,.77,.185]`, `keyboard_right [.08,.77,.185]`, `inspect [0,1.017,-.194]`.

These are designed contact locations on geometry; actual character wrist/pelvis contact remains a runtime integration measurement, not established by this model export.

## Inspection and independent assessment

Author inspected downloaded reference images and all three final asset renders. First preview issues (chair crop and monitor stand crossing in front of LCD) were corrected and rerendered. Front and three-quarter views now contain the full chair and unobstructed monitor.

Independent reviewer `astra_face` inspected all three reference photographs and all six updated Cycles renders and returned **APPROVED** for standalone prop design. Findings: clear improvement in rounded upholstery/seams, castors/armrests, thin LCD/keys, restrained wood desk. Optional: slimmer/less pillowy sofa arms would move closer to the reference. No blocking standalone visual defect. Reviewer explicitly limits this approval to standalone Cycles design, not Godot lighting parity, desktop scale, occlusion or contact.

Root independently inspected the initial three renders and confirmed the material/silhouette improvement. Runtime Godot preview and character contact checks are owned by `astra_autonomy`/root and must be recorded separately before whole-feature closeout.

## Artifact inventory

| Asset | Triangles | Materials | Bytes | SHA256 |
|---|---:|---:|---:|---|
| chair.glb | 25936 | 7 | 714712 | `486e7155c27d9a533a780796fb5eac58c98db170d84a151687903d16c32b1558` |
| sofa.glb | 38540 | 4 | 1004640 | `73bd79058d389cb6d83a4a4c32198f4fc500726c46872d5da1f429a44b933578` |
| workstation.glb | 27998 | 10 | 926752 | `eb79a71d3661d39fa0d40814e0dc35309789f73e3ec2e7a4cfe245b640954709` |

Reference download checksums:

- `sofa.webp` (4644 bytes): `8ffc64d6fc4009e4555ef0a5fec7a5cebcd97ac4c6475589ea2edf94dd98965e`
- `chair.jpg` (21791 bytes): `1b5c1700cc1dc7741ab090912677bf9aead2eef9558c4ccc02e4c15edac71ebd`
- `desk.webp` (5866 bytes): `3520ead714b9fafdb6837e54caa4a104f06564904ac873004966dcb847b6b927`

## Native composite geometry audit (follow-up)

Inspected root's `logs/windows-objects-premium/{chair,sofa}-composite-assumed-pet-front.png` and native loaded captures. Materials and curved silhouettes transfer well to native Godot. The composite uses same-frame own viewports with assumed pet-over-prop layering; it does not establish operating-system z-order.

To investigate the reported apparent 30–50px cushion gap, reimported the final GLBs and cast downward rays against evaluated mesh triangles at the socket and bilateral support positions. Reproduction: `audit_premium_seat_geometry.py`, then `overlay_premium_seat_geometry.py` (bpy environment). Raw results: `premium-seat-raycast.json`; annotated images: `premium-previews/{chair,sofa}-native-seat-overlay.png`.

- Chair actual top at `(0,.08)` in X/Z: Y=`.488926m`, whereas socket Y=`.48m`. At X=`±.06m`, top is `.489114m`. Socket is about **3.11 native pixels below** bilateral cushion top, not above it.
- Sofa at X=`0` lies in the physical narrow seam gap between independent cushions; a vertical ray reaches lower deck Y=`.324456m`. Bilateral butt-support positions at X=`±.06m`, Z=`.12m` hit actual cushion tops Y=`.43455m`. Socket Y=`.428m` is about **2.48 native pixels below** those support points. The center gap is not the intended singular load-bearing support; the pelvis spans both cushions.
- Using runtime's frontal camera elevation `atan(.55/3)=10.39°`, the current captures correspond to approximately **347.39px/m chair** and **385.37px/m sofa**. Projection of the cushion front/rounded lip is lower than the top contact surface. Comparing the avatar against that lip alone overstates an apparent vertical gap.

This isolates the authored sockets as not causing a 30–50px upward separation. It does not approve the avatar's stable/rest-derived seat anchor as a rendered anatomical contact point. The native composites also show furniture visibly oversized relative to the default character. Integration owner is investigating pose-aware avatar bounds/anchor and size selection; no asset geometry or runtime metadata was changed during this audit. The review should compare final seated skin/garment geometry with the projected cushion top, and use consistent avatar/furniture visual scale.

Packaging provenance is also supplied as `native/assets/desktop_objects/premium/PROVENANCE.txt` because runtime exports exclude Markdown. This preserves repository licensing and explicitly excludes manufacturer photographs from the bundle.

Independent follow-up reviewer `astra_face` inspected both native overlays, raycast/projection scripts and measurements: **APPROVED the narrow geometry inference**. Coordinate conversion and orthographic projection are consistent. Reviewer confirms this does not establish avatar buttock/thigh mesh contact and that furniture oversize is plainly visible. The sofa's minimum inter-cushion gap comes from source construction (`2 × .385m` center spacing minus `.763m` cushion width = `.007m`), not an inference from the six sampled rays; the rounded gap varies with height/depth.

## Shared occupied furniture scene

Added `native/scripts/desktop_object_contact_scene.gd` as an isolated geometry owner for the avatar's existing 3D world. It creates no camera, light, window, motion or desktop lifecycle. Integration owns transform/visibility and native-window hide/restore.

API: `configure(type)`, `clear()`, `has_socket(name)`, `socket_local(name)`, `socket_world(name)`, `socket_catalogue(world_space=true)`, `get_local_bounds()`, `get_world_bounds()`, `geometry_points_local()`, `facing_direction_world()`. Properties: `loaded`, `error`, `object_type`, `recommended_yaw_degrees`.

Chair/sofa retain +Z user facing and zero recommended presentation yaw. Computer adds the existing premium chair at `(0,0,.60)` with Y rotation `PI`; the actual transformed chair seat is `(0,.48,.52)`. The user faces local -Z toward the keyboard/monitor. Recommended whole-arrangement yaw is +35°; avatar heading is therefore 215° in the host's +Z-front convention. This offsets the monitor to the left of the seated user's head in projection. The keyboard is 0.29m above the seat, 0.335m forward, with local negative-X for user left and positive-X for user right. These are geometry contracts; bilateral reach still requires posed avatar validation.

Actual Godot 4.5.2 headless test `test_contact_scene.gd`: **31 checks, 0 failures**, covering real GLB loading, repeated configuration, world socket transformations under translation/yaw/scale, all-vertex AABB containment, chair seat transformation, user/keyboard/monitor depth ordering, failure cleanup and idempotent clear. Independent `astra_face` implementation review: **APPROVED**, no blocker within this module's scope.

Actual native scene render: `premium-previews/computer-shared-scene-native.png`, generated by `render_contact_scene.gd` at 680×760, Godot 4.5.2 GL Compatibility/Mesa llvmpipe. Author inspected the output: chair faces the desk, keyboard and monitor remain visible at the recommended angle, all geometry fits. This image contains the furniture arrangement only, so it establishes neither avatar contact nor final Windows rendering parity. Root/autonomy own final shared-world character pose, calibrated bounds, reach and lifecycle checks.

### Physical-scale reach refinement

Final computer chair center Z is **0.60m**, moved 4cm toward the desk from the initial 0.64m arrangement. The transformed chair seat is Z=0.52m. Actual workstation/keyboard meshes and sockets are unchanged. This is a physical furniture placement correction for Rice Shower's approximately 10.95mm short right-hand reach at ordinary scale, not a displaced or softened contact target.

After the change, `test_contact_scene.gd` remains **31/0**. Integration owner's `test_shared_work_reach.gd` rerun against the production constant (no fixture offsets) passes **all six hands across Cheval Grand, Rice Shower and Eishin Flash**, maximum measured world error **7.03e-8m**. Evidence: `shared-work-reach-final.log`. These are strict solver acceptance and final transformed wrist checks; final Windows pose rendering remains a separate check.

Mesh clearance stays natural: the nearest chair seat front is approximately Z=.3525m, still 27.5mm outside the tabletop front at Z=.325m; chair arm caps remain around Z=.491m or farther, clear of the desk apron. Rerendered and inspected the actual Godot standalone arrangement at the updated position. Also inspected root's earlier `windows-objects-shared-dev3/computer-use-shared-depth.png`: same-world chair/desk/avatar depth and monitor-facing presentation read coherently, with the display unobstructed. That earlier image used a temporary size and is not evidence for this final physical-scale revision.
