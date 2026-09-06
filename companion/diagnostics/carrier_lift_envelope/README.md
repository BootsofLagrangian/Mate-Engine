# Stationary carrier lift/lower envelope

`MotionPlayer.seated_carrier_lift_envelope()` is available after one processed valid carrier frame, including lift zero. It returns 105 avatar-local capsules with `articulation_enclosed: true`, `scope: rig_lift_envelope`, current avatar transform and model identity. It does not set `articulation_frozen`. This admission is for stationary lift/lower only; translated/swivelled carriage uses the separate full-lift rigid snapshot.

The reference captures the actual pre-lift hip, knee and ankle positions and the exact runtime clearance (4% of rest leg length). Upper-body pose and foot orientation remain held by the reviewed carrier owner. Each leg uses the same forward-pole, 2–140 degree, fixed-length two-bone geometry as `LegIK`. Sixteen midpoint samples cover normalized lift [0,1]. Each sampled capsule radius includes a conservative endpoint-motion remainder for its half interval. Queries perform no skeleton, clock, reference or diagnostic writes.

For target vector q(t), vertical target speed c, direction d=q/|q| and clamped reach r, use |d'| <= c/min|q| and |r'| <= c. The knee is d*x+p*h, with x=(u²-l²+r²)/(2r), h=sqrt(u²-x²), and normalized projected forward pole p. Endpoint extrema bound |x|, and the minimum h bounds |h'|. The projected pole derivative is at most 2|d'|; its midpoint norm minus that derivative times the half interval bounds its minimum norm. These give a bound on the knee derivative by the product rule. Near a pole fallback or geometric singularity, the query rejects instead of certifying an envelope. The ankle derivative is c on an unclamped interval, otherwise bounded by |d'|*max(r)+c. Multiplying by half-interval length bounds the distance from the midpoint endpoint. Convex interpolation of the two endpoint errors also bounds the entire capsule centerline. The conservative Gram-matrix scale bound converts margins to avatar-local units.

The five-rig fixture evaluates 483 forward/reverse actual solver phases per rig, including nonaligned phases relative to the 16 intervals. It compares actual capsule endpoints and radii against the containing interval, and checks exact pose, clock and diagnostic preservation. An explicit outward numeric guard of 1e-5 times the maximum posed leg length (transformed conservatively) encloses observed sub-micrometre solver discrepancies; it is recorded as `numeric_guard_m`. The final test requires no positive overflow after this guard. Model/source/reference/floor changes invalidate the owner and both envelope APIs.

Replay:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_carrier_lift_envelope.gd
```

This is a body-volume approximation, not complete garment/hair/mesh collision. Actual fixed-desk intersection and hosted phase admission are separate integration checks. Local query timings do not establish Windows frame-time guarantees.
