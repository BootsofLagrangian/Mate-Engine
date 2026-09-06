# Final build identity and regression records

`build.json` is the manifest copied from the final exported Windows executable. The executable SHA256 is `80303c7e703a5dbd526d343a2ac1ddd64af4b05ea8cbedd44094eb7c6bda170f`, 99,674,664 bytes. Runtime source hashes were rechecked against the working tree before closeout with no mismatch. External probes and downloaded character/motion assets remain separate identified inputs.

`acceptance.json` retains the 18 actual Windows surface assertions and the final Linux native selftest log (581 passed, zero failed), plus raw evidence paths and SHA256 hashes. These are different execution scopes: the selftest's audio driver is Dummy; the surface probe runs the real Windows RTX 4090 Vulkan host. The deliberate audio overflow warning belongs to the selftest's queue recovery fixture.

See [combined validation](../../VALIDATION.md), [furniture acceptance](../desktop_objects/windows-final/README.md) and [Windows movement analysis](../transition_chain/windows-shared-floor-final.md).

The staged diff whitespace check passes for authored files. Two vendor license files retain their original CRLF/whitespace bytes and are excluded from that whitespace-only check: `diagnostics/authored_idle/candidates/LICENSE.txt` and `native/assets/desktop_objects/License.txt`.
