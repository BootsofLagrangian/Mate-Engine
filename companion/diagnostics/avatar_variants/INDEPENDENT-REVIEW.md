# Native avatar-variant independent review

Status: **APPROVED after revisions** for the scoped native transaction behavior.

Scope: the avatar variant UI, catalogue selection/cache, same-character reload transaction, local cancellation and terminal feedback in `control_panel.gd`, `backend_client.gd`, `main.gd`, and `living_behavior.gd`. Camera, gait, furniture algorithms and actual Windows rendering are outside this review.

Initial transaction suite covered 23 checks with production main methods and fake network/renderer. Independent added reproductions found two concrete races:

1. After a successful download queues a deferred avatar apply, local Stop/new chat calls `_cancel_current` but did not cancel the avatar command. The queued apply still reloaded the avatar after Stop. The local session suppresses subsequent cancelled-turn events, so relying on backend cancellation cannot repair this.
2. A catalogue refresh during a `wet` request started a reload of the saved `default` variant while leaving the wet command active. Default then loaded successfully and incorrectly reported the wet request completed.

Both reproduced defects were corrected. Local Stop cancels before retiring the turn; external disable/disconnect cancellation revokes the pending/deferred avatar load, with internal `avatar_changed` cleanup explicitly exempted. Catalogue refresh preserves the pending requested variant, and missing variants or changed characters cancel their prior command. Completion checks ownership by both character and variant. Cancellation now also stops tracked HTTPRequest objects and removes their partial files.

Independent final verification:

- Final production-method transaction harness: **32 passed, 0 failed** (`Godot --headless --path native --script ../diagnostics/avatar_variants/test_avatar_variants.gd`).
- Original independent added race reproduction: **25 passed, 0 failed**, including both originally failing Stop and refresh cases.
- Scoped `git diff --check`: clean.

The harness exercises actual selection/request/deferred-apply/control flow with a fake network and renderer; real `LivingBehavior.cancel` is used for disable/disconnect and self-cleanup regression checks. Actual Windows avatar reload and rendering remain separate root-owned acceptance tests.

The inspected cache names isolate character/variant tuples, HTTP callback generations reject superseded download results, and the existing VRM loader constructs the replacement before discarding the old scene. The review does not claim real renderer or Windows behavior from the fake-renderer transaction harness.

## Follow-up preview and Windows probe review

The narrow contextual-clip filter excludes seated and authored gait assets from ordinary gesture/ambient selectors while retaining them for their contact/navigation owners. The expanded native transaction/UI suite independently passed **32/0**.

The external Windows probe was reviewed for false positive/negative risks: it uses real Korean LM requests, Japanese reply text, actual native PCM playback, action/done consistency, exactly one native completion, raw turn-matched backend feedback, and distinct expected avatar hashes. It separates its direct default-baseline setup from the two measured LM actions and restores original settings. It captures owned viewports only. Source parsing passed; no Windows launch was performed by this reviewer.

One deterministic probe false failure was reported: the loader records an absolute `model_path`, whereas the cache helper returns `user://...`. The final revision globalizes and simplifies both paths; independently verified and parsed cleanly. **Probe source APPROVED for root-owned Windows execution.** Actual runtime acceptance remains unmeasured by this review.

Reviewed file hashes (SHA-256; unrelated camera/furniture edits in shared files are outside the review scope):

- `native/scripts/control_panel.gd`: `eae05d39ea42d4c72d493f4aaec4547802b7d925858452c1789eabd591146d0a`
- `native/scripts/backend_client.gd`: `5394c94372e199633af84118b4b6bfe849d21f6bf8e6d86f894dd7deba8d1fd1`
- `native/scripts/main.gd`: `547893d4686f9058dacc074b9c4ef1b8bb809ac934055751d790dd14651d539f`
- `native/scripts/living_behavior.gd`: `ae1502dd0e501e1dc03ad200f6e7a9549f558c08e9fe5d2bc99e79045a6976b7`
- `diagnostics/avatar_variants/test_avatar_variants.gd`: `a222fb4c62637500acd0914baff733bdf3d3d3f383e67f88b15a563ddc59c267`
- `diagnostics/avatar_variants/host_fixture.gd`: `3f512e72a6b7be8f2174ad3a59ae1759b612eb6691c49eea8d14e70f76266a64`
- `native/tools/probe_windows_appearance_skills.gd`: `07fe240bd4ba2ce42facc1869131b1d2f629931c378d9745b27a4d847c4981f0`
