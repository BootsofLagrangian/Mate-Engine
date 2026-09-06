# Independent camera and spatial review

Verdict: **APPROVED for projection geometry and canonical world-pose integration**, with the Windows composition and picking limits below. This review does not approve concurrent seating animation, floor-envelope changes, garment physics, facial rendering, or motion naturalness.

The reviewer inspected the actual current implementation and independently ran Godot 4.5.2 tests. `source-identity.json` identifies the files reviewed; these files also contain unrelated concurrent work outside this scope.

## Evidence

- Orthographic projection: 5,274 checks, no failures.
- Perspective and off-axis crop projection: 454 checks, no failures; maximum global crop residual 0.004788 px.
- Actual imported chair projection: 14 checks, no failures. Doubling optical depth shrinks geometry without changing physical scale; socket pixels match the reference camera.
- Host migration, persistence and rollback: 9 checks, no failures. A later camera/FOV/calibration change preserves world transform and stored migration factor; a behind-eye edit is rejected and reverted.
- Real main projection methods with three imported rigs: 54 checks, no failures; maximum foot-pivot residual 0.000173 px. Simulated native window movement changes only the crop: the canonical camera and a fixed world point's desktop projection remain invariant. Networking, UI and locomotion were suppressed.
- Reviewer-authored standalone-to-contact socket transfer: 33 checks, no failures after correction, using actual Store, Host method, imported Window geometry and ContactScene. Covers chair, sofa and computer at object yaw 0°, 45°, and -110° with physical scale 0.8.

The two affected window/host tests were rerun after shared World3D integration. Their additional reruns are not new independent test cases. All logs are retained here.

## Defect found and corrected

The standalone computer applies an authored 35° presentation rotation in `DesktopObjectWindow._apply_visual`, but the first spatial contact path applied only record yaw and reset the recommended rotation. Entering contact therefore moved keyboard/use/inspect sockets by 9.3–11.8 cm at scale 0.8. The reviewer reproduced 12 failures in 33 checks through the actual Host method (`socket-transfer-before.log`). The corrected spatial contact transform includes recommended presentation yaw, and activation preserves it. The same probe now passes (`socket-transfer-after.log`). This proves geometric continuity for these sockets, not natural sitting choreography.

## Shared scene and limits

Originally each native prop had an independent World3D, so native window stacking could override scene depth. The revised spatial path gives root and prop crops one World3D, disables duplicate prop lighting/environment and hides standalone model roots while a contact scene replaces them. The reviewer inspected these paths.

The implementer's `../shared-world-render/report.json` contains 150,822 opaque rendered samples with zero RGB mismatches across a full camera and two off-axis crops of overlapping imported chairs. The reviewer inspected its source, report and full image: the near blue chair occludes the farther red chair. This is Linux rendering evidence for shared scene depth, not an independently rerun Windows compositor test. Its test uses SubViewports, so actual native Window lifecycle remains a separate runtime check.

Partially transparent/antialiased edges can still blend more than once where native windows overlap; equal RGBA crops do not imply equal final desktop compositing. The full render has 2,635 partial-alpha pixels. Likewise native input ownership may differ from the frontmost visible mesh in an overlapping crop; ray-based object picking is not established by these tests. Neither limitation changes the demonstrated metric depth, projection or opaque scene occlusion, but neither should be described as solved.

No Windows application was launched by this reviewer. The parent owns final native acceptance. No visual-naturalness or full three-dimensional navigation claim follows from these results.
