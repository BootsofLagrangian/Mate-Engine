# Declarative desktop-object skills

`DesktopObjectsHost.furniture_catalog()` advertises only installed native furniture capabilities. Each version-1 descriptor contains `id`, allowed `verbs`, named local-3D `sockets`, `appearances`, scale/yaw `bounds`, and `perception: {mode: geometry_only, available: true, reason: native_geometry, reachable: unknown}`. Geometry availability does not imply reachable placement or screen-content recognition.

An existing conversation may emit `intent: {kind: furniture, object_type, verb, target_id?, placement?, scale?, yaw_deg?, appearance?}`. LivingBehavior routes the same validated path used by local requests. `place`, `sit`, `use`, and `inspect` can ensure an existing compatible object or create one; `configure`, `appearance`, `hide`, and `remove` require an exact current `object:obj_N` target. Sit supports chairs/sofas; use supports the computer. Configure changes only requested fields, preserving placement. No arbitrary scripts, paths, pixels, textures, or shader code are accepted.

`placement` is `near`, `left`, or `right` relative to the pet, bounded to a usable desktop workarea and its current support height. A command may fail when no safe same-support approach exists. Scale is 0.5–1.8. Yaw is −180°–180° about world up, independent of camera orbit. The store persists yaw and appearance alongside stable instance IDs. Presets are:

- `default`: original authored materials.
- `warm` / `cool`: duplicated authored materials with a bounded color tint, preserving textures and roughness.
- `porcelain`: smooth ivory replacement material.
- `flat`: unshaded material using authored color and textures.

The single pending-command slot has 30-second freshness, character identity, bounded 128-ID dedup history, and user-over-model priority. It waits for speech, microphone, foreground work, preview, and dialogue hold to clear. Drag, explicit stop, switch, disconnect, and failed/cancelled originating turns invalidate it. Once dispatched, the existing 65-second bounded interaction lifecycle controls approach and contact; computer use completes after ten seconds. A second action/done carrying the same ID cannot recreate or replay an object operation.

`command_finished(id, outcome)` and the capped `command_outcomes` log describe actual native outcomes. Living sends bounded `intent_result` feedback for issued model intents; backend retains it for a later user turn. Feedback never starts another model request and contains no private desktop geometry. A seated arrival is reported once the exact owned seat is attached; work completes only after its finite contact interval.

# Camera and occupied presentation

`refresh_view()` updates standalone camera orientation and zoom, and recomputes shared geometry using camera depth (`DesktopView`), not a fixed world-Z plane. Shared prop and avatar use the same world and depth buffer. An already occupied seat can retain contact while the side panel is open or the camera changes, provided the full arrangement fits the viewport/workarea and exact owned-seat reprojection remains safe. Otherwise the host reports an explicit failure and releases contact. Preparatory movement remains interrupted by an opened panel. `occupied_rect()` returns the combined local projected extent for panel placement.

`DesktopAutonomy.refresh_seat_projection` is limited to the currently owned seated surface, requires seat/pelvis screen coincidence, checks full visible-body workarea bounds, and never moves the OS window. It cannot acquire unrelated furniture or bypass navigation safety. Standalone windows keep a canonical imported-geometry reference pixels/metre multiplied only by object scale and view zoom. Rotation changes the native viewport dimensions rather than magnification. Full native rectangles are clamped to usable workareas; dragging converts the dynamic frame back to its persisted centre/floor anchor. After native creation, the host reasserts the owned window’s transparent compositor flag; actual Windows alpha remains a separately measured acceptance item.

# Verification scope

`test_commands.gd`: 24 semantic checks covering ensure/reuse, action/done dedup, speech deferral, cancellation, expiry, active/queued Director user priority (including dispatch-time revalidation), character switch, exact-target validation, configuration and JSON persistence. Its interaction entry is stubbed; it does not prove rendered seating.

`test_view_objects.gd`: 70 checks with actual imported geometry over three camera yaws and three object yaws per type, material restoration/no cumulative tint, fixed physical pixels/metre across camera/object yaw, linear zoom scaling, and bounded owned-seat reprojection. Existing host/store/projection checks remain separate. Actual Windows skill execution, post-draw contact, and camera screenshots are root-owned acceptance evidence.

`diagnostics/behavior/test_default_roaming.gd` simulates sixteen minutes with only native support endpoints: six intermittent local walks, minimum gap 127 seconds, without a client or model. The existing defaults (`autonomy_enabled`, `surface_roam`, `behavior_enabled` true and `idle_clip` auto) provide this behavior without manual interest points; explicit user preferences are preserved.

Forced pre-chat world publication refreshes live targets synchronously after connection/selection guards. `diagnostics/behavior/test_forced_world.gd` passes five checks from a stale empty Director with actual live floor endpoints, including no duplicate revision on the next unchanged tick. This prevents a delayed local target refresh from invalidating an otherwise valid model action immediately after the request begins.
