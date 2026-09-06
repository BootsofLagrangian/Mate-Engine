# Desktop intent validation

The backend and native controller were tested separately, then together on Windows. Protocol and validation rules are in [engine/README.md](../../engine/README.md); implementation is in [engine/intent.py](../../engine/intent.py), with the coordination contract in [astra-intent-contract.md](../../logs/collaboration/astra-intent-contract.md).

## Real model development rounds

Each round used the same nine Korean/Japanese requests across Cheval, Rice and Eishin: seven known-target move/inspect/rest requests and two unavailable-target requests. Every request started a fresh connection with an explicit character selection and the same two named targets. All **27 attempts** are retained; none were excluded. These repeated development cases are not a held-out reliability estimate.

| Round | Correct required intents | Unknown intents blocked | Valid JSON / action-final parity | First voiced PCM |
| --- | --- | --- | --- | --- |
| [V1](../../logs/intent-gpu-v1/report.json) | 0/7 | 2/2 | 9/9 each | 2,101.8 ms |
| [V2](../../logs/intent-gpu-v2/report.json) | 7/7 | 2/2 | 9/9 each | 2,193.9 ms |
| [V3, retained](../../logs/intent-gpu-v3/report.json) | 7/7 | 2/2 | 9/9 each | 2,234.6 ms |

V1 omitted intent metadata. V2 resolved the competing three-field schema and added isolated format examples plus a current-request reminder. V3 added an unavailable-target negative example. Only conversations with desktop context receive these additions; no periodic model calls or phrase-to-action router were introduced.

Each round included **one voiced request immediately after a supervisor restart**, followed by eight voiceless requests. Median first-text latency for those later requests was 102.7, 110.1 and 121.7 ms respectively. These single voiced observations are not a controlled latency benchmark. Reports retain configuration/source hashes and timed events; V2/V3 also retain every raw model JSON. Scripts are [V1](../../logs/probe_intents_gpu.py), [V2](../../logs/probe_intents_gpu_v2.py) and [V3](../../logs/probe_intents_gpu_v3.py). No native movement was executed in these rounds.

**Remaining language limitation:** both V3 unknown-target raw outputs invented `prop:bookshelf`, which validation stripped. Rice still said “本棚へ向かいますね。” and returned `walk` gesture metadata despite having no executable movement intent. Eishin correctly said the location was unavailable. The native host now reserves dialogue `walk`, `walk_formal` and `sit_idle` for navigation/contact control, so that metadata alone does not start marching in place. This guard does not repair the spoken promise; live geometry validation and controller outcomes are authoritative.

## Final verification

The full backend suite passed **111 tests** after the retained prompt changes, covering streaming parity, metadata bounds, unknown targets, expired/changed context, character isolation, reset/reconnect and profile behavior settings.

Root's final packaged Windows probe passed **12 checks, zero failures** using a real Korean request, GPU-generated Japanese acknowledgment and dedicated voice. The [raw native report](../../logs/windows-native-intent/report.json) records `move_to` for the listed `support:left` target, identical action/final intent, zero position drift during spoken acknowledgment, actual Windows movement from `(890,672)` to `(-354,672)`, and exactly one `arrived` outcome after deduplication. Native first PCM receipt was 954 ms in this separate run. This establishes one complete spoken-request-to-arrival path, not general navigation or model-language reliability. The backend reviewer inspected this artifact; root executed the Windows test.

Raw logs are local diagnostic artifacts and may not be present in a fresh checkout. This tracked record preserves the selection, counts and acceptance limits.
