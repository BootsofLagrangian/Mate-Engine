# Moving workstation chair source review

Independent review by Astra Face, 2026-09-07. Scope: ContactScene chair setup API, declared premium capability and `desktop_workstation_setup.gd`; host animation/carrier integration is excluded.

**REVISE — returned sweep envelope.** Collision checks merge previous/current transformed component boxes and add a conservative angular sagitta. However, `setup_bounds_local` initially merged only sampled scene bounds. It can omit intermediate rotation extrema. Merge the conservative swept boxes into the returned envelope so host full-path view fitting can cover the same continuous trajectory. Per-sample fit callbacks alone do not prove intermediate crop coverage.

Other inspected mechanics are consistent: chair mesh, seat anchor and facing share one transform; desk and keyboard sockets remain fixed. Geometry queries follow the new chair transform. Planning starts from an undisplaced setup and restores that setup on normal success/failure returns. Sweeps cover translation followed by rotation, check actor and other solids without target exemptions, and derive subsequent approach from the actual changed seat and source trajectory. Scene transforms are assumed to follow the existing upright uniform-scale furniture contract.

Inspected owner `/tmp/workstation-setup-test.log`: 35 checks, zero failures across three actual rigs, with the retained exit warning. Successful candidates use 0.1 local metre pullout and -125 degree swivel, plus admitted authored approach factors. These results do not establish animated chair handling, seated-avatar clearance during turn/roll-in, hands pulling furniture, or actual Windows visual acceptance. Roughly 440 ms planning is recorded rather than described as frame-safe.

## Corrected planner verdict: APPROVED

The returned bounds now include every conservative swept component box, including angular padding. The two-argument fit callback receives that accumulated envelope, closing the continuous-view-coverage gap. `setup_parts_local` conservatively merges each component's sweep and includes stationary furniture.

Reviewed the new pure `reposition` helper: it submits the envelope's eight corners and complete swept/stationary parts to the existing fixed-Y placement search, with scene world basis and actor/other obstacles. It returns a proposal without mutating furniture. The caller must still admit/commit transactionally and run a fresh plan from the new location; the helper documents that contract. Merged sweep bounds are conservative and may reject otherwise feasible arrangements.

Inspected the updated owner log: 44 checks, zero failures, including intermediate actual-vertex envelope coverage and no-mutation/fixed-Y reposition checks. This approval remains limited to the empty-chair planner and geometry API. Occupied-body clearance, carrier lifecycle and Windows choreography require their separate reviews.

## Final sweep/loader and restore-clearance additions

**APPROVED**, bounded source scope. The carrier helper's quaternion shortest-path sweep now matches Host shortest-angle interpolation. Four centerline endpoints plus angular sagitta conservatively enclose each rigid capsule segment; expanded oriented-box SAT retains desk solids while excluding only the carried chair support. Stationary articulation envelopes are accepted only without support movement. This is the declared rig-volume approximation, not a full skin/garment enclosure.

Computer Window loading uses the same ContactScene assembly, updates socket/vertex/camera fitting after chair pose or scale changes, and preserves fixed desk/keyboard geometry. Inspected final owner logs: native window 87/0; synthetic sweep geometry 17/0; production planner-selected three-rig carry/lift/hand fixture zero failures (`/tmp/occupied-planner-final.log`, largest listed hand error about 7.45e-8 m). No Windows full-cycle result is inferred.

Reviewed `find_restore_clearance`: it builds navigation from all current furniture/other solids at the exact start Y, searches bounded 0.05 m rings with 16 directions, checks target and route view callbacks at no more than 0.025 m spacing, and requires both actual swivel and roll sweeps to clear the proposed standing actor. Temporary chair changes are restored on successful and unsuccessful paths; the navigation map is disposed. Returned navigation geometry allows the Host to validate the same resolution rather than substitute an incompatible coarse map. Maximum distance bounds the endpoint offset, not necessarily total routed distance. The caller still owns real movement and lifecycle.

Inspected `/tmp/workstation-restore-clearance-fine.log`: 68 checks, zero failures, retained exit warning. `/tmp/recorded-restore-clearance-final.log` reproduces the recorded actor/chair obstruction and admits a 0.10 m step; its explicit scope excludes other objects and camera. These results approve the geometric proposal helper, not a production step-away execution or visual animation.

## Runtime projection-envelope alignment: APPROVED

The paired Host/reposition correction uses runtime world-axis AABB corners consistently. `reposition` constructs the basis-transformed envelope at zero translation and inverse-basis maps its corners into the placement solver's input frame. The solver then reapplies the original basis, yielding exactly those world-axis offsets at each candidate translation. Collision parts and fixed-Y policy are unchanged.

Inspected `/tmp/product-setup-view-fixed.log`: the earlier local-corner pass/runtime-world-box failure is reproduced from the recorded target plus current installed calibration; aligned admission rejects it, a bounded 0.285770 m fixed-Y proposal yields a fresh accepted plan, and 62 sampled runtime phase bounds fit. The Host's separate actual-asset six-check regression was independently rerun successfully. This is source/fixture approval; actual fresh-product LM completion remains separate.

## Combined actor approach admission: APPROVED for correctness

The planner now validates the actual staging path, retains its grid descriptor, and places the target all-heading actor hull into the same local frame as the furniture envelope. Repositioning projects that combined envelope while retaining the original physical furniture collision parts. Candidate proposals are deduplicated and sorted by distance; only physically filtered candidates invoke the full fresh-plan callback. The callback restores temporary scene position, and Host commit still runs a new plan with rollback on failure. A different freshly selected staging route must pass its own view check, so translated geometry from an earlier candidate cannot serve as final route proof.

Inspected `/tmp/product-approach-view-final.log`: old route rejected, six candidates validated, fixed-Y 0.146316 m furniture reposition accepted, full rebuilt route and 62 setup poses fit. Fixture entry bounds also fit, explicitly scoped to that fixture's outgoing pose. The preceding existing initial-ground correction was 0.093198 m and is recorded separately; it is not hidden inside furniture placement.

The recorded candidate search costs approximately **2.45 seconds synchronously**. This approval establishes admission correctness, not frame-safe planning or uninterrupted animation during that cost. Actual Windows future entry pose and strict timing acceptance remain unproven by this fixture.
