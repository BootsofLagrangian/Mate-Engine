# Authored seating Windows probe review

APPROVED for the declared measurement scope after the handoff sampling fix. Reviewed `native/tools/probe_windows_authored_seating.gd` independently of its implementation. The probe uses production processing, registered source clips, actual skeleton joint positions, validated furniture commands, and owned viewport images. Its fixed front orthographic physical coordinate conversion remains defined after the occupied scene is released. Settings and owned resources are restored on completion/watchdog.

A discovered gap allowed a long transition-boundary interval to enlarge the joint continuity allowance without failing the within-phase 20 Hz gate. Both the boundary timing check and continuity acceptance now require `0 < dt <= 0.05` seconds, while preserving raw timing and displacement.

This source approval permits the actual Windows run. It does not approve aesthetic naturalness, perspective seating, or unseen renderer output. PNG capture overhead is included in measured intervals and can cause an honest timing failure.
