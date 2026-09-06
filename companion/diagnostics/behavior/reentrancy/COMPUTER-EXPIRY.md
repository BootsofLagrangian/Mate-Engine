# Separate cause of the computer approach expiry

Read-only analysis of the preserved actual Windows run `logs/text-scenario-computer-bilingual-ko-01/report.json` identifies legacy 2D approach starvation, distinct from the reentrant terminal-delivery bug.

The model issued `computer/use` correctly at 8.512 s. Voice was no longer active by 10.852 s. At 18.635 s the pet had attached to the floor and ObjectsHost entered `approaching`, with internal request `object-use:obj_2:19564`. From 22.385 s through 48.434 s, all 105 retained contexts show native state `rest`, attached floor support, no blocking/foreground/speech/pointer flag, the same window position, and the same `approaching` interaction. Expiry followed at 48.449 s.

Current Living code sets `furniture_busy` for every nonempty interaction, then requires `not furniture_busy` to expose `can_move` to Director. The legacy furniture approach itself queues a Director move while its interaction remains nonempty. That move therefore cannot dispatch and exhausts its 30-second freshness budget. It never reaches facing or seated contact admission. The owner was asked to exempt only the matching internal legacy approach, preserving arbitration against unrelated movement. No Living/Objects changes were made by this reviewer.
