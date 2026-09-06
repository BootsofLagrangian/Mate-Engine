# Locomotion catalogue review

2026-09-06, root independent review of backend-agent changes: **APPROVED**.

Reviewed `MotionAssets.entries` and `MotionBank.parse_asset_catalog` /
`validate_asset_entry`. Explicit `locomotion` and `locomotion_preserve_hips`
booleans default false; priority defaults zero and is bounded to integral 0..100.
Python rejects bool-as-int and noninteger JSON types. Godot accepts finite
integral numbers because its JSON decoder represents integer tokens as floats,
while rejecting booleans, fractions and nonfinite values. Existing catalogue
file/checksum validation and old clip behavior remain in effect.

Validation supplied by the implementer: full backend 157 tests passed; dedicated
native parser 28 checks passed. Registration, selected gait and rendered contact
are separate host/motion acceptance; these parser results do not establish them.
