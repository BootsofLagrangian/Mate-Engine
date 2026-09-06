# Native skill registry and furniture calls, version 1

`world_context` advertises installed capabilities alongside its named interests. `furniture_schema_version` is 1 (default); `furniture_catalog` contains at most eight descriptors. New native object types require a descriptor and executor, not backend character/type branches. Legacy `furniture_types` remains compatible for chair/sofa/computer only. Omission disables furniture calls. Existing 45-second TTL, revision invalidation, selection/reset/reconnect isolation and action/done deduplication apply.

```json
{"version":1,"id":"computer","verbs":["place","use","configure","inspect","hide","remove"],"sockets":["seat","keyboard_left","keyboard_right"],"appearances":["default","warm","cool","porcelain"],"bounds":{"scale":[0.5,1.8],"yaw_deg":[-180,180]},"perception":{"mode":"geometry_only","available":true,"reachable":"unknown","reason":"native_geometry"}}
```

Descriptors require id/verbs/sockets/appearances/bounds; version and perception have compatible defaults. IDs are lowercase identifiers of at most 40 characters, lists are bounded and distinct, bounds cannot exceed the global safe ranges shown. Available=false rejects invocation. Reachability is unknown/yes/no; it is a host-reported assessment, not inferred from registry presence. Native live validation remains authoritative even when advertised reachable=yes. Only geometry is perceived: no screenshot, screen-content interpretation or VLM inference is claimed.

A response contains at most one skill invocation in its optional intent:

```json
{"kind":"furniture","object_type":"computer","verb":"use","placement":"near"}
```

The type and verb must be advertised. Supported verb vocabulary is place/sit/use/inspect/configure/appearance/hide/remove; each type advertises only implemented verbs. The host ensures/reuses or creates suitable furniture, safely places it, and performs the requested interaction. No manual setup is required for a computer-use request. Optional target_id must identify a currently listed prop; configure/appearance/hide/remove require it. Configure requires at least one scale/yaw_deg/appearance change and prohibits placement, so an appearance edit cannot silently relocate an object. Appearance requires an advertised preset. Hide/remove reject configuration fields. Extra fields reject the entire intent.

Scale and yaw_deg must be finite non-boolean numbers inside descriptor bounds. Appearance is an allowlisted preset ID, never shader source, arbitrary material files or executable code. Native presets may internally use materials/shaders; backend does not interpret or construct them. Omit configuration parameters normally to preserve native physical sizing and authored appearance.

## Spatial frames and semantic anchors

- Placement near/left/right is relative to the pet on the current usable desktop support. The native controller resolves it into actual usable-workarea geometry, respecting negative monitor origins and its established Godot coordinate normalization. Version 1 intentionally exposes no model-authored pixel coordinates or normalized numeric positions.
- Physical scene translations and contact distances use world metres; object sockets are named object-local 3D coordinates transformed into that shared scene. Center/base/seat/keyboard/contact anchors are semantic roles, not interchangeable origins. The executor resolves a verb to its required named sockets and reports missing/unreachable geometry.
- `yaw_deg` rotates the object about world up. Camera viewing yaw/pitch is a separate presentation transform and is not controlled by this object-angle field. The model cannot change the camera through this schema.
- Native window placement, object world transforms and camera projection meet at the existing host geometry boundary. Speech is acknowledged first; execution uses the live controller, not a model claim about reaching coordinates.

## Execution feedback

Native reports a terminal result using `intent_result` with `character_id`, `intent_id` (`<turn_id>:intent`), `outcome` and optional symbolic `reason`. Outcomes are completed/arrived/rejected/failed/cancelled/expired/interrupted; reason is at most 64 lowercase letters/underscores. No private geometry or freeform instructions are accepted. Backend accepts only IDs actually issued to that connection/character within 120 seconds, accepts one terminal result per ID, and keeps the last eight reports for the next ordinary model turn. Reset/selection/reconnect clears them. Duplicate reports are acknowledged without adding another history item. This feedback triggers no automatic model call.

