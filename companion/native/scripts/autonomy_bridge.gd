class_name AutonomyBridge
extends RefCounted
## Host-side policy between DesktopAutonomy (window movement, Astra-owned) and the rest of the
## pet (session, microphone, audio, motion, panel). Pure logic so it runs headless:
##   * when roaming must be blocked (panel open, recording, speaking, dragging, live dialogue),
##   * whether the pointer is "near" the pet,
##   * which locomotion presentation to use (imported walk VRMA loop vs. a gentle float),
##   * which ambient idle clip may be used without overriding interaction/IK gestures,
##   * readable Korean state labels,
##   * window-position persistence that accepts negative global monitor origins.
## It never reads the screen: the only perception input is the host's observe_interest hook.

const STATE_LABELS := {
	"walk": "산책 중",
	"inspect": "살펴보는 중",
	"rest": "쉬는 중",
	"settle": "잠시 대기",
	"paused": "일시정지",
	"no_space": "공간 부족",
	"approach": "자리로 이동 중",
	"no_surface": "닿을 표면 없음",
}
## Pet size (avatar node scale). 0.6 is a small desktop pet; 1.25 still fits the window height.
const SCALE_MIN := 0.35
const SCALE_MAX := 1.25
const SCALE_DEFAULT := 0.6
const SCALE_WHEEL_STEP := 0.05
## Unity AvatarScaleController smoothing: factor 0.1 per 60 Hz frame.
const SCALE_SMOOTH_FACTOR := 0.1
## Window pixels kept free below the standing foot pivot and above the head at SCALE_MAX.
const FOOT_MARGIN_PX := 40.0
const HEAD_MARGIN_PX := 30.0
## Sit needs this imported loop (MotionPlayer.start_contact_pose plays it).
const SIT_CLIP := "sit_idle"
const POINTER_NEAR_MARGIN := 40.0
## Roaming stays paused this long after the last dialogue activity so the pet does not wander off
## the moment its reply ends; DesktopAutonomy adds its own 2.5 s settle on top.
const DIALOGUE_HOLD := 6.0
## Imported clips that may drive locomotion, in preference order (manifest names).
const WALK_CLIPS: Array[String] = ["walk", "walk_formal"]
## Autonomy speed (px/s) at which the walk clip plays at 1x.
const REFERENCE_SPEED := 75.0
const WALK_SPEED_RANGE := Vector2(0.6, 1.6)
## Idle loops the ambient policy may pick automatically (manifest names).
const AMBIENT_IDLE_CLIPS: Array[String] = ["idle_natural"]
## Float bob for the no-walk-clip fallback (metres, seconds): small enough that the hit rect and
## passthrough polygon barely change.
const FLOAT_AMPLITUDE := 0.012
const FLOAT_PERIOD := 1.7
## Restoring a saved window position requires this much of the window inside some monitor.
const RESTORE_INSET := 40

var _dialogue_until := -INF


## Record dialogue activity (chat sent, utterance sent, server turn events, gesture from LLM).
func note_dialogue(now: float) -> void:
	_dialogue_until = now + DIALOGUE_HOLD


func dialogue_holding(now: float) -> bool:
	return now < _dialogue_until


## Context for DesktopAutonomy.update_context(). Every field true blocks movement immediately.
## conversation "active" = generating, audibly playing, any non-idle activity, or the hold window.
## hold: host-side block (the pet is seated on a surface): the module keeps its contact but never
## chooses a new target, so sitting pauses auto-walk until the user stands the pet up.
func context(panel_open: bool, recording: bool, speaking: bool, dragging: bool,
		activity: String, generating: bool, playing: bool, now: float, hold: bool = false) -> Dictionary:
	var conversation := generating or playing or activity != "idle" or dialogue_holding(now)
	return {
		"panel_open": panel_open,
		"listening": recording or activity == "listening",
		"speaking": speaking or activity == "speaking",
		"dragging": dragging,
		"foreground_busy": conversation or hold,
	}


static func is_blocked(ctx: Dictionary) -> bool:
	for key in ["panel_open", "listening", "speaking", "dragging", "foreground_busy"]:
		if bool(ctx.get(key, false)):
			return true
	return false


