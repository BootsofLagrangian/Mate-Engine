# Curated authored everyday capabilities

Ten everyday VRMA capabilities and the three selected UMA seating phases are
installed through `selection.json`. The shared catalog contained 33 valid entries
after this installation, including the other owner's two playful locomotion
clips. Acquisition and installation counts are different: 59 previously acquired
canonical source clips plus 13 newly acquired generic gesture phases = 72 source
candidates. Joined actions and the typing mask are derived selections, not extra
independent source captures. Only 13 entries are managed by this installer.

## Installed everyday selection

| Alias | Seconds | Playback and observed source shape |
| --- | ---: | --- |
| authored_think | 5.167 | Entry, hand-near-chin thinking, exit |
| authored_bow | 3.067 | Entry, small polite bow, return upright |
| authored_breathe | 5.400 | One deliberate breath with relaxed arms; finite action |
| authored_wave | 1.967 | Friendly hand wave, returns toward standing pose |
| authored_stretch | 3.367 | Shoulder/arm stretch and release |
| authored_overhead_stretch | 4.100 | Arms extend overhead/outward and relax |
| authored_read | 12.533 | Retrieve/read/return pantomime, entry + loop + exit |
| authored_drink | 4.600 | Lift/drink/lower pantomime, entry + loop + exit |
| authored_phone | 2.033 | Stable authored check-phone hold, native fade in/out |
| authored_type | 8.333 | Repeating keyboard pantomime; 43 upper-body rotation channels only |

The remaining selected entries are `sit_enter`, `sit_idle`, and `sit_exit`.
The motion owner approved their actual three-rig sit/stand renders and support
checks before installation. `sit_idle` replaces the old Quaternius source SHA
`1f618806f57d1a4b86802e82575224514514ce7492aad0eb7d034b1f1dea5bc5`
with the paired UMA01 idle. The runtime owner added source-load calibration/cache
invalidation and generic enter/exit registration. The manifest marks the finite
phases with `seated_transition: enter|exit`.

All these entries are `ambient: false`. They become ordinary catalog/preview and
motion capabilities, but do not automatically become random idle actions. The
existing `uma_home_idle` continues to provide quiet standing animation. This
curation does not claim a new dedicated looking-around idle. Reading, drinking,
phone and typing descriptions explicitly say no prop is attached. Their authored
hand motion is available; attaching/synchronizing objects remains separate work.

## Selection evidence

`source-statistics.json` decodes every selected channel, confirms finite samples,
reports all 52 mapped bones, and separates finger motion from larger-joint motion.
Typing retains all 52 rest/mapping definitions but animates only 43 upper-body
bones. It has no hips, legs, feet, toes or translation channels. Its rotation
loop seam is 0.01546 degrees. Seated idle's seam is zero. Other everyday motions
are finite, so their endpoint gap is handled by the existing entry/exit blend.

The full phone entry/loop/exit source was rejected for this release: its wrist
jumps 25.08 degrees in one 60 Hz step during release. The installed hold instead
has a maximum non-finger step of 0.271 degrees. Reading's largest 37.79-degree
step is on a distal finger during release, while its largest non-finger step is
4.615 degrees. It was retained after source-shape review; no Euler interpolation
repair or invented motion was applied at that point. Source quaternion sampling
had already replaced the corruptible FBX Euler route.

Actual Linux Godot Compatibility renders of 20 alternatives were inspected on
Cheval, followed by the derived typing clip. Selected source movements are
coherent; the joined phases keep their authored poses. Capture sheets and the
typing image are local ignored research artifacts under
`assets/research/everyday-candidates/render-review/`. This is source pose review,
not proof of Windows compositor/MToon output. Raw images were captured with
`render_sources.gd`; they do not use the production native window.

`probe_runtime.gd` then exercises the actual MotionPlayer on Cheval, Rice and
Eishin at 60 Hz for every selected everyday clip's full duration; typing runs two
cycles. `runtime-results.json` contains all 30 cases. There are no nonfinite bone
poses. The nine standing full-body gestures use existing final foot contact; the
maximum reported solver residual is 0.000000391 m, below the 0.015 m gate.
Typing deliberately uses no foot solver of its own. This test does not measure
screen-pixel foot sliding, prop collision, cloth motion or Windows presentation.
No Windows process was launched for this subtask.

The backend's real `MotionAssets.catalog()` and `read()` validated every selected
file and checksum: 13/13 selected, 33 total entries at installation. Generic
catalog consumers can therefore fetch/preview these installed aliases. No core
backend, native playback or LLM policy change was made by this curator.

## Provenance and reproducibility

These selected clips derive from the user's local UMA files, not CC0 assets.
They remain ignored under `assets/`; no original bundle, FBX, YAML or VRMA binary
was added to Git. Each manifest entry points to extraction and conversion
provenance. `selection.json` pins exact source and installed hashes.

The original 47 sitting/object sources are reproduced by
`diagnostics/seating_assets/acquire_uma_actions.py`. `acquire_extra.py` exports the
additional 13 generic think/bow/breath/stretch/wave sources and direct-quaternion
bakes them using the existing extractor. Both exporters refuse nonempty output
directories and read original F: bundles without modifying them.

After those sources exist:

```sh
python3 companion/diagnostics/everyday_assets/build_selection.py
python3 companion/diagnostics/everyday_assets/inspect_selection.py
python3 companion/diagnostics/everyday_assets/install_curated.py
```

`build_selection.py` concatenates authored phases and filters typing channels;
it does not generate poses. `install_curated.py` preflights every source hash, alias, duration and contained
target path before its first write. Peer review requested this all-or-nothing
validation step; invalid later hashes and escaped targets now cause no mutation.
The installer replaces only selected aliases, preserves unrelated entries, and atomically
replaces individual files/the manifest after a concurrent-change check. Shared
catalog mutation was coordinated with seating and playful-motion owners.

Public UAL2 folded-arm/yes/no and other acquired candidates were rendered for
comparison but not automatically promoted. The current result is a deliberately
small useful subset, not an indiscriminate preload of the acquired library.
