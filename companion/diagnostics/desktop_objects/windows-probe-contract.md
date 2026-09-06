# Actual Windows furniture probe

`native/tools/probe_windows_objects.gd` is an opt-in external main-app probe. Run with the real Windows Godot executable or exported app, `--script <absolute Windows script path> -- --output <absolute Windows output directory>`. The backend and installed avatar/motions must be available. Do not run alongside another companion instance. The probe has a 420-second overall bound and writes partial `report.json` after every check.

The Linux headless compile check passes and exits 2 with `WINDOWS_OBJECTS_NOT_RUN`. This verifies parsing only; Windows behavior is not validated by that check.

The probe checks:

- Chair, sofa and computer GLBs load in visible, separate native windows on an actual usable monitor workarea.
- At pet scale 0.6, chair and sofa interactions approach by more than 100 actual OS window pixels, attach the seat, and place the projected avatar seat anchor within 3 pixels of the furniture's projected seat socket.
- The existing user-stop handler releases an occupied chair. Moving, resizing, hiding and removing an occupied chair each release seating, with a fresh occupied-state prerequisite for each mutation.
- Furniture data survives a JSON/store round trip and is written through Settings.
- Computer use enters its finite work stage. A post-draw measurement reports `hand_reachable`, projected wrist-to-keyboard distance and world-space wrist-to-target distance; acceptance requires reachability, at most 3 pixels and at most 2 cm. It then waits for finite expiry. No keyboard/mouse automation is performed.
- Repeated shutdown removes all owned furniture windows, and original Settings are restored during teardown.

The probe creates and moves only its own application/furniture windows and captures only their viewport textures. It disables VAD, but connects to the configured backend for startup assets; it does not submit audio or conversational turns. It temporarily replaces furniture preferences and restores the original settings on normal teardown, failure teardown and its internal deadline. An externally killed process cannot guarantee restoration.

Initial furniture positions use distinct workarea fractions (.2/.5/.8); an interaction target is moved to .62 while the pet starts at .35. These are actual window placements, not simulated positions. Before each seat/use interaction, all other furniture is hidden and the target is shown and awaited until loaded. Pet and target textures are read without an intervening await after one post-draw signal. Their PNGs share timestamp and native-position metadata, and an additional composite places the pet over the prop at those positions. This assumed layer order is explicitly labeled; it does not establish actual OS z-order or constitute a compositor screenshot. Camera projections use Godot desktop coordinates and each viewport's own camera. The seat metric concerns the configured rendered contact anchor, not an independently inferred anatomical mesh point.

Prerequisites and timeouts count as failures, including absence of a reachable keyboard or floor support. Inspect the recorded checks, contact measurements, outcomes and owned-viewport images before drawing visual-quality conclusions. Root owns Windows execution and independent review; this document makes no claim that the Windows assertions have passed.

The first development Windows run remains preserved at `logs/windows-objects-development`: persistence equality, sofa interruption and wrist contact failed. Subsequent probe changes canonicalize disk furniture through `Store.set_data` while retaining the complete parsed disk payload, and record 250 ms context snapshots plus navigation/intent/interaction outcomes with pointer, panel, busy state and support geometry. These changes improve diagnosis; they do not retroactively pass the first run or establish the cause of its failures.

## Current shared-scene and persistence acceptance

`--character ID` defaults to `cheval-grand`. After hello, the probe explicitly selects that catalog ID and waits for matching session ID, actual loaded VRM cache filename and successful avatar load. It records actual model path, title and SHA-256. Prior runs without these fields do not establish rig identity from initial Settings alone. `--contact-only` skips the four repeated occupied-chair mutations; it retains three contact interactions, user stop, persistence and cleanup, and records the reduced mode.

Shared contact scenes are now mandatory for chair, sofa and computer acceptance. When active, the root viewport contains pet and furniture in one depth buffer and is captured directly; a legacy separate-viewport diagnostic cannot pass the shared-scene assertion. Computer checks both final wrist positions against named keyboard sockets, plus seated contact. The calibrated seat anchor is not an independently measured anatomical mesh contact. Natural computer expiry requires exactly one matching `interaction_finished` outcome of `completed`; an empty interaction caused by cancellation fails.

Persistence uses canonical Store values. All non-scale fields, object order/count and dictionary keys must match exactly. Scale must remain finite with absolute error at most `1e-12`, and `Store.rect_for` must produce exactly the same pixel rectangle. Thus even a smaller scale difference fails if it changes rounded geometry. Reports retain 17-decimal source/restored scale strings, absolute differences and both rectangles. This accounts for Godot's default JSON double rounding without quantizing production state or accepting meaningful persistence loss. A local isolated five-case comparator check passed: serializer roundoff accepted, meaningful scale/position/label differences rejected, and a sub-tolerance scale change crossing a pixel-rounding boundary rejected. No Windows assertions were rerun as part of this comparator change.
