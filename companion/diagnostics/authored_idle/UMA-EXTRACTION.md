# Local UMA motion extraction

The fixed subset exporter reads the user-authorized local UMA asset tree and copies **32 motion bundles plus one body rig** into its own ignored working directory. It does not change source bundles/configuration, install runtime motions, or perform a bulk asset export.

Run from WSL with the installed Windows .NET 8.0.30 host and Windows Framework C# compiler:

```sh
python3 companion/diagnostics/authored_idle/export_uma_subset.py
```

Defaults target `/mnt/f/ULTIMA/UMA-Extractor`, with output at `companion/assets/research/uma/export-work/natural-subset`. An existing nonempty output directory is refused; use `--output` for another preserved attempt. Tool paths and asset root can be explicitly overridden. The assets are local working material, not redistributable fixtures included by this helper.

## Export contract

Selection comprises 17 generic standing/turning/walking/chair phases and five idle phases each for character IDs 1089, 1030 and 1037. The actual bundle filenames are verified before copying. Manifest entries record source hashes, tool hashes, settings, output hashes and each output's source bundle. Source hashes are rechecked after extraction.

`AssetStudioSubset.cs` loads the copied rig and clips together through the installed AssetStudio API. Each FBX uses the rig Animator and an explicit single `AnimationClip[]`; automatic animation collection is disabled. Mesh renderer references are cleared **in memory only**, avoiding unrelated mesh/material dependencies while preserving the actual rest hierarchy. All nodes and animation are exported, without skins/materials/blendshapes or Euler filtering. No animated first frame is substituted for the rest pose.

The helper also writes `rig.json`: 128 original Unity local transforms with parent IDs, plus the Avatar's 132 hash-to-path entries. The CLI separately exports each clip's decompressed `.anim` curves. This supports direct curve retargeting without depending on FBX interpolation or units.

AssetStudio's [native loader](https://raw.githubusercontent.com/RazTools/Studio/main/AssetStudio.PInvoke/DllLoader.cs) resolves `x64` relative to the process executable, which is `dotnet.exe` in this setup. The helper therefore copies the existing FBX native DLL beside the local .NET host, refusing to replace a different existing DLL. The source installation remains unchanged.

## Coordinate and validation scope

The source JSON/YAML retains Unity axes and transforms. AssetStudio's [model conversion](https://raw.githubusercontent.com/RazTools/Studio/main/AssetStudio.Utility/ModelConverter.cs) mirrors translation X and quaternion Y/Z for FBX. With export scale factor 1, the motion agent's Godot import measured rest lengths at **0.01× the original rig JSON** because of FBX unit interpretation. Consumers must explicitly correct this scale or use original JSON as the reference; do not apply the basis conversion twice. Retargeting must also account for animated helper nodes such as `UpBody_Ctrl` and `Position`.

Initial proof exported standing idle and a 50-degree left turn, each containing a rest skeleton and one animation. The motion agent successfully imported both into Godot. The completed bounded run produced **32 FBXs, 32 YAML clips and one rig JSON**; all 33 source bundle hashes remained unchanged. Raw export logs, copied helper source and `manifest.json` are under the local output directory. The formatted tracked C# helper was subsequently compiled and reran the two-clip proof successfully.

This validates extraction and provenance, not final character motion quality. FBX/curve retargeting, helper-node folding, resampling fidelity and runtime visual acceptance belong to the downstream motion work.
