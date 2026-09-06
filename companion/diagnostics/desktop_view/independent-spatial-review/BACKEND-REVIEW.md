# Independent additive backend review

Verdict: **APPROVED** for the bounded spatial, locomotion-selection and appearance-variant backend additions. No blocking defect found. This author is independent of their implementation.

Reviewed `furniture.py`, `intent.py`, `server.py`, `profiles.py`, provider request/prompt forwarding, final Turn validation and relevant tests. Exact hashes are in `backend-source-identity.json`.

`position_m` is admitted only for advertised `desktop_scene_v1`, requires exactly finite numeric x/y/z within declared bounds, rejects booleans, excludes simultaneous placement and is limited to place/configure. It does not equate storage bounds with reachable/native-visible positions. `locomotion_id` is permitted only for a finite move_to request and must be in the current native catalog; descriptions are bounded data, not executable asset paths.

Appearance variants are derived from the selected validated profile and installed files, gated by native boolean opt-in. The HTTP query selects a declared variant and returns 404 for unknown/missing IDs; it does not accept a filesystem path or silently fall back. Variant declarations reject escaping paths, unsupported override fields and duplicate/reserved IDs. The LM action accepts only kind and variant_id from the installed catalog. Appearance context changes do not call character selection or history reset: conversation remains indexed by the same session/character. This is a backend property; native rig reload and voice continuity need separate runtime validation.

Freshness and withdrawal reuse the existing 45-second world TTL and revision mechanism. Changes to spatial descriptors, gait catalogs, native appearance support or active appearance revoke in-flight capability snapshots; identical heartbeats do not. Turn forwarding and sender dequeue both check current validity. Cancelled/superseded turns are filtered. Execution reports require a previously issued intent from the same connection and selected character, bounded lifetime and a bounded result/reason; duplicate terminal reports are acknowledged without adding duplicate history feedback. Missing files after request creation can still fail natively; this is not represented as successful execution.

Independent command from the repository root:

```
../.venv-omni/bin/python -m pytest companion/engine/tests/test_spatial_locomotion.py companion/engine/tests/test_avatar_variant_route.py companion/engine/tests/test_furniture_intents.py companion/engine/tests/test_intents.py -q
```

Result: **73 passed**, 0 failed, 0.62 seconds; only existing FastAPI/AnyIO deprecation warnings. The implementer separately reports the complete 211-test backend suite in `../../desktop_objects/ADDITIVE-SKILLS-VALIDATION.json`; this reviewer did not rerun that full suite. These tests use fake providers and local HTTP/WebSockets; they do not demonstrate real-model instruction accuracy, actual avatar loading or production GPU execution. No production service was changed by this reviewer.
