# Validation record — 2026-09-06 KST

The browser + local inference service has been executed. Unity 6000.2.6f2 is not installed here: **native compilation, Play mode, transparent desktop window, built-in clip blending and Unity PCM playback have not been executed**. The Unity changes are independently source-reviewed, not runtime-approved.

## Hardware and models

WSL, RTX 4090 24 GB. `/usr/lib/wsl/lib/nvidia-smi` works although ordinary PATH lookup does not. Initially unrelated jobs occupied ~23.7 GB; they ended independently and were never stopped by this task. Final default is CUDA for LLM/TTS/STT.

- PyTorch 2.6.0+cu126: GPU matrix multiplication and attention comparisons executed.
- llama-cpp-python 0.3.19 CUDA 12.4: Qwen2.5-1.5B-Instruct Q4_K_M, all layers offloaded, flash attention enabled. This is 1.54B, not exactly 1.0B.
- UmaDiffusion GPT-SoVITS v2: CUDA FP16, pinned upstream `38cd8815781275a9b438d2c5812087c82f73a377`.
- faster-whisper small CUDA FP16: actual STT requests executed. ~5.9 GB total GPU use observed with all stages loaded, including background/desktop baseline.
- Drive VRM: GLB2/VRM0.x, 18,567,488 bytes. Download hashes and provenance are recorded separately.

## Streaming and optimization

There is no separate translation call. Character facts, authored examples and language/role instructions reside in SYSTEM. A user-turn wrapper identifies the human trainer; explicit motion requests also receive a short Japanese meaning hint. A constrained JSON text character range excludes ordinary Korean and Latin letters, but **script restriction is not a semantic language guarantee**.

LLM JSON is parsed incrementally; short clauses are committed before the final reply completes. Japanese morpheme boundaries allow splitting longer comma-free text without arbitrary mid-word cuts. LLM and TTS workers overlap. TTS produces an entire input fragment before yielding audio; 20ms PCM is transport framing, not phoneme-level acoustic streaming. No claim is made that TTS matches every LLM token's decoding speed.

The original parallel batch path took 0.65–1.09 s for the two tested Japanese phrases. The single-fragment path took about 0.54–0.62 s for 2.51–2.83 s of audio (real-time factor ~0.21–0.24 in warm samples). The tiny repeated set is a scoped engineering comparison, not a general benchmark. Logs: `tts-mode-bench.json`, `tts-sdpa-bench.json`.

`tts_optimization.py` patches the batch decoder's materialized attention to PyTorch SDPA before TorchScript import. Source hash checks, pristine backup and environment-controlled restoration guard the patch. Boolean blocked masks are inverted for SDPA, including fully masked rows. GPU random-input comparison: float32 max absolute error 1.91e-6; float16 9.77e-4. A fixed-seed batch-SDPA/naive audio pair had identical samples (correlation 1.0). This does not establish equivalence for every input. The deployed short-fragment path uses `parallel_infer=False`, which was faster than the patched batch path. Reference caches remain stable, and startup warms LLM/TTS before interaction.

Actual three-turn streaming samples are in `logs/stream-benchmark.json`, including first token/text/audio and model completion. Final measured warm first PCM arrivals were 0.408, 0.473 and 0.523 s; all three delivered audio before LLM completion. These observations do not exclude GPU contention or scheduling variability. Latest exact values are in that JSON.

A rebuilt Chromium browser run measured first scheduled playback at 0.795 s, with 274 PCM frames and **zero scheduled gaps**. The next buffers were already queued while the current utterance played. Gap measurement includes `scheduledStart - previousPlayhead`, not merely arrivals after buffer exhaustion. `check-pcm.mjs` separately verifies late-arrival accounting. Log: `browser-live.json`. This is one observed run, not a universal no-stutter guarantee; physical speakers were not listened to.

## Checks

- 15 Python tests: invalid replies, upload limits, motion consistency, session behavior, partial JSON, phrase commitment, controlled provider overlap and stopping at the first complete JSON object.
- Vite build passed; dependency checks previously passed (`uv pip check`, npm audit 0 vulnerabilities).
- Browser: actual VRM loaded, streamed PCM playing, lip-sync analyser connected, correct wave action, no JavaScript exceptions. Chromium uses SwiftShader in this WSL validation environment; model inference uses CUDA.
- Cancellation: delayed STT response does not revive speech; Stop during delayed `AudioContext.close()` releases controls; actual queued PCM stops. Delayed STT/close portions intentionally use controlled test timing. Log: `cancellation-validation.json`.
- Virtual browser microphone fed the official reference WAV through getUserMedia → browser WAV encoding → real Whisper → real Qwen → real streaming TTS. Exactly one chat request; Enter during recording submitted none. Physical microphone not tested.
- Eight shared motions (`idle`, `nod`, `shake_head`, `shy`, `wave`, `think`, `bow`, `stretch`) rendered with active offsets and return to zero. Wave/stretch/bow screenshots inspected. Web VRM0 rotation requires spring-bone reset; semantic forward bends require an adapter axis sign conversion. Web rendering capped at 30 FPS.
- Earlier audio roundtrip: generated 32kHz/5.22s audio, RMS .0685/peak .783; Whisper transcribed `トレーナーさん、お疲れ様です。僕も、ここにいますから。`. No human voice-identity evaluation performed.
- Supervisor SIGTERM closed both ports and the stack was restarted. Wait for old processes to exit before an immediate restart.
- Independent review approved current streaming cancellation/cleanup, attention patch and Unity source changes; native Unity runtime explicitly excluded.

## Observed quality limits

Eight authored Korean language probes (including requests for English/Chinese) produced Japanese with kana and no ordinary Hangul/Latin letters. The original greeting role inversion was fixed for its follow-up probe. This is a narrow test set, partly overlapping SYSTEM examples, not an unseen evaluation or proof of always-Japanese behavior.

The 1.5B model still sometimes uses 私 instead of 僕, thanks the trainer when asked to praise the trainer, or gives an off-topic answer. One multi-turn stretch request generated text about raising a flag while the action controller correctly selected stretch; a Japanese motion-meaning hint was subsequently added and the final multi-turn stretch retest returned the intended body-stretch reply. No fine-tuning was performed. Do not represent this implementation as a faithful or consistently accurate character model.

Whisper's reference transcription had homophone errors (`僕は鳴る勝手偉大な馬娘に`) and the resulting dialogue also drifted. The microphone test proves connection, not recognition accuracy. STT operates after recording ends; it is not live incremental recognition or automatic voice activity turn-taking.

Unity streaming now uses incremental UTF-8 NDJSON plus a bounded PCM ring and audio-thread callback. That implementation, raw-bone retargeting and built-in Animator composition need the actual Unity Editor to validate. No completed native build is included.

Evidence lives in ignored `logs/`; models, downloaded VRM, reference audio and generated speech are also excluded from Git. See `SOURCES.md` for usage metadata and origins.