## Pointer "near" the interactive pet: inside the grown pet rect or over the handle, or dragging.
static func pointer_near(mouse_local: Vector2, pet_rect: Rect2, handle_rect: Rect2, dragging: bool, was_near: bool = false) -> bool:
	if dragging:
		return true
	if not mouse_local.is_finite():
		return false
	# Authored poses change the visible silhouette even with planted feet.
	# Exit farther away so stopping a walk cannot immediately clear its hover.
	var exit_extra := 24.0 if was_near else 0.0
	if pet_rect.grow(POINTER_NEAR_MARGIN + exit_extra).has_point(mouse_local):
		return true
	return handle_rect.has_area() and handle_rect.grow(POINTER_NEAR_MARGIN * 0.5 + exit_extra).has_point(mouse_local)


static func state_label(state: String, enabled: bool, panel_open: bool, sitting: bool = false) -> String:
	if not enabled:
		return "꺼짐"
	if sitting:
		return "앉아 있음" if state != "approach" else "앉을 자리로 이동 중"
	if panel_open and state != "no_space" and state != "no_surface":
		return "패널 열림 · 정지"
	return str(STATE_LABELS.get(state, state))


## Surface-mode status line. The world source only reports window/monitor rectangles (never
## contents); this label says so and never claims perception.
static func surface_status(surface_roam: bool, os_name: String, source_available: bool,
		source_error: String, snapshot: Dictionary) -> String:
	if not surface_roam:
		return "표면 걷기 꺼짐 · 자유 이동"
	if os_name != "Windows":
		return "표면 걷기: 작업 표시줄 바닥만 (창 위치 읽기는 Windows 전용)"
	if source_available:
		var windows: int = snapshot.get("windows", []).size()
		var monitors: int = snapshot.get("monitors", []).size()
		return "표면 걷기: 창 %d개 · 모니터 %d개 (위치만 읽음, 내용 인식 없음)" % [windows, monitors]
	var why := source_error if not source_error.is_empty() else "도우미 대기 중"
	return "표면 걷기: 창 위치 없음 · 바닥만 (%s)" % why


## Highest-priority declared locomotion clip, with stable name ordering on ties.
## Older catalogues retain their known walk fallbacks.
static func pick_walk_clip(loaded_clips: Dictionary) -> String:
	var selected := ""
	var priority := -1
	var names := loaded_clips.keys()
	names.sort()
	for name in names:
		var entry: Variant = loaded_clips[name]
		if not entry is Dictionary or not bool(entry.get("locomotion", false)) or not bool(entry.get("loop", false)):
			continue
		var candidate := int(entry.get("locomotion_priority", 0))
		if candidate > priority:
			selected = str(name)
			priority = candidate
	if not selected.is_empty():
		return selected
	for name in WALK_CLIPS:
		if loaded_clips.has(name):
			return name
	return ""


## Locomotion presentation for a locomotion_changed(moving, velocity) signal.
##   {action: "walk", clip, speed}  -> play the imported walk loop (host starts it once; the
##                                    speed is derived from the configured autonomy speed, not the
##                                    per-frame velocity, so the clip is never restarted mid-stride)
##   {action: "float"}              -> no walk clip: gentle vertical float, legs stay in idle
##                                    (never a gliding walk pose)
##   {action: "stop"}               -> movement ended: stop the walk loop we started / end float
##   {action: "none"}               -> keep whatever dialogue gesture owns the body
## grounded=false (surface mode "approach": re-seating toward a support) never walks: the module
## glides the window, the body floats/idles. sitting=true: the seated body neither walks nor bobs.
static func locomotion_plan(moving: bool, loaded_clips: Dictionary, dialogue_gesture_active: bool,
		autonomy_speed: float, grounded: bool = true, sitting: bool = false) -> Dictionary:
	if not moving:
		return {"action": "stop"}
	if dialogue_gesture_active or sitting:
		return {"action": "none"}
	var clip := pick_walk_clip(loaded_clips)
	if clip.is_empty() or not grounded:
		return {"action": "float"}
	var speed := clampf(autonomy_speed / REFERENCE_SPEED, WALK_SPEED_RANGE.x, WALK_SPEED_RANGE.y)
	return {"action": "walk", "clip": clip, "speed": speed}


