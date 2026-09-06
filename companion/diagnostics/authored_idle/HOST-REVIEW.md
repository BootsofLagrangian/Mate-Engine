# Authored idle host review — APPROVED

Reviewed root LivingBehavior scheduler/suspension/profile refresh, main._apply_ambient_idle,
and Fable ControlPanel idle selector. Runtime motion/IK implementation was outside this
independent scope. The reviewer made no runtime edits.

Found a stale attention override when behavior was disabled while attention was active:
the disabled tick returned before refreshing the override. Root corrected the disabled
path to retain explicit foreground/panel attention and clear stale autonomous attention.

Independent dedicated test_host_idle.gd: 21 checks, zero failures after correction.
Reproduction and exact coverage are in diagnostics/behavior/README.md. Current short
character idle actions (3.73–4.33 seconds) fit well inside the scheduler minimum20-second
interval; quiet cooldown does not restart them. Only auto mode permits intermittent
actions. The selector exposes ambient loops, excludes finite actions/walk loops, and
preserves unloaded saved selections rather than silently replacing settings.

Approval is for host ownership, scheduling, and UI consistency only. Authored idle
appearance, blending, and grounded-foot quality require the motion/rendered probes.
