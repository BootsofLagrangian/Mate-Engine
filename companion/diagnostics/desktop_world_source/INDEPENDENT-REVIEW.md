# Independent snapshot-reader review

2026-09-06 — **APPROVED for the bounded reader fix.** Reviewed source diff and the 11-case focused fixture. Invalid/unreadable publications retain the last valid geometry without refreshing its source timestamp; missing files now expire it after the same five-second deadline. New valid empty-window snapshots apply immediately. Recovery and no repeated detach notification are covered; dead-child and stop behavior are unchanged. This addresses transient read failures without treating malformed transport as immediate evidence of disappeared surfaces. No Windows execution or source edits by reviewer.

Separately reviewed the object probe's approach metric change: global projected foot-anchor displacement removes inflation from transparent-window reframing. Its label should remain visible anchor displacement, since yaw/pivot changes can contribute; it is not a reconstructed traveled path length.
