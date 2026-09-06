# Real-model furniture intent validation

Actual Omni3B WebSocket tests cover all three installed profiles. Native registry data was exported from `DesktopObjectsHost.furniture_catalog()` with its platform-availability gate overridden for the Linux exporter; the existing chair is a declared backend fixture. These tests validate generation, normalization, streaming and feedback acceptance, not actual native creation/contact. No model instance beyond the owned desktop services was started.

All 18 attempts are retained:

| Round | Exact accepted intent | Scope |
| --- | --- | --- |
| V1 | 3/6 | Computer ensure/use succeeds for all profiles; literal `cool` in configuration speech triggers Japanese guard |
| V2 | 3/6 | Added technical-ID-in-metadata instruction and isolated configuration example; same literal-ID failures remain |
| V2 natural Japanese | 3/3 | Chair yaw 45°, scale .8, cool appearance, correct existing target |
| V2 natural Korean | 2/3 | Cheval and Rice correct; Eishin copies fictional example target, rejected by normalizer |

The Korean request was `의자를 45도 돌리고 크기는 80퍼센트로 줄이고 차가운 색감으로 바꿔 줘.` Eishin produced valid Japanese acknowledgement and correct settings but used `prop:sample` instead of the available `prop:obj_1`. The host received no intent. Its spoken promise still exceeds what was executed; this remains a model semantic limitation. No failed case was silently retried or relabeled successful.

Natural-Japanese and Korean configuration rounds used fresh sessions, whereas V1/V2 literal configuration followed computer use and simulated cancellation feedback. They are disclosed variants, not controlled language-only comparisons. The language guard remains strict. Successful issued intents received simulated `cancelled/user_stop` feedback acknowledgements; no real object was stopped in these backend-only tests.

One computer request was voiced in each restart round. Their individual server timings, all outcomes and raw-record hashes appear in the adjacent JSON. These cold-restart observations are not steady-state latency measurements. Full backend suite passed 184 tests before the final added generic-registry regression; the furniture subset, including that regression, passed 28 tests after the prompt update. Real native LM-triggered execution remains a separate acceptance step.

V3 grounding correction removed every fictional target ID and omitted typed configuration examples because current target metadata lacks authoritative object type. Face independently approved that source change; 54 intent/furniture tests passed. The bounded Korean retest then accepted **0/3**: the model no longer copied an invented ID, but omitted required target IDs and emitted array-valued scale/yaw fields. All were stripped by validation. This brings preserved attempts to 21; it is not a successful replacement for V2. A next improvement needs an actual compatible target example backed by native type metadata, rather than reintroducing fictional IDs or weakening normalization.

V4 adds optional native-store-backed `object_type` to prop interests and constructs configuration examples only from an actually listed compatible target. Numeric examples use scalar values within advertised bounds and listed appearance presets. Face independently approved the change. Exactly one Korean configuration attempt per profile now succeeds **3/3**, with yaw 45°, scale .8, cool appearance and the correct `object:obj_1` target. All 24 attempts remain retained; the earlier failures are unchanged. Native object execution is still outside these backend-only tests.
