# Mambo and Hachimi mini characters

Both selectable profiles use actual UMA mini/chibi game geometry assembled from the user's local `F:\ULTIMA\UMA-Extractor` collection. Mambo is the Matikanetannhauser mini (1062); Hachimi is the Tokai Teio mini (1003). They are not fumo plush models or a downloaded fan meme sculpt. Their playful persona, examples and motion preferences are authored for this companion.

The default avatars use the original **mini-specific dry** body and hair textures. These were found inside the `sourceresources/3d/chara/mini/.../materials/mtl_*` bundles, separate from the visible wet texture directories. Sweat was not painted out. The prior wet diffuse adaptation remains an optional `wet` avatar variant, with the same geometry and fixed mouth.

- [Mambo profile](../../characters/mambo.json), [source provenance](mambo-asset-provenance.json)
- [Hachimi profile](../../characters/hachimi.json), [source provenance](hachimi-asset-provenance.json)
- [Asset checks](asset-validation.json), [isolated reproduction](reproduction.json)
- [Windows mouth checks](windows-mouth-validation.json), [independent visual review](MOUTH-REVIEW.md)
- [Direct GPU voice generation](voice-validation.json)

The voice references are the original clean spoken samples linked by the [official Matikanetannhauser page](https://umamusume.jp/character/matikanetannhauser/) and [official Tokai Teio page](https://umamusume.jp/character/tokaiteio/). Audio is resampled to mono 32 kHz; only trailing silence is added when needed for the existing GPT-SoVITS v2 reference minimum. The shared trained Uma GPT-SoVITS weights stay unchanged. These are character voice references, not exact edited meme recordings.

## Mouth repair

The source mini face has a real mouth cutout. Simply making the atlas background transparent exposed that cavity. An initial pair of shrinking/expanding atlas planes also produced two lip contours at intermediate weights. Both rejected attempts are retained in ignored development render directories.

The final avatar has one visible mouth surface with five continuous shape targets and a static opaque skin cover behind it. The surface follows a fitted source face curve with 2 mm clearance, so partial vowel weights do not intersect the cover. Mouth artwork comes from the source AA atlas; the five vowel targets deform that artwork. Neutral is a thin closed line. This is a practical VRM face conversion, not a recreation of the game's full facial shader. Blink uses vertical squeezing on the source eye surface and preserves eye width.

Actual Windows RTX 4090 D3D12 Forward+ captures cover both avatars, front/45-degree views, neutral, blink and five vowels at 0.3/0.6/1.0: **76 images**. All ten front-view vowel sequences have strictly increasing pink aperture pixels. Independent review inspected neutral and partial/full vowel views and approved the repaired mouth. These are owned source-window static renders, not a live microphone lip-sync test.

Numeric checks cover the actual installed GLB buffers, finite vertices, five increasing mouth apertures, persistent cover, reference WAVs and identical dry/wet geometry: **284 checks passed**. A fresh conversion to an isolated temporary directory reproduced all four VRMs byte for byte. Existing profile/history and ambient profile tests passed **16 tests**. Motion integration evidence is maintained by [the motion task](../meme_motion/README.md); its earlier exact 250-check matrix used the retained wet files, whose geometry matches the dry defaults.

The two direct warm GPU TTS calls produced non-silent 32 kHz audio: Mambo 2.9 s in 1.48 s and Hachimi 3.9 s in 1.16 s. These are functional single-call measurements, not streaming first-audio latency or voice-similarity scores.

## Reproduce

From `companion/`, with `UnityPy`, NumPy, SciPy, Pillow, requests, gdown and ffmpeg available:

```bash
python diagnostics/meme_characters/extract_mini.py
python setup_characters.py
python diagnostics/meme_characters/validate_assets.py
```

The converter defaults to both characters and both texture variants. `--id mambo --variant dry` selects one. The local source root is explicit in the converter; source bundle hashes are recorded. All VRMs, source textures, voice audio and local `.matecharacter` archives remain ignored by Git. The profiles embed provenance so a local character archive carries its source identity alongside the assets. These copyrighted game/voice assets do not acquire a redistribution license by being packaged.

No original spring simulation is included in this initial conversion. A separate physics task is adding bounded spring groups; that work must update asset hashes and repeat the relevant runtime checks before claiming final spring behavior.
