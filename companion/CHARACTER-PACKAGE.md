# Single-file character packages

A `.matecharacter` file is a versioned ZIP containing the character's avatar, voice reference, Japanese transcript, personality/context/examples, speech style, behavior tuning and selected animations. Import registers an ordinary engine profile; the native client and dialogue/TTS/motion services use their existing generic loaders after a backend restart.

```bash
# From companion/. Character-specific assets and selected motions are included.
python3 -m engine.character_package export cheval-grand output/cheval-grand.matecharacter
python3 -m engine.character_package inspect output/cheval-grand.matecharacter

# On another configured Mate companion installation:
python3 -m engine.character_package import /path/to/cheval-grand.matecharacter
# Existing IDs are protected. --replace explicitly updates that ID.

# Optional: carry the existing shared UMA GPT + SoVITS weights too (~230 MB before ZIP).
python3 -m engine.character_package export cheval-grand output/cheval-grand-with-tts.matecharacter --include-tts-weights
```

The small package is portable character data, **not an entire GPU application**. It declares the external Mate runtime, compatible dialogue/audio-input provider, GPT-SoVITS v2 runtime, the two exact UMA model hashes, HuBERT and BERT dependencies. `inspect` prints machine-readable JSON with dependency checks; it does not claim model services are healthy. `--include-tts-weights` includes the two currently supported shared weights and installs them only when absent. Differing installed weights are never overwritten. Arbitrary package-supplied model weights, scripts and plugins cannot activate.

By default import requires the declared shared TTS weights. `--allow-missing-runtime` explicitly permits an offline/staging import; its result lists what remains missing. The backend must be restarted to refresh its character catalog. CLI export/import currently require the default companion layout; active `MATE_CHARACTERS_DIR`, `MATE_USER_DATA` or `MATE_MOTION_BANK` overrides are rejected with an actionable error. `--root /path/to/companion` permits a separate staging installation. No chat history, environment file, login information, caches or user workspace is exported.

## Character contract

| Profile data | Runtime meaning |
| --- | --- |
| `canonical_facts`, `roleplay_guidance`, `examples`, `user_role` | Persona, context and authored conversational examples |
| `package.speaking_patterns`, `package.voice_patterns` | Short textual speech/delivery guidance appended to the LLM system prompt |
| `assets.reference_audio`, `assets.reference_text` | Actual dedicated GPT-SoVITS voice conditioning; mono PCM16 WAV, 3–10 seconds |
| `assets.vrm` | Default self-contained VRM 0/1 GLB; external buffer/image URLs are rejected |
| `avatar_variants` | Optional outfits/appearances for the same character; each includes `id`, `label`, `vrm`, optional `description`/`mood_tags` |
| `motion_style`, `behavior_style` | Existing amplitude/tempo, idle timing, gaze/curiosity/posture controls |
| `ambient_loop`, `idle_actions`, `package.motion_ids` | Required installed motion IDs, bundled with capabilities and checksums |
| `job_ack`, `job_done`, `job_failed` | Short character-specific task-status utterances |
| Other `package` JSON fields | Preserved descriptive/namespaced metadata; no executable behavior |

`voice_patterns` describes how to phrase/deliver a line; it **does not add an acoustic pitch/speed API**. Actual voice identity comes from the bundled reference and the declared dedicated TTS model. Future voice engines/voice variants require an explicit supported runtime contract rather than silently interpreting arbitrary fields.

Example optional profile block:

```json
"package": {
  "speaking_patterns": ["短い日本語で、明るく返す。"],
  "voice_patterns": ["はしゃぐ時も同じ口癖を毎回繰り返さない。"],
  "motion_ids": ["playful_shrug"],
  "author": "local character author",
  "license_note": "Check each source asset before redistribution."
}
```

The exporter includes the profile's ambient/idle clips, extra `motion_ids`, and installed `uma_walk` when available. Imported procedural motion data is validated by the existing motion bank. VRMA assets are validated and published through the usual `/motion-assets` catalog. Authored gait metadata (`locomotion_style`: multiple contact intervals, stride, source hip-height policy and bounds) and `seated_transition` are preserved exactly and validated by the shared engine contract. Existing motion names with different clips/capabilities are rejected; shared identical motions can be reused. This avoids silently changing another character's animation.

