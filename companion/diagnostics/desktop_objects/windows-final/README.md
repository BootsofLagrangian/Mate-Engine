# Final native furniture acceptance — 2026-09-06

The professional reference-informed props and shared occupied scene passed actual Windows Vulkan/RTX 4090 checks and independent visual review on one exported executable.

- Package SHA256: `80303c7e703a5dbd526d343a2ac1ddd64af4b05ea8cbedd44094eb7c6bda170f` (99,674,664 bytes).
- Build records show source stable during export. Every run records actual selected session, VRM filename and model hash.
- [Compact acceptance](acceptance.json): **265 checks, zero failures**. Independent review: [shared host](../SHARED-HOST-REVIEW.md).

| Actual rig | Pet scale | Scope | Passed |
|---|---:|---|---:|
| Cheval Grand | 0.6 | All three contacts; occupied move, resize, hide, remove; stop; persistence; completed computer use | 100 |
| Rice Shower | 0.6 | All three contacts; persistence; explicit chair stop; completed computer use | 55 |
| Eishin Flash | 0.6 | Same contact scope | 55 |
| Eishin Flash | 1.0 | Same contact scope at larger size | 55 |

Occupied mutation coverage is Cheval-only. The selected artifacts contain 16 occupied shared-root captures and 12 initial standalone prop-window captures. Reviewers inspected chair, sofa and computer placement, physical scale, limb contact and occlusion for all four cases. Occupied captures contain the actual character and furniture in the same 3D depth buffer; they are not separately layered images or captures of unrelated desktop pixels.

Every computer case reaches both physical keyboard sockets within the unchanged 2 cm / 3 px thresholds and finishes with a matching completed outcome. Seat projection errors are below one pixel. Seated floor constraints use bounded leg IK and eligible spring-chain floor collision; they do not provide general cloth or furniture collision. Computer use is an animated interaction, not keyboard input to a real application. Handheld tools remain a future extension of the socket contract.

## Selection and retained failures

The four final runs are exactly those listed in `acceptance.json`; no final run was omitted. Earlier development failures remain under ignored `logs/`:

- `windows-objects-premium`: 88 functional passes on an earlier package, but visual review rejected oversize props and computer occlusion.
- `windows-objects-shared-development`, `windows-objects-shared-dev2`, `windows-objects-shared-dev3`: unsafe contact, support identity, world snapshot, persistence precision and insufficient reach candidates. These prompted the explicit owned-seat lock, robust snapshot reader, physical prop scale and actual chair placement fix.
- `windows-objects-floor-cheval-full`: package `93fc119e…` failed to find imported GLB resources through a physical-file-only check. The final resource-loader guard was verified against all three embedded PCK assets before the accepted runs.

See [design research](../visual-redesign.md), [seated geometry review](../SEATED-GEOMETRY-REVIEW.md), [floor constraint validation](../../seated_floor/README.md) and [probe review](../WINDOWS-PROBE-REVIEW.md) for diagnosis and limitations. Raw traces and character-containing images stay outside Git; compact records preserve their hashes.

## Reproduce the aggregate

From `companion/`, after running the external Windows probe for each case:

```sh
python3 diagnostics/desktop_objects/summarize_windows.py \
  --input logs/windows-objects-floor-v2-cheval-full \
  --input logs/windows-objects-floor-v2-rice \
  --input logs/windows-objects-floor-v2-eishin \
  --input logs/windows-objects-floor-v2-eishin-scale1 \
  --output diagnostics/desktop_objects/windows-final/acceptance.json
```

The probe is `native/tools/probe_windows_objects.gd`, supplied externally to the exported executable. It accepts `--character`, `--scale`, `--contact-only`, `--test-root` and `--output`; normal settings are restored at exit.
