# GPU result — audio input → Omni text → supplied character TTS

Run date: 2026-09-06 KST. RTX 4090, BF16/SDPA. **The requested pipeline executed successfully.** Five synthetic Korean inputs plus one repeated input produced Japanese dialogue and PCM through the existing UmaDiffusion GPT-SoVITS server. No Omni audio generator was loaded; no ASR transcript was supplied to Omni.

This is an offline waveform test, not a physical microphone/full-duplex test. The main UI still uses its existing Whisper/text-Qwen path.

## Observed responses and latency

First PCM is measured after submitting the already recorded waveform to the offline pipeline. It excludes recording, model loading and client playback buffering.

| Korean input meaning | Omni response observation | First PCM |
|---|---|---:|
| Greeting; asks about the day | Greets trainer and describes feeling calm | 1.720 s (Omni-cold) |
| Wants warm tea, not coffee | Offers warm tea: `温かいお茶を淹れましょうか？` | 0.949 s |
| Happy about passing an exam | Congratulates and explicitly mentions passing the exam | 0.712 s |
| Sad about failing an exam | Comforts/rest suggestion; does not explicitly repeat the exam fact | 0.528 s |
| Asks for slow right-hand wave | Says it will wave; selects `wave` | 0.848 s |
| Repeat greeting | Same text as first run | 0.702 s (warm) |

All six runs returned valid dialogue JSON and nonempty PCM, with no recorded pipeline/voice error. All delivered the first PCM before the model finished generating its complete response. Five warm calls: range **0.528–0.949 s**, median **0.712 s**. This is a small scoped observation, not a latency distribution or general comprehension benchmark.

The gesture schema only carries a name; selecting wave does not establish execution of the requested right-hand/speed parameters. Negative-emotion response was broadly appropriate but not explicit evidence that every detail of the failed-exam utterance was understood. No human voice-similarity score was obtained.

## Comparison with existing pipeline

The same synthetic inputs went through Whisper small → Qwen2.5-1.5B GGUF → the same character TTS. First PCM from upload was 1.232, 0.722, 0.947, 0.534 and 0.666 s respectively. Whisper preserved the intended content of all five fixtures.

For matched non-first cases p01–p04, Omni's median was **0.780 s**, the existing pipeline's **0.694 s**. Thus this test does **not** establish a speed improvement from replacing STT with Omni. Omni gave a more explicit congratulation on the passed-exam example, but the test is too small for a general model-quality ranking. Architecture, model size, decoding, context wrapping and prefix-cache behavior differ between paths.

## GPU and model configuration

- Qwen2.5-Omni-3B upstream revision `f75b40e3da2003cdd6e1829b1f420ca70797c34e`.
- Loaded `Qwen2_5OmniThinkerForConditionalGeneration` only. `talker_present=false`, `token2wav_present=false`.
- All loaded parameters on `cuda:0`; 4,703,464,448 parameters including audio and unused vision components. The 3B name is not the total loaded system parameter count.
- Checkpoint loading: 7.70 s, excluded from per-request latency.
- Omni-process peak CUDA tensor allocation: **9.502–9.523 GiB**; allocator-reserved peak reached **10.330 GiB**. These figures exclude separate TTS/STT processes and desktop/VRM rendering.
- Warm audio preprocessing: about 8.7–10.1 ms in these runs. Input padding was shortened without changing valid mel features on the separate p01 equivalence check.
- No image input, CPU parameter offload, quantization or fine-tuning was used.

## Character voice provenance and output check

The existing supervised TTS worker's configuration points to these unchanged local files:

- `uma-AIO-GPT-v2-e100.ckpt`: SHA256 `847f88e3d8bea9dc37fc686a02499e7402d9af6cceb6e6eda6bdbb3b16582716`
- `uma-AIO-SoViTS-v2_e20_s8300.pth`: SHA256 `417d80e4fedb5bd4d9f45d985dc889d4fa738a8644177dea310f894e3c973a06`

The existing `reference.wav` and prompt were retained. These hashes identify the configured on-disk checkpoints; no Omni speaker was used. The separate MMS model generated only Korean INPUT fixtures.

An ASR roundtrip of the exam-congratulation output preserved the words of the generated Japanese response. Tea and comfort outputs also preserved the intended wording apart from orthographic/punctuation differences. Greeting and waving outputs had ASR substitutions around some words, including the trainer address; without human listening, this cannot distinguish ASR error from synthesis error. Do not report flawless pronunciation or verified voice identity.

Example local output (exam passed): `companion/output/033c02c81fa445d98463ada753c2e9ce.wav`.

## Evidence and use

Full machine-readable results: `companion/logs/omni/results.json`; baseline: `baseline.json`; fixture identities and independent input ASR: `input-controls.json`; initialization/runtime log: `run.log`; frontend check: `frontend-check.json`. Inputs and audio outputs are ignored by Git.

Use `infer_wav.py` with an actual Korean recording to test this same pipeline; see the adjacent README. The experiment process exits after testing and frees its model allocation. This work does not switch the existing UI or claim native Windows microphone validation.
