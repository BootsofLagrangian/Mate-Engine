# Initial scene-ground placement review

The bounded admission design preserves world Y and uses the measured all-heading projection envelope to select a nearby XZ point before movement. The geometry helper's matrix validation is reviewed separately by Spatial Review.

Independent review found two integration gaps, now corrected: direct idle adoption lacked furniture collision admission, and the idle observer invoked adoption itself. Both request and idle adoption now reject a normalization segment crossing any vertically overlapping furniture component expanded by the standing radius before actor mutation. The observer waits for Living's own ground latch and records the production initial-placement result, so it cannot conceal a broken automatic hook.

The segment is a disclosed bounded initial placement, not measured authored locomotion. The test observes later local trips separately. A final minor guard was requested before the idle adoption anchor read: require a loaded avatar and available perspective camera, matching request admission, so slow loading cannot read an absent foot anchor.

Final source verdict: **APPROVED** after the availability guard was verified before `_blocked` or anchor access. No further integration blocker found. Actual Windows initial placement, rendering and autonomous movement remain separate acceptance evidence.
