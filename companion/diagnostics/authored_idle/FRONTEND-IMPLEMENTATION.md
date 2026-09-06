# Frontend authored-idle summary (Fable) — 2026-09-06: usable "대기 동작" selector

Scope (frontend-owned only): `native/scripts/control_panel.gd`, `native/selftest.gd`,
`native/README.md` ("VRMA motion assets" bullet + test list). Not touched: `settings.gd`, `main.gd`,
`motion_bank.gd`, `motion_player.gd`, profiles/backend, protocol. No commits, no Windows run, no model
or backend restart. Not final: the frontend runtime behaviour is unverified until root's Windows run.

## What changed

- `_refresh_idle_clip_option()` no longer builds a single disabled item. Items (metadata = setting
  value): `auto` → "자동 (캐릭터에 맞게)" / "자동 · <description> (<clip>)" when the current
  character's `ambient_loop` is loaded / "자동 (캐릭터 동작 준비 중)" when declared but not loaded;
  `""` → "기본 호흡만 (클립 없음)"; then each eligible clip as "<manifest description ≤28 chars…>
  (<name>)" or the bare name, tooltip = description + duration. Selector enabled;
  `fit_to_longest_item = false` + `clip_text` so long descriptions cannot widen the panel.
- Eligibility `ControlPanel.idle_candidates()` (sorted): catalogue entry with `ambient == true`
  **and** `loop == true`, or legacy `idle_natural` (`AutonomyBridge.AMBIENT_IDLE_CLIPS`), or the
  current character's declared `ambient_loop` when loaded. `walk`/`prop`/`dance`/one-shot ambient
  clips are never listed. No hardcoded character branches.
- Preservation: `_idle_choice` is read from `idle_clip` at build, updated only by a user pick or the
  host mirror `set_idle_clip(value)`. If the saved clip is not loaded (before download, after a
  failed download, removed from the catalogue) it stays selected as "<clip> (아직 없음)"; refreshes,
  character switches and mirrors never emit `setting_changed`. A user pick emits
  `setting_changed("idle_clip", "auto" | "" | "<clip>")` exactly once.
- Profile automatic mode: `set_characters(characters, current)` now reads `ambient_loop` from the
  current character dict (the character catalogue already carries it) → `set_idle_profile(name)`;
  `idle_profile()` getter. Only the label changes; `Main._apply_ambient_idle` keeps resolving the
  actual loop through `MotionPlayer.set_ambient_loop`.
- Motion tab preview untouched: every imported clip remains in the preset list.

## Host-facing API (no main change required; optional)

- `ControlPanel.idle_candidates() -> Array[String]`, `idle_clip() -> String`,
  `set_idle_clip(value)` (mirror, no emit), `set_idle_profile(loop)`, `idle_profile()`,
  static `idle_clip_label(name, entry)`.
- Existing `setting_changed("idle_clip", value)` → `Main._on_setting` → `_apply_ambient_idle()`
  unchanged. Root may call `panel.set_idle_clip(...)` after a settings reset if one is added.

## Tests (`native/tools/run_selftest.sh`: 528 passed, 0 failed; was 502)

- `[motion asset catalog]` (+3): non-bool `ambient` rejected ("ambient is not a bool", 7 problems),
  `ambient` defaults false, boolean ambient+loop carried.
- `[panel: vrma presets + roaming controls]` (updated 2): with walk/dance/nod only, the selector
  offers exactly `["auto", ""]`, enabled, auto selected, plain wording.
- New `[panel: idle selection]` (22): saved-but-unloaded clip kept as placeholder at build;
  eligible-only candidates (`idle_natural`, `uma_idle`, `zz_calm` from a 7-clip catalogue);
  placeholder resolves on catalogue arrival while still selected; truncated description label;
  name-only label; auto label without/with profile, pending profile loop, declared loop eligible
  once loaded; character change keeps the explicit choice; refresh dropping the saved clip →
  placeholder, no emit; round trip restores; user picks emit `""`, clip, `auto`; host mirror no emit;
  empty catalogue keeps placeholder; auto with nothing loaded = two items; preview presets intact;
  CJK width budget.
- Also re-verified unchanged: host lifecycle probe 25/0 earlier this session (not re-run after
  this change; the panel is instantiated by selftest's `[control panel fit]`).

## Not verified / for root

- Visual result of the selector and the actual authored loops under gaze/gestures need the Windows
  run; `MotionPlayer.set_ambient_loop` was being edited concurrently (selftest passed against the
  tree state at run time, no retry needed).
- If root wants the "자동" label to show the *resolved* loop rather than the profile's declared one,
  call `panel.set_idle_profile(resolved_name)` from `_apply_ambient_idle`.
