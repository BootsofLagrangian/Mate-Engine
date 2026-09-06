# Product-defaults fixture review

**APPROVED** after one corrected diagnostic defect. Independent review of the
root-authored `--product-defaults` changes in the Python launcher, native scenario
script and README; no backend or Windows runtime changed by this review.

Without the flag, the script retains saved preferences. With it, the script takes
a deep copy of the running native `Settings.DEFAULTS`, retains the configured
backend endpoint and applies the requested character plus the existing text-only
fixture overrides. It saves a complete original deep copy before either branch;
the inherited normal-exit cleanup restores and saves it. `settings_profile` and
`initial_settings` distinguish the two environments. Only step text reaches
`_send_chat`; expectations and this environment flag do not become model instructions.

The added `actual_view` runs after character/avatar readiness and records actual
view settings, camera role, projection, transform and FOV. Initial review found an
unconditional `spatial_camera()` dereference: that method returns null in
orthographic mode. Root corrected it to use the canonical reference camera when
available, otherwise `app.camera`, labeling the latter `root_viewport`. The final
source preserves saved orthographic mode and makes the measured camera explicit.

Validation: two-mode CLI dry-run comparison **3 checks passed**; headless native
assertion suite **10 passed, 0 failed**. After the camera fallback correction,
Godot 4.5.2 Linux `--headless --check-only` parsed the actual external scenario
script successfully (exit 0). No Windows app or model request was launched.
Actual perspective geometry, playback and skill execution remain Windows-run
claims; this review establishes fixture selection, restoration and diagnostic scope.
