# Independent character package review

Status: APPROVED after revisions for the archive/import/export and Python loader scope below.

Scope: `.matecharacter` archive validation, staged installation and profile activation, installed asset loaders, and re-export. This review does not validate rendered avatar quality or live GPU voice output.

The review examined path traversal and Windows filename collisions, symlink/special/encrypted entries, exact inventory and hashes, decompression budgets, executable payload exclusion, pinned shared TTS model checks, and profile-last activation. No additional defect was found in those inspected gates.

Initial independent reproductions found the following concrete defects, reported to the implementation owner:

- Re-import with `replace=True` registered a previously installed avatar after its bytes were replaced with `b'corrupt'`. The hash-addressed directory was trusted without validating reused content.
- A host `uma_walk` with different bytes, duration and locomotion capabilities silently won global name resolution over the imported character's declared walk.
- Re-export from a fresh root with no built-in procedural bank lost an installed package's `wiggle` procedural motion.
- A 12-byte GLB header with no JSON/VRM content was accepted as a registered avatar.
- A WAV truncated to its 44-byte header was accepted because declared frame count was checked without consuming the samples.

All five reproduced defects were corrected and regression tested. Reused immutable assets are verified before publication; conflicting globally named motion bytes/capabilities are rejected; installed procedural motions survive fresh-root re-export; complete GLB framing and VRM/animation extension checks run before activation; PCM samples are consumed with bounded sample-rate/duration and exact declared-byte checks. Both VRM and VRMA reject external buffer/image references. Nondefault configured runtime directories are rejected explicitly.

Independent final verification:

- `python -m pytest -q diagnostics/character_package/test_package.py`: **47 passed** after the additive avatar-variant, appearance-ability and gait-metadata revisions (see below).
- `python -m pytest -q engine/tests/test_motion_assets.py engine/tests/test_motions.py engine/tests/test_profiles_and_history.py`: **75 passed**; existing FastAPI/AnyIO deprecation warnings only.
- Original independent malformed-media reproduction now rejects both header-only GLB and truncated WAV.
- `git diff --check` across the scoped implementation and diagnostics: clean.

The archive remains declarative data. TTS/runtime availability is reported separately; these tests do not establish GPU readiness, visual rig quality, full glTF semantic validity, or redistribution rights. Import activates through a final atomic profile replace after validating assets; failed imports can leave unreferenced immutable asset bytes, but do not publish a new character profile.

The final follow-up also handles malformed GLB `asset` values with a clean rejection and validates profile/manifest extension consistency. The contract documentation and manifest schema were reviewed for the stated scope; no new blocker was found. The package suite passed again after this revision. A subsequent final compatibility correction restricts reference audio to 3–10 seconds: independently verified against the installed GPT-SoVITS `_set_prompt_semantic` check (48,000–160,000 samples at 16 kHz). The added 11-second rejection case passed with the complete final **33-case** package suite. Approval remains unchanged.

## Additive avatar-variant review

Status: **APPROVED** for profile and package semantics. Backend HTTP selection and native avatar reload/contact cleanup are outside this review.

Reviewed the optional bounded variant list, unique/reserved IDs, contained VRM paths, labels/descriptions/tags, and explicit exclusion of variant voice/model/motion overrides. Default and unknown-ID behavior preserves the existing default avatar and returns no asset for unknown variants. Export includes every declared alternate in the exact inventory; import applies the same media and containment checks to every alternate before atomic profile activation; re-export preserves alternate bytes while character identity and voice remain shared.

Independent verification: **48 tests passed** in `diagnostics/character_package/test_package.py` plus `engine/tests/test_profiles_and_history.py` (**41 package + 7 profile/history**). An additional independent adversarial check replaced a variant with a rehashed VRM containing an external image URI; import rejected it before creating the character profile. Scoped `git diff --check` remained clean. No blocker found.

## Portable appearance-ability review

Status: **APPROVED** for the derived package/profile ability descriptor. LM prompt construction, intent routing, client support negotiation and native execution are outside this file-level review.

The `change_appearance` descriptor derives its closed intent schema and variant enum from validated profile data. The portable manifest includes all declared variants, while the live catalog filters unavailable assets. A supplied descriptor cannot widen the enum or alter execution because import requires equality with the derived descriptor. Older v1 archives may omit it and receive the same derived representation. The descriptor carries labels and mood tags without exposing paths or enabling arbitrary executable behavior; default appearance remains an explicit allowed ID when available.

Independent final suite: **51 passed** across `diagnostics/character_package/test_package.py` and `engine/tests/test_profiles_and_history.py` (**44 package + 7 profile/history**). Covered portable roundtrip and live catalog equivalence, filtering after an alternate disappears, descriptor tamper rejection and older-v1 omission. Source, schema and contract documentation reviewed; no blocker found.

## Gait metadata portability review

Status: **APPROVED** for the narrow package integration. Native gait solving and the shared locomotion validator's algorithmic correctness remain the motion team's review scope.

The package importer now calls the existing `valid_locomotion_style` contract, disallows nonempty gait style on a non-locomotion clip, and checks the seated-transition tag against the supported enum. Name-collision checks include both gait metadata and seated-transition semantics, so a matching binary cannot silently replace a different contact/stride policy. Export and re-export preserve catalog metadata rather than reconstructing or dropping the new fields.

Independent final package suite: **47 passed**. The three additional cases establish exact multiple-contact/hip-policy/seated-tag roundtrip and re-export, rejection of rehashed invalid gait metadata, and rejection of same-binary/different-style shadowing. Documentation matches the preserved fields; scoped diff check is clean. No blocker found.

Reviewed file hashes (SHA-256):

- `engine/character_package.py`: `633587e9f8f305e0689973dc16b3a485dec55a748ed805b85d68686d93dd46b9`
- `engine/package_assets.py`: `184a74d0eae89def824171cc60fb6e47e85faf9d19151f366c9738795f11ed6c`
- `engine/profiles.py`: `bcb8b49590a3ced4b9a7c961a39e3817cb16f3700e3e12ce34a7ce32f12f7f2d`
- `engine/motion_assets.py`: `e2cbdb65ed5edc0582c42e64f1df227796669b003a359699e31e83fb410606ba`
- `engine/motions.py`: `2c2ab15d63ad0c93a491a144b738284b3e5583f32b23992a6ea10c2e76f5bbd8`
- `diagnostics/character_package/test_package.py`: `7226ea2cb920b3ce5b54ab722b78b051df3d63956bdbf3aa006a1dbffdb478a7`
- `schemas/matecharacter-v1.schema.json`: `77b028398054a4522b2486264535c091544258ddeb611c6fd04eb4b360ee3760`
- `CHARACTER-PACKAGE.md`: `14dc93e8b1f8447749e7ea9dbb9cd2c47971c5ae737520fac52b9af476460f0a`
