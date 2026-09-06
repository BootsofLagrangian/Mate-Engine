# Grounded placement independent review

Source review by Astra Face, 2026-09-07. Scope: `desktop_object_placement.gd` and the Host ground-readiness, placement and new-instance size changes. No Windows runtime was launched for this review.

**REVISE — one queue readiness mismatch.** A command with `position_m` skips `_tick_command`'s ground wait. If it needs a new object, `_execute_command` still invokes `add_object`, which requires ground regardless of explicit coordinates. A valid startup explicit placement is consequently consumed as `no_space`. Creation must wait consistently, or explicit creation must actually be independent of ground. Existing-target explicit configuration need not wait.

The remaining bounded design is consistent on source inspection:

- Imported furniture vertices, including the workstation chair, form the projection hull. The candidate basis is applied once; component bounds include their mesh transforms before the candidate world transform. Projection uses fixed world Y and a nine-pixel crop allowance.
- The 49 seeds produce bounded candidate proposals, with final distance checked against the original desired position. This is not an exhaustive nearest collision-free placement search. Component AABB exclusion is conservative, not triangle contact physics.
- Ground capture requires a scene-owned foot or attached floor. Perspective-mode, model and drag guards prevent a transient pose or orthographic frame from initializing canonical ground. The cached plane survives pose offsets without following the seated anchor downward.
- The measured source seat clearance affects new-instance defaults only. The bounded ratio is frozen into spatial unit scale, independently of later lens edits; existing instances are not resized by this change.

Owner evidence inspected: `/tmp/ground-placement.log`, 26 checks with zero failures, actual chair/sofa/computer geometry and queued ground readiness; the retained ObjectDB exit warning remains disclosed. The fixture checks source-derived chair size and pose-offset plane retention. It does not establish actual Windows placement, approach, authored entry or visual contact acceptance.

Existing broader command behavior is not newly certified atomic by this review: creation currently publishes/saves an intermediate record before near-placement admission and removes it on failure; optional scale/appearance changes precede later command stages. The new geometry search itself does not mutate rejected candidates.

## Corrected source verdict: APPROVED

The owner added `_command_needs_ground`, which retains pending explicit-coordinate creation until ground is ready. Explicit existing-target or reusable-type positioning remains independent of ground; configuration verbs require a real target at request validation. The existing expiry and user-priority checks still run before readiness waiting. This resolves the concrete blocker above.

Inspected `/tmp/ground-placement-final.log`: 27 checks, zero failures, with the same disclosed exit warning. The additional direct queue fixture exercises the position field; a minor follow-up requested that its temporary verb be `place`, matching accepted explicit-position wire input, rather than `use`. No runtime change is needed for that fixture correction. Approval is for this bounded implementation; production Windows placement and authored entry acceptance remain separate.
