# Legacy callback isolation

APPROVED for the bounded source change. The actual regression reproduces a legacy state notification cancelling scene-owned heading after initial travel, followed by timeout. Main's named state handler now skips only motion cleanup while scene navigation owns the foot; label and ordinary support handling remain. Legacy locomotion and both main/Living frame-displacement handlers likewise defer to that explicit owner, then resume after release.

The adapter still computes its own committed world displacement and updates its crop/pose. No travel timeout was relaxed. Camera unprojection during release is guarded by instance/tree availability so teardown does not query a removed camera.

The implementation owner's retained before log has five failures including revoked heading and no arrival; the corrected actual-rig fixture reports 274 checks and zero failures, including injected legacy notifications and an imported multi-part chair route. The fixture retains an ObjectDB exit warning. This review approves callback ownership; it does not establish actual Windows visual quality or the full authored seating sequence.
