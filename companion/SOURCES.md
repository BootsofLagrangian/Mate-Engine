# Runtime asset provenance

Downloaded 2026-09-05/06 KST for this local setup.

| Input | Source |
|---|---|
| Mate Engine checkout | https://github.com/shinyflvre/Mate-Engine (existing user checkout) |
| Voice weights | https://huggingface.co/UmaDiffusion/uma-voice-gpt-sovits-v2 |
| GPT-SoVITS implementation | https://github.com/RVC-Boss/GPT-SoVITS/tree/38cd8815781275a9b438d2c5812087c82f73a377 |
| Qwen GGUF | https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF |
| STT | https://huggingface.co/Systran/faster-whisper-small |
| HuBERT | https://huggingface.co/TencentGameMate/chinese-hubert-base |
| BERT | https://huggingface.co/hfl/chinese-roberta-wwm-ext-large |
| User's Drive folder | https://drive.google.com/drive/folders/1vul3PhJlk5-uTiaVZacvCYRXqVX4k-ry |
| Cheval folder | https://drive.google.com/drive/folders/1QUDF6RZiFDzyxsTsUFTcvzPt4we_tnfU |
| Selected VRM | `高尚骏逸.vrm`, file ID `1-TDrBrutb5UClm-aAIat5FWoZeRDc-ar` |
| Persona and reference audio | https://umamusume.jp/character/chevalgrand/ |

The downloaded VRM is 18,567,488 bytes, GLB v2 with VRM 0.x extension. Embedded metadata identifies author **Mercer**, title **cg**, `allowedUserName=OnlyAuthor`, `commercialUssageName=Disallow`, `licenseName=Redistribution_Prohibited`. Keep the downloaded asset local; no distribution permission is inferred from the public folder. The reference sample and model binaries are also excluded from Git. UmaDiffusion's model card labels the weights CC-BY-NC-SA-4.0 and describes personal/research use. Qwen is Apache-2.0.

The 5.2-second official voice sample says `僕はなる。勝って、偉大なウマ娘に。` The full sample was converted to mono 32 kHz WAV. Whisper initially wrote homophones `鳴る`/`馬娘`; the reference prompt uses corrected Japanese orthography. This is a reference-conditioned AIO voice model, not newly trained Cheval-specific weights. No identity/speaker-similarity score was measured.

Compatibility fixes are kept outside the vendor checkout: `tts_worker.py` supplies the missing v2 Japanese phoneme symbol table and bounds CPU threads. The original LangSegment PyPI 0.2.0 import is broken; a pinned source checkout at `ishine/LangSegment@0d767c3867d6f59aaa886088debc473777b74a28` is installed instead. Legacy checkpoint loading is enabled only in the TTS worker environment for the explicit pretrained files.

The UmaDiffusion SHA256 values are checked by setup.py. Additional local asset hashes are recorded in `asset-manifest.json`.

## Streaming implementation references

- Unity 6.2 DownloadHandlerScript callback/thread behavior: https://docs.unity3d.com/6000.2/Documentation/ScriptReference/Networking.DownloadHandlerScript.html
- PyTorch SDPA API/mask semantics: https://docs.pytorch.org/docs/stable/generated/torch.nn.functional.scaled_dot_product_attention.html
- Local `tts_optimization.py` records the expected pinned decoder SHA256 and applies a reversible attention patch. This patch is local project code; it is not an upstream release.
