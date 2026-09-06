# Fable medium furniture grounding review

`claude-fable-5-1`, medium. Full command/prompt/output retained under logs/collaboration/fable-furniture-grounding-review*.

APPROVED

**Scope reviewed:** current-vs-HEAD diff of `companion/engine/profiles.py`, `companion/engine/intent.py`, `companion/engine/providers/omni.py`, plus the new untracked `companion/engine/tests/test_skill_prompt_grounding.py`. No source modified, nothing run on GPU or Windows, no services touched.

**Tests:** ran the two requested files with the omni venv.

```
engine/tests/test_skill_prompt_grounding.py + engine/tests/test_furniture_intents.py
33 passed, 15 warnings (pre-existing FastAPI/anyio deprecations)
```

**Findings, all confirmed against the code:**

- **Example selection is correct.** The new capability picker scans all available entries for a `use` verb first, then falls back to `place`. With the legacy catalog, `computer/use` now wins over `chair/place`. Unavailable entries and configure-only entries yield no example, so no type or ID is invented.
- **Ordinary chat is not forced into furniture.** The per-turn grounding pairs an execution row carrying an intent with a conversation row carrying none, and states that only an actual execution request produces the intent. The existing system-prompt rule to omit intent for normal conversation is unchanged.
- **Tone examples no longer compete with the reply schema.** In desktop context, voice samples are emitted as quoted text prefixed with a label saying they are not a JSON or behaviour template. Non-desktop prompts are byte-identical to before, and the test asserts both branches.
- **Placement in the message is right.** The grounding lands after the furniture rule and before the current user message, for both text and audio modalities. The system prompt already includes the same skill via the system-level example, so the two agree on the advertised ID.
- **No routing or validator change.** Validators, generation, and intent parsing are untouched. The tests only assert prompt text and never feed a harness model.

**Minor, non-blocking notes:**

- The execution row's request meaning says "installed furniture". The host creates the item on demand, so "advertised" would be more accurate. Cosmetic only.
- The added grounding repeats per turn, roughly 150 tokens. Acceptable against the 4300-token input in the failing log, but worth remembering if context budget tightens.
- Only the omni provider appends the new grounding. That matches the requested scope, but any other provider building furniture prompts would not get the contrast examples.
