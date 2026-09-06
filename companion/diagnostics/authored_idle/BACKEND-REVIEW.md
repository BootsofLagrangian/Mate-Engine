# Independent ambient catalog review

Verdict: **APPROVED**. Reviewer: Astra backend; implementation under review authored by root. Scope is the new ambient profile/catalog fields, manifest metadata and three profile defaults—not the reviewer's separate extraction helper or native motion implementation.

Reviewed `engine/profiles.py`, `engine/motion_assets.py`, `engine/tests/test_ambient_profiles.py`, changed motion-asset tests, and the Cheval/Rice/Eishin profile JSON files.

- `ambient_loop` accepts an empty default or a validated motion ID. `idle_actions` accepts at most eight validated IDs, rejects malformed types/path-like values, and deduplicates while preserving order. These are generic catalog values; no character-specific backend branches or idle model calls were introduced.
- The optional manifest `ambient` field accepts only a Boolean and survives catalog publication. Existing file containment, VRMA/header validation and checksum checks still govern whether assets are advertised or served.
- The three profiles select `uma_home_idle` and their respective `uma_*_idle_action`. An independent read-only check against the currently installed `MotionAssets` catalog verified all references: the shared loop has `ambient=true, loop=true`, and all three idle actions are installed with `loop=false`.

Independent full-suite execution:

```sh
/home/hard2251/workspace/mate-engine/.venv-omni/bin/python -m pytest companion/engine/tests -q
```

Result: **122 passed in 13.11 seconds**. The 113 warnings are existing FastAPI/AnyIO deprecations. Coverage includes the nine ambient-profile cases and two additional ambient metadata cases, plus the existing backend regressions.

No blocking findings and no runtime corrections required. Profile references are syntax-validated rather than requiring installed assets at profile-load time, allowing optional/local assets to be installed later. Actual availability is checked by the asset catalog/native consumer. The installed-reference check is a snapshot of this local installation, not a guarantee that raw assets exist in a fresh checkout. Native blending, idle timing, retargeting fidelity and visual quality require their separate motion/integration validation.

## Subsequent contact metadata implementation

After the approved ambient review above, root requested a separate change implemented by Astra backend: optional motion manifest `contact_mode` accepts only `""` or `"foot"` and is preserved in the published catalog. Invalid values exclude that entry; an omitted field stays omitted. This is generic motion metadata for the native preview/contact consumer, with no character-specific branches or backend geometry handling.

Added nine regression cases: both allowed values and seven unsupported/type-invalid values. The full backend suite now passes **131 tests in 11.21 seconds**, with existing deprecation warnings only. Native parser/pass-through and actual hip/IK behavior are owned and validated separately.

The earlier **APPROVED** verdict applies to root's ambient changes, not to this reviewer-authored follow-up. Independent root review of the `contact_mode` implementation is pending at this record's update.

Root independent follow-up: **APPROVED** for the reviewer-authored contact metadata
change. Inspected the manifest filter, emitted HTTP catalogue, and parameterized
accepted/invalid cases. Tuple membership rejects non-string JSON values without
hashing containers; missing metadata preserves existing clips. Native parser uses
the same empty/foot enum and host forwards it to the motion owner. The 131-test
run includes these nine cases. This is metadata validation, not foot-IK quality.
