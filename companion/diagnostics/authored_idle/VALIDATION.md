# Authored desktop idle acceptance — 2026-09-06

This document preserves the authored-idle milestone. The later direct-UMA walk, concurrent actions and furniture build are recorded in [current validation](../../VALIDATION.md); references below to pending checks or the former CC0 walking owner describe this earlier stage.

This milestone extends the committed stepped-turn baseline (`da294f2f`). It adds
actual local UMA animation to the running desktop pet: one shared quiet standing
base, three selectable source posture clips, and three short entry/loop/exit
behaviors. Character profiles select assets through `ambient_loop` and
`idle_actions`; runtime behavior has no character-specific code branches.

The automatic idle scheduler makes no model calls. Its deadline is at least
20 seconds, or 1.5 times the profile idle interval. User-selected clips and basic
breathing disable automatic profile actions. Speech, microphone input, work,
dragging, preview and navigation retain priority. The idle layer preserves its
phase, transfers head ownership to gaze, and applies normalized hips translation
plus final standing contact IK. Explicit `contact_mode: "foot"` metadata enables
the same translation/contact correction for manual previews.

## Sources and selection

The user-authorized F: tree contains 17,598 common motion files plus character
sets. The bounded extraction copied 32 selected clips and one embedded body rig;
source hashes were unchanged. Seven runtime assets were selected after rendering
and contact tests. Actual character action phase joins differ by at most 0.110°.
The converted skeleton folds animated helper ancestors into humanoid joints and
explicitly corrects FBX units. See [extraction](UMA-EXTRACTION.md) and
[reproduction/runtime contract](UMA-RUNTIME.md).

Overte FBX and 11 public CC0 VRMA candidates were screened as alternatives;
[the initial Overte report](REPORT.md) and [public VRMA report](../vrma_public/REPORT.md)
retain their limited scope. Props and unvalidated seated/locomotion trajectories
were not silently installed as ordinary standing idles. Existing CC0 walking and
stepped 3D foot arcs continue to own desktop movement.

## Verification

- Backend: 131 tests passed, including profile/catalog metadata and contact mode.
- Host policy: independent 21 checks passed, including auto-only scheduling,
  profile refresh, interruption and the disabled-attention latch fix.
- Initial Windows source run: 24 checks passed, 162 own-viewport captures across
  all three characters; RTX 4090 Vulkan/Forward+. Three actual action midpoints
  were visually inspected. This preceded the final head/turn handoff fixes.
- Independent review found and corrected abrupt head ownership switching and
  authored pelvis loss when starting a turn. Final numerical/build/Windows
  results are recorded below once the source is frozen; the initial run is not
  final acceptance evidence.

Reviews: [asset/probe](ASSET-REVIEW.md), [backend](BACKEND-REVIEW.md),
[host](HOST-REVIEW.md), [Fable frontend implementation](FRONTEND-IMPLEMENTATION.md).

## Limits

This is a contact-aware desktop animation layer, not full body physics. Only hips
translation is consumed; other joints retain target bone lengths. IK intentionally
changes the source legs, so exact source world trajectories are not claimed.
Character actions are authored finite clips; head/gaze transition tests do not
establish that every animation or every interruption has human-like acceleration.
Raw source assets, converted binaries and derived avatar images remain local.
