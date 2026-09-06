# Native face / mouth diagnostic

2026-09-06. Godot 4.5.2 Linux Forward+ / llvmpipe, DISPLAY=:0. Original three VRM files are unchanged. The probe loads through the production VrmAvatar importer, resets the skeleton to rest, applies no motion player and explicitly clears morph weights before each expression. Camera is orthographic, head close-up, fixed lighting.

## Finding

Cheval's black mouth at silence is caused by the MToon outline pass, not an open jaw, incorrect viseme index, PCM envelope, missing neutral preset, or black mouth texture. `outline-isolation.png` compares the same original mesh/material first with its imported outline and then only with `Material.next_pass` removed. Zero expression weights yield a black mouth with the outline and a closed natural mouth without it. Applying Cheval's authored neutral at 1 does not remove the black mouth. Rice and Eishin are also included as controls.

The screen-outline shader uses `conventional_outlined_vertex.z` after screen-space XY displacement, extruding inner mouth geometry toward the camera. Cheval FACE uses screen outline width 0.4, corresponding to a 0.004-unit normal offset for its depth. Inner mouth outline triangles become visible in front of closed lips. The proposed fix preserves original view-space depth for screen outlines; its final screenshot validation is recorded separately after the shader owner applies it.

The disable-outline run is a diagnostic ablation, not the production fix. It removes useful outlines elsewhere, so should not be deployed.

## Expression scope

Original Cheval VRM: aa -> A index 0, ih -> I index 1, oh -> U index 2, neutral -> Ne index 5; each preset binding weight is 100%. These are the authored preset-to-target mappings, including the apparently unusual oh-to-U naming, and should not be replaced by target-name guesses. Rice aa/ih/oh bind indices 126/128/134 at 70.9/73.9/85.4%; Eishin indices 136/138/134 at 100%. No mesh default morph weights are authored in these assets.

All three characters have raw-zero, authored-neutral, and independent aa/oh/ih at 0.1, 0.3 and 0.6 in `renders/` and `no-outline/`. These are expression weights; final mesh weights additionally multiply each authored binding weight. Cheval aa=0.3 gives slight parted lips, aa=0.6 a modest opening without the outline artifact. Motion playback should keep speech visemes within a combined budget around 0.6, and return to exact zero on reset/silence. There is no need to force neutral=1 at idle.

## Reproduce

From the repository root:

```sh
DISPLAY=:0 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script ../diagnostics/face/render_face.gd
DISPLAY=:0 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script ../diagnostics/face/render_face_no_outline.gd
```

`FACE_RENDER_DIR=/absolute/output` overrides the first probe's output directory. Existing `renders/` are pre-fix evidence; use a different output for shader verification. These Linux renders establish the cause; final Windows host validation remains separate.

## Fixed-outline verification

The shader owner applied the view-space depth fix and safe XY normalization. Re-ran all 33 expression images in `fixed-outline/`, retaining outline next passes. `fixed-outline-comparison.png` was visually inspected: Cheval's zero-weight mouth is closed, aa 0.3 is slightly parted, aa 0.6 opens modestly, and oh 0.6 rounds naturally. Rice/Eishin zero-weight mouths remain closed, with natural aa/oh opening. Hair/clothing outlines are visibly retained. No black inner-mouth triangles remain in these inspected samples.

`fixed-outline-probe.log` records exact runtime target mappings and jaw state. Cheval and Rice Jaw transforms equal rest transforms; Eishin does not expose a normalized Jaw. Binding weights match source percentages times the addon's 0.99999 singularity avoidance factor. This supports an outline-depth cause rather than jaw or index corruption. Validation here is Linux Forward+, not final Windows desktop playback.
