# Occupied view bounds correction

The failed packaged run is preserved at `logs/windows-space-skills-d3d12-refresh/report.json`. Computer creation/use/feedback and initial configured-chair contact passed; changing camera yaw/pitch to 45° released the chair with `view_does_not_fit`.

`probe_view_fit.gd` reconstructs the reported Cheval rig, physical chair scale, camera, desktop origin and usable workarea using actual imported geometry and canonical seated bounds. The rotated combined envelope is 319.34×370.28 pixels, so it fits the 680×760 viewport. Its global bottom is 1444.59 while the usable desktop ends at 1392. The failure is a 52.59-pixel workarea overflow, not insufficient viewport size or bad seat alignment.

For an already occupied seat, fitting now applies the minimum integer translation to the entire pet/furniture assembly: exactly 53 pixels upward in this case. Window origin, autonomy origin and shared desktop floor move equally; local pivot, physical scale, camera and seated pose remain unchanged. The next owned-seat reprojection retains exact support identity. No dimensions or safety tolerances are relaxed. Translations larger than 256 pixels, oversized arrangements, and disconnected destination monitors are rejected.

The ten-check reproduction verifies sub-.001-pixel seat coincidence, full combined workarea containment, unchanged local pose, idempotent repeated fitting, negative monitor origins, and rejection cases. The existing host suite remains 32/0. Logs retain before/after measurements. This is a CPU geometry regression; the packaged Windows camera-control replay remains separate acceptance evidence.