The model emits Japanese acknowledgement with text first and must not claim creation, contact or arrival succeeded before feedback. Capacity, placement, live object type, support/contact feasibility, cancellation and finite interaction duration remain native responsibilities. Background job turns receive no furniture capability. Tests cover empty-world ensure requests, generic nonbuiltin descriptors, configuration bounds, early streaming, action/done parity, in-flight capability revocation, reset/character isolation, and issued/deduplicated feedback. Real-model invocation and native execution require separate integration validation.

Typed prop interests may additionally include `object_type`, supplied by the native store. It is permitted only for kind=prop and must match an advertised capability. The normalizer rejects a call whose type contradicts that target. Untyped legacy interests remain accepted, but are not used for typed configuration examples. Live prompt examples contain only current target IDs; a configuration example is emitted only for an actual typed prop with an available compatible configure skill, scalar values within its bounds and a listed appearance preset. Object-type guessing from labels is not authoritative and is never used to construct these examples.

## Additive spatial, locomotion, and costume capabilities

`world_context.furniture_catalog` may advertise per-type
`spatial:{frame:"desktop_scene_v1",bounds:{x:[-20,20],y:[-20,20],z:[-20,20]}}`.
Only advertised capabilities permit `position_m:{x,y,z}` in furniture `place` or
`configure`; every axis must be finite, nonboolean, and within advertised bounds.
`configure` still requires a known prop target. `position_m` and semantic
`placement` are mutually exclusive. No default near-placement is inserted for an
explicit position. The frame is right-handed world metres: +X right, +Y up, +Z
back, origin at the fixed virtual-camera orbit target for the selected workarea.
It does not follow the pet's OS window. Native advertises this capability only
when its perspective setter is available. Storage bounds are not an assurance of
reachability: live camera, workarea, clipping, and contact checks remain native.
Scale is object size, never a substitute for distance; camera view and object yaw
remain separate.

`world_context.locomotion_catalog` contains at most 32 loaded, registered
locomotion capabilities `{id,description?}`. IDs match
`[a-z0-9][a-z0-9_-]{0,31}`; descriptions are printable data up to 240 characters.
Only `move_to` may add `locomotion_id`, copied exactly from that catalog. Omission
retains normal gait selection; arbitrary gestures cannot become locomotion.
Withdrawal changes the context revision and revokes in-flight requests.

`world_context.appearance_supported` is a strict boolean, default false.
Optional `active_variant_id` defaults to `default`; when supported it must be an
installed variant of the selected server profile. The server derives costume
capabilities and labels from that profile, never client URLs or model paths.
The optional reply is exactly
`intent:{kind:"change_appearance",variant_id:"<installed id>"}`. Its prompt includes
the active variant. Costume changes preserve character/session/history identity.
Native deduplicates `<turn>:intent`, uses the same safe variant loader as the UI,
and reports completed only after the new model actually loads. Existing terminal
`intent_result` feedback applies. No automatic model invocation follows feedback.

All three additions share the existing 45-second context TTL, unchanged-heartbeat
revision behavior, character/reset clearing, and action/done metadata parity.
`GET /characters/{id}/avatar?variant={id}` serves only the profile-resolved asset;
unknown or missing variants return 404 rather than the base costume. Omitting the
query retains the existing default route. Package appearance abilities are derived
from validated variants; their declaration alone does not enable native execution.

### Issued action versus final turn metadata

The sender checks current context before the first action is delivered. Once an
intent has actually been issued on that connection, a successful `done` repeats
that exact request with `intent_replay:true`, even if its execution changed the
world revision while TTS was finishing. This is historical action metadata, not a
new execution or completion claim. Native deduplicates the unchanged
`<turn_id>:intent`. An intent rejected before first delivery cannot be resurrected
by `done`; reset, character change, cancellation and supersession still revoke it.
Actual completion remains the separately validated `intent_result` outcome.
