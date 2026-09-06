# Character package validation

The v1 `.matecharacter` implementation is documented in [CHARACTER-PACKAGE.md](../../CHARACTER-PACKAGE.md). [roundtrip.json](roundtrip.json) records the real Cheval export/import and engine loader result.

- 47 focused tests passed: actual exporter/importer, profile+voice+VRMA resolution, procedural motion re-export in a fresh root, explicit replacement, missing runtime refusal, corrupt immutable assets, same-name motion conflicts, traversal/Windows names, symlinks, case collisions, hashes, missing assets, versions, decompression bounds, untrusted model requirements, truncated PCM and actual TTS 10-second reference limit, invalid/external VRM/VRMA media, custom-layout rejection, history/secrets exclusion, full alternate-avatar import/re-export, unknown/default IDs, missing variants and unsupported voice/motion overrides, derived LM appearance abilities, ability tamper/backward compatibility, and exact authored-gait metadata roundtrip/collision checks.
- 98 existing profile/history, ambient profile, motion asset, procedural motion and dialogue tests passed. These use existing test providers; they do not synthesize GPU speech.
- [Five-character sample inventory](sample-packages.json) records exact archive hashes and sizes for Cheval, Rice, Eishin, Mambo and Hachimi. All five imported into the same isolated root with avatar/reference availability true and per-profile motion resolution.
- Actual Cheval VRM and WAV bytes survived roundtrip unchanged; persona and selected `uma_home_idle`, `uma_cheval_idle_action`, `uma_walk` are resolved through the ordinary engine loaders.
- Final audit passed with stable profile and motion-manifest hashes, exact full imported motion metadata, and equal package/live LM appearance abilities. Both meme archives contain `playful_strut` and `mambo_goofy_walk` with their authored contact/stride/hip policies.
- Mambo/Hachimi packages include actual dry default mini avatars and optional original wet appearances. Both default and wet VRM hashes survive import unchanged; character identity, reference audio, and textual voice patterns remain intact. All variant files have inventory/provenance records.
- Both a small character-only archive and an optional archive carrying the exact supported shared GPT/SoVITS weights were exported locally. The latter imported into an isolated companion root without `--allow-missing-runtime`; both exact model hashes are present. Reimport with explicit `--replace` succeeds and verifies immutable assets.
- Independent review: [INDEPENDENT-REVIEW.md](INDEPENDENT-REVIEW.md).

The local artifacts are `companion/output/{cheval-grand,rice-shower,eishin-flash,mambo,hachimi}.matecharacter` and `companion/output/cheval-grand-with-tts.matecharacter` (ignored). Installed roundtrip data is `/tmp/mate-character-final-20260907`. This diagnostic verifies packaging and loader compatibility, not a fresh full native/GPU session; external dialogue/TTS runtime libraries and HuBERT/BERT remain declared prerequisites. No archive was published to GitHub, and no redistribution license is inferred for user-local Uma assets.

```bash
/home/hard2251/workspace/mate-engine/.venv-omni/bin/python -m pytest diagnostics/character_package/test_package.py -q
/home/hard2251/workspace/mate-engine/.venv-omni/bin/python -m pytest engine/tests/test_profiles_and_history.py engine/tests/test_ambient_profiles.py engine/tests/test_motion_assets.py engine/tests/test_motions.py engine/tests/test_dialogue.py -q
python3 -m engine.character_package inspect output/cheval-grand.matecharacter
# After character/motion asset freeze; requires a fresh target directory:
python3 diagnostics/character_package/roundtrip_real.py --install-root /tmp/mate-character-final-audit
```

Development review found and fixed: trusting an existing immutable directory, silent same-name motion shadowing, missing procedural re-export without a built-in bank, accepting header-only GLB/truncated PCM, external VRMA resources, and silently importing into an inactive custom character directory. Rejection cases are retained in the test suite.

Shared motion names remain protected even under `--replace`: a changed clip needs a new motion ID, so another installed character cannot silently switch animation.

The final archives use the reviewed production authored spring metadata. Experimental runtime garment/hand-proxy tuning is not included; packaging makes no claim of full cloth simulation or guaranteed absence of intersections.
