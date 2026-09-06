# Obstacle containment reduction review

**APPROVED**, independent source review by Astra Face, 2026-09-07.

The controller now admits at most 2,048 raw parts, validates their finite nonnegative AABBs, applies the existing vertical filter and actor-radius expansion, then discards only rectangles fully enclosed by an already retained rectangle. Every retained rectangle is an original expanded rectangle; every discarded rectangle remains covered. Thus the blocked X/Z union is unchanged. Sorting by descending area supports reduction without target-specific exceptions or merging gaps between solids. The 96-effective-obstacle limit and grid limit remain enforced before replacing the active navigation map.

Inspected `probe_obstacle_union.gd` and `/tmp/obstacle-union-after.log`: actual imported computer (122 parts) plus chair (34 parts) reduces from 156 raw parts to 26 effective obstacles. The fixture verifies both directions of union containment, and 97 disjoint rectangles still reject with `too_many_effective_obstacles`. The owner reports the existing 4,252-check path suite passing. This review did not launch Windows or rerun that suite.

This fixes the demonstrated raw-part admission failure. It does not by itself establish a reachable computer approach or successful authored interaction in the actual Windows scene.