## Grounded walking is only claimed in surface mode while the module reports state "walk" with an
## attached support; free roaming (surface mode off) keeps its previous walk presentation.
static func grounded(surface_mode: bool, state: String, contact: Dictionary) -> bool:
	if not surface_mode:
		return true
	return state == "walk" and bool(contact.get("attached", false))


## Velocity handed to MotionPlayer.set_locomotion_direction: face the travel direction only while
## actually walking; a glide (approach), a stop or a seated pose returns to the front. Facing never
## touches gestures, so speech gestures are not overridden.
static func facing_velocity(moving: bool, grounded_walk: bool, sitting: bool, velocity: Vector2) -> Vector2:
	if not moving or not grounded_walk or sitting or not velocity.is_finite():
		return Vector2.ZERO
	return velocity


## Manual sit is offered only on an attached support with the sit loop imported; standing up is
## always allowed while seated.
static func can_sit(surface_mode: bool, contact: Dictionary, has_sit_clip: bool, sitting: bool) -> bool:
	if sitting:
		return true
	return surface_mode and has_sit_clip and bool(contact.get("attached", false))


# ----------------------------------------------------------------- pet scale / framing

static func clamp_scale(value: float) -> float:
	return clampf(value, SCALE_MIN, SCALE_MAX) if is_finite(value) else SCALE_DEFAULT


## Mouse wheel over the pet: one notch = SCALE_WHEEL_STEP, bounded. Ignored while dragging or
## while the pointer is over the panel (the panel consumes its own wheel events).
static func wheel_scale(target: float, notches: int, dragging: bool, over_pet: bool) -> float:
	if dragging or not over_pet or notches == 0:
		return target
	return clamp_scale(snappedf(target + notches * SCALE_WHEEL_STEP, 0.01))


## Exponential smoothing toward the target (frame-rate independent form of the Unity lerp).
static func smooth_scale(current: float, target: float, delta: float) -> float:
	if not is_finite(current):
		return target
	var k := 1.0 - pow(1.0 - SCALE_SMOOTH_FACTOR, maxf(delta, 0.0) * 60.0)
	var next := lerpf(current, target, k)
	return target if absf(next - target) < 0.0005 else next


## Model height in window pixels at scale 1.0 such that SCALE_MAX still fits between the margins.
static func reference_height_px(window_height: float) -> float:
	return (window_height - FOOT_MARGIN_PX - HEAD_MARGIN_PX) / SCALE_MAX


## Standing foot pivot in window pixels: centred in the pet zone, FOOT_MARGIN_PX above the bottom.
static func foot_pivot_px(window_size: Vector2, pet_zone_width: float) -> Vector2:
	return Vector2(window_size.x - pet_zone_width * 0.5, window_size.y - FOOT_MARGIN_PX)


## Orthographic desktop camera: exact pixels/metre at every depth. This keeps a
## measured shoe sole and conservative body bounds on the same desktop support.
## fov only selects a comfortable camera distance; it does not change projection scale.
static func pet_camera(model_height: float, fov_deg: float, window_size: Vector2, pivot_px: Vector2,
		reference_px: float) -> Dictionary:
	var h := maxf(model_height, 0.5)
	var ppm := reference_px / h
	var distance := window_size.y / (2.0 * tan(deg_to_rad(fov_deg) * 0.5) * ppm)
	var centre := window_size * 0.5
	return {"position": Vector3(-(pivot_px.x - centre.x) / ppm, (pivot_px.y - centre.y) / ppm, distance),
		"px_per_m": ppm, "size": window_size.y / ppm, "projection": Camera3D.PROJECTION_ORTHOGONAL}


## Window pixel -> world point on the z=0 plane for a camera from pet_camera() at camera_base.
static func pixel_to_world(px: Vector2, camera_base: Vector3, px_per_m: float, window_size: Vector2) -> Vector3:
	var centre := window_size * 0.5
	return Vector3(camera_base.x + (px.x - centre.x) / px_per_m, camera_base.y - (px.y - centre.y) / px_per_m, 0.0)


## Avatar transform that keeps pivot_local (foot or seat, avatar-local metres) exactly at
## pivot_world whatever the facing yaw and scale in [basis]: scaling/turning happen about the contact.
static func pivot_transform(basis: Basis, pivot_world: Vector3, pivot_local: Vector3) -> Transform3D:
	return Transform3D(basis, pivot_world - basis * pivot_local)


