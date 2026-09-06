# Fable medium no-intent assertion review

APPROVED

**Scope reviewed:** the `expect_no_intent` additions in `companion/run_text_scenario.py`, the `valid_step`, `no_intent_assertion_passes`, and trial hook in `companion/native/tools/run_text_scenario.gd`, the new headless `diagnostics/text_scenarios/test_assertions.gd`, the new Python test, and `computer-conversation.json`. Read-only, no GPU, Windows, or services.

**Tests run:**

| Suite | Result |
|---|---|
| `engine/tests/test_text_scenario_validation.py` | 9 passed |
| Godot 4.5.2 Linux headless `test_assertions.gd` | 10 passed, 0 failed, exit 0 |

**Findings, all confirmed:**

- **Assertion never reaches the model.** The only value submitted is the step text via `app._send_chat`. The assertion fields are read solely in the local trial checks and the validators.
- **Boolean and mutual-exclusion checks match on both sides.** Python rejects non-bool via a strict type check, so integer 1 and the string "true" fail. Native uses a `TYPE_BOOL` typeof check. Both reject the combination with `expect_intent`.
- **Fails on either event path.** The pass helper requires that neither the action nor the done event carries an intent key, and the trial appends a distinct failure label. The headless test covers both the action-only and done-only cases.
- **Validators are now aligned.** Native `valid_step` mirrors Python's supported-field set, non-empty text up to 4000 chars, finite timeout in 1..90, non-empty dict for expect_intent, and the same outcome vocabulary. The new native check also rejects a boolean timeout and stray keys such as a raw intent, which the old inline check did not.
- **Scenario file is well formed.** The Korean negative-control step carries only text and the boolean assertion and passes the Python validator.

**Non-blocking notes:**

- With `expect_no_intent` the wait predicate still only waits for the done event, so an intent arriving after done would not be observed. Since action precedes done in the existing stream ordering, this is acceptable.
- Native timeout check rejects a boolean via typeof, but Python's check would need review if a bool timeout should also be rejected there. Out of scope for this delta.
