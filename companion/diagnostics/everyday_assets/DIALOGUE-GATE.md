# Dialogue motion gate

The installed everyday selection correctly excluded seated phases and optional
gait styles, but the dialogue allowlist still advertised `uma_walk` and legacy
`walk`/`walk_formal`. Native dialogue handling rejects those names/capabilities,
so the model could select a gesture that would silently become idle.

`available_motions` now excludes all declared locomotion, seated transition and
gait-style capabilities, plus the reserved legacy walking/seating names. Filtering
also covers procedural-bank name collisions. The asset catalog and verified
downloads remain available for previews and host-owned contextual execution;
loaded locomotion can still be selected through its validated movement intent.

The actual installed catalog has 33 valid entries. All ten `authored_*` everyday
aliases remain advertised with their descriptions. Eight contextual assets are
excluded from ordinary gestures and remain checksum-readable; exact names are in
`dialogue-gate.json`. Typing is described as upper-body pantomime without a prop;
its source loop does not imply autonomous furniture use or a random idle policy.

Focused validation: `test_motion_assets.py` and `test_spatial_locomotion.py`,
**86 passed, 0 failed**. Coverage includes generic metadata without reserved
names, legacy names without metadata, procedural collisions, normal finite
gesture metadata and actual WebSocket request forwarding. The previous test
that expected legacy `walk` as an ordinary gesture was updated to a permitted
authored wave. No model, voice asset, native runtime or backend process changed.

Independent review found one metadata-shadow collision in the first fix: a custom
bank name could hide a same-named VRMA capability before filtering. The final
implementation collects contextual names from both sources before deduplication,
with three generic collision regressions.

Final independent verdict: **APPROVED** by `/root/spatial_review`, which reran
the same focused suite independently: **86 passed, 0 failed**. Source hashes are
recorded in `dialogue-gate.json`.