## Body-shaped hit/bounds rect from the projected mesh AABB: VRM AABBs are wide (arms), so 12 % is
## trimmed from each side. Shared by the host's pet rect and the tests.
static func body_rect(projected: Rect2) -> Rect2:
	var shrink_x := projected.size.x * 0.12
	return Rect2(projected.position.x + shrink_x, projected.position.y, projected.size.x - 2.0 * shrink_x, projected.size.y)


## Pixel shift that brings a projected pet rect back inside the window (top/bottom first, then
## sides); Vector2.ZERO when it already fits. Applied to the pivot so a large seated scale never
## pushes the dangling legs out of the window.
static func fit_shift(rect: Rect2, window_size: Vector2) -> Vector2:
	var shift := Vector2.ZERO
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return shift
	if rect.end.y > window_size.y:
		shift.y = window_size.y - rect.end.y
	if rect.position.y + shift.y < 0.0:
		shift.y = -rect.position.y
	if rect.end.x > window_size.x:
		shift.x = window_size.x - rect.end.x
	if rect.position.x + shift.x < 0.0:
		shift.x = -rect.position.x
	return shift


## Vertical float offset (metres) for the fallback presentation; blend 0..1 fades it in/out.
static func float_offset(time: float, blend: float) -> float:
	return FLOAT_AMPLITUDE * clampf(blend, 0.0, 1.0) * sin(time * TAU / FLOAT_PERIOD)


## Which imported loop (if any) may run as the ambient idle.
##   setting "" (off)      -> ""
##   setting "auto"        -> first AMBIENT_IDLE_CLIPS entry that is loaded, only when the motion
##                            owner exposes an ambient-loop API that blends UNDER gestures/gaze/IK
##                            (has_ambient_api). Without that API a looping VRMA would override
##                            head gaze and be silently killed by the first gesture, so: "".
##   setting <clip name>   -> that clip when loaded and the API exists, else "".
static func ambient_idle_choice(setting: String, loaded_clips: Dictionary, has_ambient_api: bool) -> String:
	if setting.is_empty() or not has_ambient_api:
		return ""
	if setting == "auto":
		for name in AMBIENT_IDLE_CLIPS:
			if loaded_clips.has(name):
				return name
		return ""
	return setting if loaded_clips.has(setting) else ""


## Saved window origin restore. Negative coordinates are valid (monitors left of/above the
## primary); the only requirement is that the window, inset by RESTORE_INSET, still touches one
## of the current monitors' usable rects. Otherwise the bottom-right of [fallback] is used.
static func restore_position(saved: bool, x: int, y: int, window_size: Vector2i,
		screens: Array, fallback: Rect2i) -> Vector2i:
	if saved:
		var wanted := Rect2i(Vector2i(x, y), window_size)
		for s in screens:
			var screen: Rect2i = s
			if screen.grow(-RESTORE_INSET).intersects(wanted):
				return wanted.position
	return Vector2i(fallback.end.x - window_size.x - 16, fallback.end.y - window_size.y - 8)


## Render gutters may change independently of the visible character's desktop
## position. Old settings contain an origin in the original reference canvas.
static func restore_render_position(settings: Dictionary, reference_size: Vector2i,
		reference_foot: Vector2, render_foot: Vector2, screens: Array, fallback: Rect2i) -> Vector2i:
	var logical_origin := Vector2i(int(settings.get("window_x", -1)), int(settings.get("window_y", -1)))
	var saved := bool(settings.get("window_pos_saved", false))
	if settings.has("window_foot_x") and settings.has("window_foot_y"):
		var anchor := Vector2(float(settings.window_foot_x), float(settings.window_foot_y))
		var visible := false
		if anchor.is_finite():
			for screen in screens:
				# A floor sole may lie exactly on the bottom/right workarea edge.
				if Rect2(screen).grow(1.0).has_point(anchor): visible = true; break
		if visible: logical_origin = Vector2i((anchor - reference_foot).round())
		else: saved = false
	var restored := restore_position(saved,
		logical_origin.x, logical_origin.y, reference_size, screens, fallback)
	return Vector2i((Vector2(restored) + reference_foot - render_foot).round())
