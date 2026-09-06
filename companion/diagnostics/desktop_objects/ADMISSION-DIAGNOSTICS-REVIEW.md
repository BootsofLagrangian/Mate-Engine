# Admission diagnostic review

APPROVED. Independent source comparison found the original seat-admission predicates, order, short-circuit behavior and numeric thresholds preserved. Named early returns only record diagnostic state. The wrong-pose path records a fresh reason. ObjectsHost captures the seat record before clearing interaction ownership and deep-copies rejected spatial projection data before rollback overwrites the live projection record.

Independently reran `test_seat_admission_diagnostics.gd`: **38 passed, zero failed**. This approves the diagnostic instrumentation, not a fix for computer admission. The next actual Windows record is needed to identify its failing predicate.

Interpretation caveat: the `no_space` aggregate contains last-creation, last-placement and last-position-rejection records. A subpath not executed for the current command can leave a historical subrecord. Associate the placement/candidate object IDs and current reason rather than assuming every nested record belongs to the current command. The exact seat failure record is captured at rejection.
