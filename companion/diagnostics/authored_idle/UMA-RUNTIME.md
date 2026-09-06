# UMA authored idle runtime

Run from the repository root after the verified 32-FBX extraction exists:

```sh
python companion/diagnostics/authored_idle/convert_uma_runtime.py --install
python companion/diagnostics/authored_idle/test_unity_curves.py
python companion/diagnostics/authored_idle/test_humanoid_bake.py
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native -s tools/probe_authored_ambient.gd
DISPLAY=:0 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --rendering-method gl_compatibility -s tools/render_authored_ambient.gd
```

The driver imports selected FBX files with Godot, bakes the verified humanoid
mapping and animated helper ancestors at 60 Hz, explicitly corrects FBX units by
×100, then assembles real entry/loop/exit actions. `--install` copies seven local
VRMA aliases and updates `companion/motion-assets.json`. Without it, files remain
research candidates. Source extraction hashes/settings remain in
`assets/research/uma/export-work/natural-subset/manifest.json`.

The quiet generic base is `uma_home_idle`. Three character-source style loops
are available through manual motion preview or profile configuration (not the
quiet-idle dropdown), but are sustained expressive poses, not
neutral idle substitutes. Three `_idle_action` clips contain actual entry, loop
and exit: Cheval 3.733 s, Rice 4.333 s, Eishin 4.167 s. Source phase seams are at
most 0.110 degrees. All clips retarget to all three rigs; source character names
are provenance, not runtime character-specific branches.

Host contract:

- `load_vrma(name, path, contact_mode="")`: catalog `contact_mode:"foot"` also
  enables hip translation and stance correction for explicit gesture previews.
- `set_ambient_loop(name)`: continuous separate layer, no gesture-active signals.
- `play_ambient_action(name)`: finite action over the running base; returns false
  when ownership conflicts prevent playback.
- `set_ambient_attention_override(bool)`: smoothly gives head/neck to gaze while
  keeping the base phase continuous. Authored rotation blends over the continuing
  gaze base, rather than abruptly removing either pose source.
- `set_ambient_suspended(bool)`: host holds this for speech/drag/foreground work;
  do not infer whole-utterance ownership from individual audio-envelope samples.

Converted files retain every mapped translation. Runtime applies **hips offsets
only**, normalized by source hip height and target hip height; target bone lengths
remain fixed. Final two-foot IK deliberately changes the authored legs to maintain
standing desktop support. This is not exact source world-position reconstruction
or a general root-motion/physics player.

Support acquisition lasts 1.2 seconds: when an outgoing animation has displaced
the feet, targets move smoothly from those actual positions to the standing
anchors. `authored_ambient.diagnostics.contact_weight` exposes progress; fixed
contact is asserted only after acquisition. The continuous head-ownership pursuit
is limited to 0.65 weight/sec and 0.8 weight/sec², separate from gaze pursuit.

Remaining extraction candidates are not installed automatically: authored turns,
walk starts/stops and directional walking require mapping their root trajectories
to existing desktop movement/contact ownership. Chair-look entry/loop/exit was
rendered as a seated upper-body candidate using the existing seated lower-body
mask, but remains a prototype pending integration scope. Phone/drink sources from
other packs were not selected because their props/context are absent.

Proprietary source/converted binaries and derived screenshots remain local. Commit
only reusable tooling, runtime implementation and provenance/configuration metadata.
