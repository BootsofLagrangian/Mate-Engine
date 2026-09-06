# Fable medium bilingual grounding review

Full command/model/prompt/output retained under logs/collaboration/fable-bilingual-grounding-review*.

APPROVED

**Scope reviewed:** the current `furniture_request_grounding` in `engine/intent.py` and the new bilingual test in `engine/tests/test_skill_prompt_grounding.py`. Read-only. No edits, services, GPU, or Windows.

**Tests run:**

| Suite | Result |
|---|---|
| test_skill_prompt_grounding, test_furniture_intents | 34 passed |

**Findings, all confirmed:**

- **No unsupported IDs.** Both example rows derive from the capability picker, so the object type is always an available registry entry and the verb is `use` only when advertised, otherwise `place`. An empty or configure-only catalog yields an empty string, so nothing is invented.
- **Ordinary chat is not forced.** The second row is a paired Korean and Japanese request that explicitly says not to take out or use anything, and its reply carries no intent. The trailing instruction still tells the model to answer normal questions directly and not operate unrequested furniture.
- **No phrase-to-action routing.** The Korean and Japanese request fields are generic "this furniture" phrasings bound to the skill ID, not to any input word. The test asserts that neither the Korean nor English word for computer appears anywhere in the output.
- **No generation or parser change.** The delta only alters example text inside the same tagged block. Validators, generation, and intent parsing are untouched.
- **Test is portable.** It uses an arbitrary ID for both verbs, checks that the execution row's wording tracks the verb, and confirms the negative row stays intent-free.

**Non-blocking note:** the instruction "speak Japanese in either case" restates the existing system-level language rule. Harmless redundancy.
