# Production perspective probe

`native/tools/probe_windows_perspective.gd` is an external opt-in Windows script. Launch exclusively against the candidate project/package with `--output ABS_DIR`; it loads the normal main scene and requires the real backend/avatar readiness. It restores the initial settings and stops its owned windows, audio, world helper and WebSocket on completion or its 120 second watchdog.

The fixture uses two actual native chair windows in the common World3D, at explicit canonical metre positions. It checks overlapping crop rectangles, optical-depth translation without changing the model basis, canonical socket projection, immutable saved world positions and physical scales across UI camera-setting signals, and private-world restoration when returning to orthographic mode. It records actual native viewport images and a diagnostic canonical-camera viewport of that same world after rendering.

Image comparison records every opaque sample and raw mismatch. The acceptance gate separately requires at least 100 flat interior samples and zero mismatches there, where a flat sample has all nine reference RGBA pixels within 0.02 of its center. This prospective boundary exclusion addresses the already documented crop rasterization differences; it is not a claim of complete pixel identity. Native window identity and shared world identity are checked separately.

No other desktop pixels or user input are captured or injected. Native compositor partial-alpha overdraw, hit routing, seated choreography, and subjective visual quality are not established by this probe. Root must inspect retained images and record the actual package/renderer provenance with the Windows result. This file describes a pending test, not a Windows pass.
