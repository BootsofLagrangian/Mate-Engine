# Default idle Windows probe review

APPROVED for test design, pending actual Windows execution. Independently reviewed `native/tools/probe_windows_default_scene_idle.gd`.

The probe begins from product Settings.DEFAULTS with only character/backend endpoint overrides, checks actual perspective/enabled state and populated scene targets, and makes no chat or direct scene movement request. Its single owned-window corridor placement is disclosed. A qualifying depth trip must originate from a local Director request and have an exact matching arrival terminal. The five-second canonical XYZ hold is tied to that same qualifying trip, with ground latching retained and drift limited to 5 mm. Captures read only the owned viewport.

The no-conversation claim is correctly limited to turn counters and received conversation events. It does not claim independent interception of outbound traffic. This finite observation does not establish long-run movement frequency, all contexts/rigs, or aesthetic naturalness.

Two diagnostic robustness follow-ups were requested: recursively sanitize nonfinite vector components for valid JSON and verify restored settings by reading their persisted file rather than comparing the assigned in-memory dictionary. Neither changes runtime behavior or weakens acceptance thresholds.

Follow-up: both diagnostic fixes are present on rereview. Vector components recurse through finite sanitization, and restoration rereads Settings.PATH against the serialized original. Independent Godot check-only passes. Final source verdict remains APPROVED for the stated observation scope; no Windows result is inferred.
