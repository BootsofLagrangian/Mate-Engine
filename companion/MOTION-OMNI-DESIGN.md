# Motion protocol and Omni feasibility — 2026-09-06

Follow-up: the audio-input-only GPU trial has since been executed; see [experiment results](experiments/omni/RESULTS.md). The notes below describe the original investigation.

Original status: source/documentation investigation and proposed interface only. No Omni checkpoint was installed or benchmarked in this investigation; existing services remain unchanged. The JSON below is NOT accepted by the current application.

## Current implementation

`app.py` constrains the LLM to text, emotion and one of eight gesture names. `stream_pipeline.py` emits one action event. Both clients sample shared additive Euler tracks from `Assets/StreamingAssets/cheval-motions.json`. Thus the model currently selects an authored motion; it does not synthesize novel trajectories. Audio is generated separately by GPT-SoVITS.

## Proposed companion performance protocol v2

Let the model plan low-frequency actions and let the engine interpolate every frame. Three levels can coexist:

1. Named clips with intensity, speed, side and repeat parameters.
2. Procedural look-at, lean, head tilt and hand reach, blended with clips. Hand targets need IK; feet/root constraints are required before attempting full-body locomotion.
3. Bounded sparse pose keyframes for genuinely new gestures, compiled into the existing track format. Validate allowed bones, finite values, anatomical ranges, time order, angular velocity, blend-in/out and return-to-idle. This does not solve self-collision or guarantee human-quality motion; those require additional motion/IK constraints or a dedicated motion generator.

Example proposed event:

```json
{
  "version": 2,
  "turn_id": "turn-42",
  "type": "performance",
  "anchor": {"phrase": 0, "offset_ms": 0},
  "actions": [
    {"kind": "clip", "name": "wave", "side": "right", "intensity": 0.45, "speed": 0.8, "duration_ms": 2400},
    {"kind": "look", "target": "trainer", "weight": 0.8, "duration_ms": 2600},
    {"kind": "expression", "name": "happy", "weight": 0.35, "duration_ms": 2600}
  ]
}
```

Protocol requirements:

- Separate text/audio and action channels so motion JSON is never spoken.
- Anchor to the client's actual scheduled PCM phrase playback, not server request time. Include phrase IDs/sample offsets in audio events.
- Send a complete small action event early, without waiting for a long pose plan before speech. Keep planning budget small for the 1.5B model.
- Define body masks/layer priority, additive-vs-override semantics and conflict arbitration. A head nod and gaze compete for the same bones.
- Use a canonical humanoid coordinate convention plus VRM/Unity adapters; current web axis conversion demonstrates why raw Euler values cannot be blindly shared.
- Turn cancellation invalidates queued actions/audio and blends to idle. Unsupported commands fall back to a known pose, with observable validation errors.
- Validate protocol parsing and sampled bounds separately from visual/native Animator execution. Native Unity tests still require Windows Unity Editor.

## Omni findings

Official primary references, retrieved 2026-09-06:

- Qwen2.5-Omni repository: https://github.com/QwenLM/Qwen2.5-Omni
- Qwen2.5-Omni-3B model card: https://huggingface.co/Qwen/Qwen2.5-Omni-3B
- Qwen3-Omni repository: https://github.com/QwenLM/Qwen3-Omni

Omni models can consume audio features directly, removing the mandatory separate STT transcript stage. They do not capture OS microphone devices by themselves. A desktop capture layer, resampling/chunk transport, voice activity/end-of-turn detection, echo suppression, cancellation and barge-in handling remain application responsibilities. Streaming speech output does not by itself establish full-duplex listening while speaking for the selected runtime.

Qwen2.5-Omni offers 3B/7B variants. Its official 3B card exposes Chelsie/Ethan speaker choices, not a drop-in GPT-SoVITS voice checkpoint interface. It also warns that audio output expects a particular Qwen system prompt. Native character voice and Japanese audio quality therefore require separate evaluation. Its official memory table reports 18.38 GB BF16 for 15-second VIDEO input with FlashAttention2, and warns practical usage can be higher. This is not a measured audio-only requirement. Model names do not include all auxiliary module memory. `disable_talker()` saves roughly 2 GB per upstream documentation.

Qwen3-Omni-30B-A3B supports Korean/Japanese speech input and Japanese speech output per its official language list. A3B denotes active MoE parameters, not storage for only a 3B model. Standard BF16 weights exceed the RTX4090's 24 GB capacity; quantization/offload needs a separate feasibility/latency trial. The official 78.85 GB figure is for a 15-second VIDEO BF16 scenario, not this short audio-only workload. Thinker/Talker support varies by runtime; the retrieved official README says vLLM serve supports only Thinker. Do not assume every API server exposes the full streaming speech path.

## Suggested experiment order

First implement the model-independent performance protocol on the existing verified stack. Independently trial Qwen2.5-Omni-3B audio-input/text-output (Talker disabled) with the existing character TTS; keep environments separate. Compare actual Korean intent comprehension, speaker-role consistency, GPU peak memory and end-of-utterance to first audible response with the current Whisper+Qwen baseline. This is a candidate, not an established improvement.

Only replace character TTS if a native-audio candidate also preserves Japanese pronunciation and desired voice identity. Qwen3-Omni full BF16 is not the straightforward single-4090 option. Avoid replacing the running stack until audio-input quality and streaming behavior have actually been measured.
