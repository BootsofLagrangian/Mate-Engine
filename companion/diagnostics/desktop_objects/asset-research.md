# Desktop furniture asset acquisition

Downloaded 2026-09-06 from the [official Kenney Furniture Kit page](https://kenney.nl/assets/furniture-kit), which identifies 140 files and CC0. The [official archive](https://kenney.nl/media/pages/assets/furniture-kit/440e0608a4-1677580847/kenney_furniture-kit.zip) contains an original `License.txt`, retained byte-for-byte beside the five selected GLBs. It names Creative Commons Zero; the [CC0 deed](https://creativecommons.org/publicdomain/zero/1.0/) is its referenced license. Exact archive/file hashes and original extraction paths are in `assets/desktop_objects/kenney_furniture/manifest.json`.

Selected original models: red upholstered `loungeSofa`, matching red `chairDesk`, wood `desk`, muted dark `computerScreen`, and `computerKeyboard`. All use embedded material factors with no external textures. The originals are unmodified; runtime code can place screen and keyboard on the desk surface to create one computer workstation. No animations, character attachment sockets, or avatar-specific alignment are provided by the pack.

## Geometry and integration hints

Units below are original pack units. +Y is up. Sofa/chair backrests are on negative Z, so seated avatars face +Z. Desk drawer/front is +Z. Screen/keyboard use direction is an integration convention. Each original GLB has a corner-style origin; apply `center_ground_offset` before scaling. Socket Y matches measured vertex elevations, while socket X/Z and approach points are authored hints requiring runtime avatar fitting.

| Model | Size X/Y/Z | Center/ground translation | Centered socket hints |
| --- | --- | --- | --- |
| loungeSofa | [0.98, 0.46, 0.41] | [-0.49, -0.0, 0.205] | {'seat': [0.0, 0.23, 0.035], 'approach': [0.0, 0.0, 0.485]} |
| chairDesk | [0.33495, 0.6076, 0.314299] | [-0.167475, -0.0, 0.15715] | {'seat': [-0.0, 0.247394, -0.02285], 'approach': [-0.0, 0.0, 0.40715]} |
| desk | [0.734475, 0.384408, 0.3923] | [-0.357238, -0.0, 0.18385] | {'surface': [0.0, 0.384408, -0.00115], 'use': [0.122762, 0.0, 0.46385]} |
| computerScreen | [0.392688, 0.294285, 0.104004] | [-0.196344, 0.0, 0.052002] | {'screen': [-0.0, 0.17, -0.002998], 'use': [-0.0, 0.0, 0.272002]} |
| computerKeyboard | [0.2822, 0.027556, 0.118192] | [-0.1411, -0.0, 0.059096] | {'keys': [-0.0, 0.027556, -0.0], 'use': [-0.0, -0.0, 0.219096]} |

The sofa seat is Y=0.230000, office-chair seat Y=0.247394, and desktop top Y=0.384408. For a workstation assembled in desk-centered space, put the monitor base at desk top and toward the back (negative Z), and keyboard near the front (positive Z). Uniform scale must be applied consistently to all parts and socket coordinates. These are prop-space hints, not a claim that a particular avatar's hips/hands have been calibrated.

## Validation and scope

Python decoded GLB float32 position buffers and traversed source nodes, including the office-chair child mesh and desk drawer. Source transforms had identity rotation/scale; node translations were accumulated for bounds. Godot 4.5.2 headless `GLTFDocument.append_from_file` and `generate_scene` successfully loaded all five files in an isolated `/tmp` project (exit 0). Official isometric PNGs were visually inspected for sofa, chair, desk and monitor. Native-window rendering and avatar interaction remain the runtime implementer's validation responsibility.

The archive license labels the pack “Furniture Kit (2.0)” while the official page update says 1.0 released in 2018. The manifest retains this discrepancy and uses the archive SHA-256 as the precise provenance identifier. Only selected models and original license are retained in the repository; the full downloaded archive remains temporary.
