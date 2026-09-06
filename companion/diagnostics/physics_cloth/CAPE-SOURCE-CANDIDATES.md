# Recovered cape source and nondefault candidates

**Follow-up:** the manual seated-transition test was scheduling-confounded. The corrected automatic comparison also finds excessive stand-up motion, so candidate 1.2 remains rejected for the production default. See [continuous acceptance](CAPE-CONTINUOUS-ACCEPTANCE.md). The snapshot improvements below remain research observations.

The original UMA secondary-physics data is recoverable. `extract_cyspring_profile.py` reads the serialized Unity `Gallop.CySpringDataContainer`, preserving raw fields and provenance in a versioned JSON profile. No runtime or default VRM was changed by this follow-up. This is a source recovery and small comparison experiment, not a completed cloth replacement.

The selected local bundle is `3d/chara/body/bdy1089_00/clothes/pfb_bdy1089_00_cloth00`, SHA256 `e1385d37f4614d469e56eb759c659947a8d02084d76f2ea441474d3a68aa4a72`. It has four cape chains / 18 joints, 27 collider entries and four connected-panel links. Other locally inspected cloth01–04 containers differ; their game-mode selection is not established. The main body prefab alone only exposed an AssetHolder, so the separate clothes bundles were necessary.

The source specifies per-joint stiffness, drag, gravity, radii, asymmetric angular limits, inside spheres, capsules, and links coupling shoulder and chest panels. The supplied VRM has a substantially simpler spring representation. UnityPy's [serialized-object reader](https://github.com/K0lb3/UnityPy/blob/master/UnityPy/files/ObjectReader.py) exposes the embedded type tree. The corresponding [CySpring parameter declaration](https://github.com/katboi01/UmaViewer/blob/07f82e9fa08f23c1cda3a9be3045a09372eae8bb/Assets/Scripts/umamusume/Gallop/Cyspring/CySpringParamDataElement.cs) and [native wrapper](https://github.com/katboi01/UmaViewer/blob/07f82e9fa08f23c1cda3a9be3045a09372eae8bb/Assets/Scripts/umamusume/Gallop/Cyspring/CySpringNative.cs) confirm these data fields and separate solver rate arguments. They do **not** establish that raw values use VRM units. The repository's older managed DereScript solver is useful context, but is not proof of the current UMA native implementation or its time normalization.

## Reproduction

From the repository root, with UnityPy installed (the tested environment used UV Python 3.12):

```sh
uv run --python 3.12 --with UnityPy --with numpy --with scipy python companion/diagnostics/physics_cloth/extract_cyspring_profile.py /mnt/f/ULTIMA/UMA-Extractor/UmaMusumeToolbox/uma_asset/3d/chara/body/bdy1089_00/clothes/pfb_bdy1089_00_cloth00 companion/assets/research/cape-candidates/cyspring-cloth00.json --bone-contains Mantle
```

The full source profile remains in ignored research assets. The compact selected data and source identity are retained in `cape_candidates/source-summary.json`.

`native/tools/probe_cape_candidates.gd` reads that profile and changes only matching chain resources inside its own diagnostic scene. Each resource is shallow-duplicated to preserve existing collider identities; per-joint numeric arrays are replaced. This avoids changing the shared imported tail group. The probe records actual runtime arrays at each sampled point and preserves original values for nonselected-chain comparison.

## Candidate definition and selection disclosure

The initial exploratory captures accidentally retained the imported global stiffness/gravity scales while adding per-joint arrays. Independent review identified that their labeled anchors were not effective forces. Those results are preserved as `scale-confounded-report.json` / `probe-scale-confounded.gd.txt` and are not used as final numerical configurations. The corrected probe sets only the isolated candidate's stiffness/gravity scales to 1 and records every relevant scale with the arrays.

For each chain, `stiffness[i] = 2.5 × source_stiffness[i] / source_stiffness[root]`; `gravity[i] = anchor × source_gravity[i] / source_gravity[root]`. Imported drag, radii, colliders, rig, mesh and weights are retained. The source angle limits, panel links and extra collider types are **not implemented** by this scalar experiment. None of the anchors is asserted to equal original game physics.

The initial, scale-confounded anchors 0.6 and 1.2 visually failed: their increased distal stiffness made panels wider/flatter. After that observation, anchors 5.0 and 12.5 were added. Independent review then found the global-scale interaction, and all four were rerun with corrected effective units. All choices and the confounded report are retained. This is an adaptive diagnostic sweep, not a preselected comparison or a tuned production configuration.

Both sides use actual enabled SkeletonModifiers at the same origin, with explicit initial spring rebase. Each of relaxed rest, overhead stretch and arm stretch runs for three seconds at fixed 60 Hz. A centered oblique camera provides seven paired snapshots per cell; source poses are held during sequential readback. The first callback may not yet exist at frame 0 and empty snapshots must be excluded. This is a bounded visual test, not full skinned-mesh strain, interpenetration, dense jitter, seating, turning or Windows desktop acceptance.

The corrected run executed 4,488 candidate modifier callbacks. Its 2,940 parameter checks confirm effective selected arrays/scales and exact unchanged parameters/collider identities for nonselected chains. At overhead stretch 1 s, effective anchor 1.2 reduces the sampled cape-bone X span from 1.1279 m to 0.8207 m and increases mean chain-root-to-tip vertical drop from 0.4952 m to 0.5918 m. These are bone proxies, not full garment mesh measurements. Its inspected render is a more hanging candidate; anchor 0.6 changes the silhouette less. Effective anchors 5.0 and 12.5 collapse the panels into narrow body-adjacent strips in inspected views and are rejected.

Stronger gravity can lower the outer panels in the inspected views. This is a candidate direction for further constrained garment work, **not approval to change the default**. Unknown force units, missing panel coupling and collision/angle-limit fidelity prevent a claim of authentic source cloth. The original VRM and runtime remain the default.

The next substantive step is to implement or adapt a generic constrained secondary/garment solver that can consume the recovered limits, connected-bone distances and correctly transformed collision shapes, then validate a separate profile against rest silhouette, continuous motion and mesh deformation. A garment-specific remeshed cloth solution is another option. Stronger global gravity alone is not a substitute for those constraints.
