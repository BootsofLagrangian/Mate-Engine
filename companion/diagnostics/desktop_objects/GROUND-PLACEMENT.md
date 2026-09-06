# Grounded furniture placement

Semantic perspective placement requires an attached floor or an admitted scene-foot latch. A transient ungrounded startup/speaking pose cannot define world Y. Pending commands retain their existing 30-second freshness budget while waiting. Already-grounded commands can still overlap their own reply. The captured model-specific ground plane survives contact pose changes and resets on character/model change or explicit pet drag.

The planner uses actual imported furniture geometry, including the workstation chair, and its exact convex hull under the instance rotation/physical scale. It reuses the reviewed projection halfplane solver at fixed world Y, reserving nine pixels for the native crop border and integer rounding. A bounded set of 49 X/Z seeds considers both sides and inward depth; the nearest admitted candidate among these proposals is chosen within the distance limit. This is a bounded search, not a global optimum or general physics simulation. Actual component AABBs cannot overlap other visible objects or the standing actor.

New furniture defaults use the authored entry clip's measured `source_seat_clearance_local` divided by the asset's seat-to-ground height (bounded 0.75–1.25). Physical perspective unit scale retains that ratio. Existing instances and user-resized heights are unchanged.

Focused verification: actual chair, sofa, and computer+chair geometry; projected crop fit; exact fixed Y; inward Z; blocked solid volume; pending ungrounded command without mutation; one dispatch after floor readiness; plane retention after pose offset; drag reset; actual clip-derived default height. `probe_ground_placement.gd`: 27 checks, zero failures. `test_commands.gd`: 31/0. Windows use/seating acceptance remains separate.
