class_name LayeredSpriteAnimator
extends Node2D

const MAX_CATCH_UP_TICKS := 8

@onready var body: Sprite2D = $Body
@onready var weapon: Sprite2D = $Weapon

var _profile: RoleAnimationProfile
var _registered_role_id := 0
var _animations: Dictionary = {}
var _current_action: StringName = &""
var _frame_index := 0
var _ticks_remaining := 1
var _tick_accumulator := 0.0
var _body_showid := 0
var _weapon_showid := 0


func _ready() -> void:
	body.region_enabled = true
	weapon.region_enabled = true
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon.z_index = 1


func _process(delta: float) -> void:
	if _profile == null:
		return
	_tick_accumulator += delta * _profile.logical_fps
	var pending_ticks := mini(int(_tick_accumulator), MAX_CATCH_UP_TICKS)
	_tick_accumulator -= pending_ticks
	for _tick in range(pending_ticks):
		_advance_tick()


func register_role(
	role_id: int,
	profile: RoleAnimationProfile,
	body_showid := -1,
	weapon_showid := -1
) -> bool:
	if profile == null:
		push_error("Cannot register role %d without an animation profile." % role_id)
		return false
	var validation_errors := profile.validate_for_role(role_id)
	if not validation_errors.is_empty():
		for validation_error in validation_errors:
			push_error(validation_error)
		return false

	_profile = profile
	_registered_role_id = role_id
	_animations.clear()
	_current_action = &""
	_frame_index = 0
	_ticks_remaining = 1
	_tick_accumulator = 0.0

	var initial_body := profile.default_body_showid if body_showid < 0 else body_showid
	var initial_weapon := profile.default_weapon_showid if weapon_showid < 0 else weapon_showid
	_body_showid = initial_body
	_weapon_showid = initial_weapon
	position = profile.get_runtime_visual_offset()
	if not _refresh_equipment_and_animations():
		unregister_role()
		return false
	play_action(profile.default_action, true)
	return true


func unregister_role() -> void:
	_profile = null
	_registered_role_id = 0
	_animations.clear()
	_current_action = &""
	body.texture = null
	weapon.texture = null


func is_role_registered() -> bool:
	return _profile != null and _registered_role_id > 0


func get_registered_role_id() -> int:
	return _registered_role_id


func get_current_action() -> StringName:
	return _current_action


func play_action(action: StringName, restart := false) -> bool:
	if _profile == null:
		return false
	if not _animations.has(action):
		action = _profile.default_action
	if action == _current_action and not restart:
		return true
	_current_action = action
	_frame_index = 0
	_show_current_frame()
	return true


func set_body(showid: int) -> bool:
	if _profile == null:
		return false
	var atlas := _profile.get_body_atlas(showid, _weapon_showid)
	if atlas == null:
		push_warning("Role %d has no body showid %d." % [_registered_role_id, showid])
		return false
	_body_showid = showid
	body.texture = atlas
	_show_current_frame()
	return true


func set_weapon(showid: int) -> bool:
	if _profile == null:
		return false
	var atlas := _profile.get_weapon_atlas(showid)
	if atlas == null:
		push_warning("Role %d has no weapon showid %d." % [_registered_role_id, showid])
		return false
	_weapon_showid = showid
	weapon.texture = atlas
	if not _refresh_body_for_weapon():
		return false
	_animations = _profile.compile_animations(_weapon_showid)
	play_action(_current_action, true)
	return true


func cycle_weapon(step := 1) -> int:
	if _profile == null:
		return _weapon_showid
	var next_showid := _profile.get_next_weapon_showid(_weapon_showid, step)
	set_weapon(next_showid)
	return _weapon_showid


func cycle_body(step := 1) -> int:
	if _profile == null:
		return _body_showid
	var next_showid := _profile.get_next_body_showid(_body_showid, step)
	set_body(next_showid)
	return _body_showid


func get_body_showid() -> int:
	return _body_showid


func get_weapon_showid() -> int:
	return _weapon_showid


func get_body_name() -> String:
	return _profile.get_body_name(_body_showid) if _profile != null else "未注册"


func get_weapon_name() -> String:
	return _profile.get_weapon_name(_weapon_showid) if _profile != null else "未注册"


func set_facing(direction: float) -> void:
	if _profile == null or is_zero_approx(direction):
		return
	var gameplay_facing := 1 if direction > 0.0 else -1
	var should_mirror := gameplay_facing != _profile.source_facing
	scale.x = absf(scale.x) * (-1.0 if should_mirror else 1.0)


func _advance_tick() -> void:
	if _ticks_remaining > 1:
		_ticks_remaining -= 1
		return
	var animation: Dictionary = _animations[_current_action]
	var frames: Array = animation["frames"]
	if _frame_index + 1 < frames.size():
		_frame_index += 1
	elif animation["loop"]:
		_frame_index = 0
	else:
		_ticks_remaining = 1
		return
	_show_current_frame()


func _show_current_frame() -> void:
	if not is_node_ready() or _profile == null or not _animations.has(_current_action):
		return
	var frames: Array = _animations[_current_action]["frames"]
	var frame: Vector3i = frames[_frame_index]
	var frame_size := Vector2(_profile.frame_size)
	var region := Rect2(Vector2(frame.x, frame.y) * frame_size, frame_size)
	body.region_rect = region
	weapon.region_rect = region
	_ticks_remaining = frame.z


func _refresh_equipment_and_animations() -> bool:
	var weapon_atlas := _profile.get_weapon_atlas(_weapon_showid)
	var body_atlas := _profile.get_body_atlas(_body_showid, _weapon_showid)
	if weapon_atlas == null or body_atlas == null:
		push_warning(
			"Role %d cannot resolve body %d with weapon %d."
			% [_registered_role_id, _body_showid, _weapon_showid]
		)
		return false
	weapon.texture = weapon_atlas
	body.texture = body_atlas
	_animations = _profile.compile_animations(_weapon_showid)
	return not _animations.is_empty()


func _refresh_body_for_weapon() -> bool:
	var body_atlas := _profile.get_body_atlas(_body_showid, _weapon_showid)
	if body_atlas == null:
		push_warning(
			"Role %d has no body %d for weapon %d."
			% [_registered_role_id, _body_showid, _weapon_showid]
		)
		return false
	body.texture = body_atlas
	return true
