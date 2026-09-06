# Independent mini asset/source/setup review

**APPROVED for the dry/wet source selection, geometry serialization, fixed-mouth source implementation, profile provenance, and setup variant regeneration reviewed here.** Spring metadata is a separate subsequent change and is outside this approval.

The reviewer independently discovered/extracted the original local material bundles before inspecting the converter implementation. The converter selects the exact `tex_mbdy1003_00_diff` / `tex_mchr1003_00_hair_diff` and corresponding `1062` mini-specific diffuse textures. All four embedded dry body/hair PNG payloads were byte-identical to those independent original exports. Dry images contain no wet texture selection; optional wet variants are accurately described as main-model wet diffuse adaptations on mini geometry.

Independent read-only checks passed: **366 assertions** across the four installed pre-spring VRMs, their exact hashes/sizes, GLB and buffer declarations, bounded buffer views, profile and standalone provenance equality, and every recorded local source bundle hash. Three isolated setup contract scenarios also passed with temporary synthetic files and a mocked converter: missing wet invokes conversion; complete matching variants skip conversion; a converter that leaves wet missing raises an error. These scenarios verify setup control flow, not another real asset conversion. The initial system-Python attempt lacked `requests`; the three scenarios subsequently ran successfully in the project virtual environment.

Source inspection confirms mirrored source geometry and reversed winding are applied once, skin data remain linked to recorded source bones, and mouth deformation uses one source atlas surface with a persistent skin cover. This review does not independently repeat the separate Windows mouth visual assessment. Rights metadata credits Cygames, marks the local conversion as not independently licensed, and explicitly infers no redistribution license. Fan persona examples and official speech references are distinguished from exact meme recordings.

Reviewed installed pre-spring identities:

| Asset | SHA-256 |
|---|---|
| mambo dry | `bf2e0d9578f40be246532a72172c23e1e5ce4e675446122440fff7ce904050c7` |
| mambo wet | `42f3fba3b12d22a4019661206f6c04f3b8b51206b6637fa46d6bb5951fb5cae7` |
| hachimi dry | `be12334e7e519347fda2965dd39dd6e87105f2ae7f0b9e60d991cb53ee5710b2` |
| hachimi wet | `521f8f33c9b8e17f473dbe56982b9537d261686cbf5ed055e9f6c90027604d1d` |

During review, the implementer began the separate spring-metadata integration and updated numeric validation. Therefore the live numeric report and reproduction report temporarily refer to different generations; they must be refreshed to a coherent final generation before final package acceptance. The source/setup approval above does not turn pre-spring Windows captures into post-spring runtime evidence.

## Final metadata integration follow-up

**APPROVED — final asset/profile/manifest/provenance coherence.** A bounded follow-up passed 27 checks after the spring integration froze. All four actual VRM hashes and sizes agree with `character-assets.json`, embedded profile provenance, standalone provenance, the current numeric validation, and isolated bit-identical reproduction outputs. Numeric validation profile hashes match current profiles; reproduction identifies the current converter source; each asset provenance records the current spring authoring utility hash. The temporary generation mismatch noted above is resolved.

| Final asset | SHA-256 |
|---|---|
| mambo dry | `01f0e5b3165fc5d525f7e5bb73512bce0d8ea63a9b8fae31926655aba99017cd` |
| mambo wet | `56d042e9d1c60b8b9a6bec36c7192c29473cb66c335e2a806a4c82b123e36104` |
| hachimi dry | `b9bd8e8693e12e17f91856f156f82a0e68bae6b647f94587809134dc66d870d1` |
| hachimi wet | `4432961c18fcc247f02c52596ba1ca490bdf77130d911c3475031e08df65b3a9` |

Both profiles declare `playful_strut` and `mambo_goofy_walk` in `package.motion_ids`; these were not inserted into `idle_actions`. This follow-up verifies integration identities and evidence consistency; it does not assess spring behavior, gait quality, or final Windows captures, which have separate owners.
