# Fable medium prompt-capture review

Full command/prompt/model output retained under logs/collaboration/fable-prompt-capture-review*.

APPROVED

**Scope reviewed:** `engine/prompt_capture.py`, the capture and health-summary hooks in `engine/providers/omni.py`, the world_context acknowledgement in `engine/server.py`, the `--capture-prompt` arming and cleanup in `run_text_scenario.py`, the pre-publish native snapshot in `native/tools/run_text_scenario.gd`, and the new tests. Read-only. No edits, services, GPU, or Windows.

**Tests run:**

| Suite | Result |
|---|---|
| test_prompt_capture, test_omni_prompt, test_text_scenario_validation | 21 passed |
| Godot 4.5.2 headless test_assertions.gd | 10 passed, 0 failed, exit 0 |

The omni test uses the real CPU tokenizer and confirms the captured prompt equals the live chat-template output plus the JSON prefix, and that input ids are identical with capture off.

**Findings, all confirmed:**

- **Guard is exact and narrow.** Capture requires the marker's character to match, the SHA-256 of the stripped current text to match, and a finite expiry within the next 900 seconds. Audio requests and any session with prior history return early. The runner and the backend both hash the stripped first-step text, so the two sides agree.
- **One-shot and race-safe.** Output uses exclusive create, so a repeated marker with the same ID cannot overwrite an earlier capture. The marker is unlinked only when its ID still matches. The runner's cleanup removes a leftover marker only for its own ID.
- **No HTTP prompt surface.** The capture is written to the local user-data diagnostics directory, which is gitignored. The health summary exposes only catalog IDs and verbs, interest count, locomotion IDs, and variant IDs, never the prompt.
- **Inference path unchanged.** The hook runs after the real template render and before tensor preparation, with all failures swallowed. Nothing from the scenario assertions reaches the request.
- **Server acknowledgement is not misleading.** The world_context reply now echoes the validated rich catalog IDs and verbs alongside the legacy types, so an empty legacy list with a populated catalog is distinguishable.
- **Native snapshot references real methods.** Both host methods called for the pre-publish snapshot exist in `desktop_objects_host.gd`.

**Non-blocking notes:**

- If a stale marker already exists when the runner arms capture, the exclusive create raises an uncaught traceback rather than a parser error. This fails closed, so it is safe, but the message is unfriendly.
- The capture ID regex requires 32 lowercase hex characters, which matches the runner's UUID hex output and blocks path traversal. Fine as is.