## Avatar and costume variants

Variant support is additive within version 1. Existing packages remain valid; older importers must update before accepting variant payloads. The existing `assets.vrm` is always the default appearance; the ID `default` is reserved. Up to 16 optional variants can be declared:

```json
"avatar_variants": [
  {"id": "wet", "label": "비 맞은 모습", "vrm": "assets/hachimi-wet.vrm",
   "description": "Optional appearance", "mood_tags": ["playful"]}
]
```

The exporter includes **every declared variant VRM** and its SHA-256/provenance; missing files fail export. Import validates each GLB and restores the relative paths. `Profile.vrm_path("wet")` selects the alternate asset and returns `None` for unknown IDs. Catalog entries expose default/alternate URLs, availability, labels and mood tags; the alternate route is `/characters/{id}/avatar?variant=wet`.

This changes appearance under the same character ID, persona and voice reference. Voice/model/motion overrides inside a variant are unsupported and explicitly rejected. Descriptions/mood tags help the LM choose an appearance. The same portable package advertises a **declarative ability** with ID `change_appearance`, a JSON intent schema, allowed variant IDs and their mood tags. This descriptor is generated from `avatar_variants`; authors do not maintain a second list of allowed IDs. The importer rejects a supplied descriptor that disagrees with the validated variants. Older v1 files without the descriptor still work: inspection derives it.

The generic LM action is:

```json
{"text":"少し、気分を変えてみますね。","emotion":"happy","gesture":"idle",
 "intent":{"kind":"change_appearance","variant_id":"wet"}}
```

`inspect` exposes `abilities`, and the live character catalog exposes the same ability restricted to assets present on that installation. Backend validation additionally requires native-client support and a listed `variant_id`; the LM supplies no filename, shader code or executable script. Native execution reloads the same character's selected avatar and releases body contacts safely. Selecting `variant_id: "default"` returns to the base appearance. This is an agent-callable action, not a requirement for the user to open a selector. Package tests establish asset/profile compatibility; live UI/contact-reset tests belong to the native integration.

## Format and installation

[Manifest schema](schemas/matecharacter-v1.schema.json), enforced by the bounded importer:

```text
manifest.json                 format=mate.character, version=1, hashes, provenance, requirements, derived abilities
profile.json                  engine profile; package-relative avatar/audio paths
motions.json                  validated VRMA/procedural motion definitions
payload/avatar.vrm
payload/reference.wav
payload/variants/<id>.vrm      optional same-character appearances
payload/motions/<id>.vrma
runtime/<supported-weight>    optional pinned UMA weights
```

Import validates the complete inventory and SHA-256 values before staging. It rejects traversal/absolute/Windows-special paths, case collisions, symlinks, special/encrypted files, unlisted executable payloads and unsupported versions. Limits are 512 entries, 2 GiB per entry, 8 GiB expanded total, 1000× compression ratio and 2 MiB profile/manifest/motion JSON. Media validation additionally checks GLB framing/extensions/self-containment and full WAV frame data. SHA-256 detects corruption; it is **not a publisher signature**.

Assets are staged on the destination filesystem and moved into immutable content-addressed directories. The character JSON is atomically replaced **last**, which is the registration point. Imports are serialized by `.matecharacter-import.lock`. A failed import never activates a partial profile; inert staged asset directories can remain after a process crash. An interrupted process can leave the lock; remove it only after verifying no importer is running. Existing immutable assets are verified before reuse. Import changes no existing character unless `--replace` is supplied.

Current Uma avatar/reference/motion sources are local-user assets with unverified redistribution permission. Generated archives stay in ignored `output/`; they are not uploaded to GitHub. Provenance is carried in the manifest, but packaging does not grant redistribution rights. The format supports sharing when the included assets' permissions allow it.

Validation: [package test and real-asset roundtrip record](diagnostics/character_package/README.md).
