# Final package voice/intent review

**The cursor-aware run passed 12/12 checks:** a real Korean request produced Japanese acknowledgement, streamed dedicated voice, matching action/done intent for `support:right`, no movement during speech, and exactly one native arrival. Cheval Grand's actual cached model identity is recorded. The OS window moved 1,244 pixels right, from (634,672) to (1878,672); arrival was observed 28,272 ms after submission.

All three attempts used package SHA-256 `80303c7e703a5dbd526d343a2ac1ddd64af4b05ea8cbedd44094eb7c6bda170f` and NVIDIA RTX 4090. The external probe changed; the packaged runtime did not.

| Attempt | Checks passed | First PCM received by native | Outcome |
| --- | --- | --- | --- |
| Original leftward | 10/12 | 1,156 ms | Interrupted before arrival |
| Instrumented same placement | 10/12 | 1,371 ms | Pointer hover interrupted travel |
| Cursor-aware rightward | 12/12 | 920 ms | Exactly one arrival |

The diagnostic repeat identifies the interruption directly: `pointer_interaction` becomes true at the navigation-finished event while support remains attached, world geometry is available, and speech, foreground work, panel and dragging are inactive. This is the existing intentional hover-pause policy, not a navigation deadline failure. The original run stopped at the same location and is consistent with that explanation, but lacked pointer context and does not independently prove it.

The final probe chooses a route away from the cursor's monitor half: left-half cursor means a .45-width starting foot position and the real `support:right` target. It changes the Korean direction request and directional displacement assertion consistently. It neither warps the pointer nor disables hover cancellation; the >120-pixel movement requirement and 45-second arrival bound remain. This is an explicit fixture correction, not a retroactive pass for the preceding two failures.

For the successful run, server first text was 304.8 ms, first audio 858.5 ms and total generation 1,773.7 ms; native first PCM reception was 920 ms. All three attempts had zero measured speech-time drift and passed the no-dropped-frames assertion. These are three individual text-to-voice observations under actual rendering, not a latency distribution, microphone-input benchmark, or measured acoustic onset. The final acknowledgement describes intended movement, not falsely completed movement.

Adjacent `voice.json` preserves all three attempts, raw-record hashes, package identity, timing and outcomes without PCM or raw desktop contexts. The total is 32/36 passing assertions across attempts; final acceptance is specifically the last 12/12 run. Raw logs remain under `logs/windows-intent-shared-floor-{final,diagnostic,corridor}`.
