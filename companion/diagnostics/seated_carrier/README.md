# Seated support carrier: additive foot policy

This is an explicitly **procedural additive clearance policy**, not an acquired chair-pull or foot-powered rolling motion. It retains the installed authored seated pose and adds vertical ankle targets through the existing bounded LegIK, preserving each source foot's global basis. Clearance is 4% of target leg length. The pelvis and all non-leg bones remain unchanged by the helper.

## Host contract

- `set_seated_carrier(lift_weight, yaw_world) -> bool`: only valid in seated contact, without preview/custom/finite seated transition, and with valid floor/reference data. Host supplies eased 0→1 and 1→0 ramps (tested 0.6 s) and continuous chair yaw. A single yaw change exceeding 12° is rejected. The exercised native avatar parent has identity orientation; the API currently writes local avatar yaw and is not certified for arbitrary rotated parents.
- `seated_carrier_state()`: `active`, `lift`, `ready`, `limited`, `clearance_local`, `min_gap_local`, `reach_error_local`, and `world_plant_claimed:false`. A changed lift invalidates readiness until Motion processes the pose; repeating the same lift permits polling the latest processed readiness. Host must wait for readiness before moving the chair and stop support movement before lowering.
- `clear_seated_carrier()`: use after controlled lowering. Contact release, reset, model replacement, preview/custom activation, lost floor/reference or finite transition clears ownership. Host must stop its physical carrier movement when ownership is lost.

The active helper owns seated body yaw, so normal facing pursuit does not fight chair orientation. It does not move the chair, root position, hands or furniture. Foot diagnostics explicitly mark the lack of a planted-world-foot claim during carrying.

## Evidence and limits

`probe_seated_carrier.gd` follows the actual authored entry before 0.6 s lift, 0.3 m carrier translation plus 90° yaw, and lowering. The five rigs are Cheval, Rice, Eishin, Mambo and Hachimi. Original nominal evidence is `nominal.json`; independent final source validation is in [the independent review](../authored_foot_contacts/CARRIER-REVIEW.md) and its adjacent `review-carrier.*` artifacts.

- Full actual foot-influenced geometry minimum while carried: 27–30 mm on normal rigs, approximately 7.8 mm on minis.
- Local pelvis movement caused by the helper: zero.
- Maximum measured LegIK reach error: 0.166 mm.
- Lowered release marker displacement: below 0.003 mm.
- Independent checks cover the leg-only affected-bone mask, source foot basis, invalid requests, readiness invalidation, ownership loss, reset and facing control.

The initial direct-seated-pose fixture incorrectly bypassed production entry/floor alignment on Mambo and failed; `direct-seat-rejected.*` is preserved. Final tests execute the authored entry rather than changing a floor tolerance.

The inspected 150-frame Linux Cheval sequence and contact sheet are retained under `companion/logs/diagnostic-traces/seated_carrier/render/`, with `render-provenance.json` hashes. It shows modest knee flexion and shoe clearance during support movement, then a gradual return. The rendered seat is a simplified slab. **Actual computer desk/body collision, occupied swivel sweep, host readiness timing, Windows rendering and frame intervals are outside this helper approval.** The empty-chair planner alone cannot establish those properties.

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_seated_carrier.gd
DISPLAY=:0 MOTION_RENDER_DIR=/tmp/seated-carrier-render WALK_CHARACTER=cheval-grand companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script res://tools/render_seated_carrier.gd
```

No acquired source in the current bounded inventory establishes chair pulling or seated foot-powered rolling. UMA01's hand reach toward the seat is not proof of a hand-pull contact.
