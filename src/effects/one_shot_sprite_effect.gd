class_name OneShotSpriteEffect
extends Sprite2D

const MAX_CATCH_UP_FRAMES := 8

var _frames: Array = []
var _fps := 24.0
var _frame_index := 0
var _frame_accumulator := 0.0
var _follow_target: Node2D
var _follow_offset := Vector2.ZERO
var _loop := false
var _linear_velocity := Vector2.ZERO
var _lifetime_seconds := 0.0


func configure(
	frames: Array,
	fps: float,
	source_facing: int,
	gameplay_facing: float,
	sprite_offset := Vector2.ZERO
) -> bool:
	if frames.is_empty() or fps <= 0.0:
		return false
	_frames = frames
	_fps = fps
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
	offset = sprite_offset
	z_index = 4
	var facing_sign := 1 if gameplay_facing >= 0.0 else -1
	scale.x = -1.0 if facing_sign != source_facing else 1.0
	texture = _frames[0] as Texture2D
	return texture != null


func _process(delta: float) -> void:
	if _lifetime_seconds > 0.0:
		_lifetime_seconds -= delta
		if _lifetime_seconds <= 0.0:
			queue_free()
			return
	if not _update_follow_position():
		return
	if _follow_target == null:
		global_position += _linear_velocity * delta
	_advance_animation(delta)


func _advance_animation(delta: float) -> bool:
	_frame_accumulator += delta * _fps
	var pending_frames := mini(int(_frame_accumulator), MAX_CATCH_UP_FRAMES)
	_frame_accumulator -= pending_frames
	for _frame in range(pending_frames):
		_frame_index += 1
		if _frame_index >= _frames.size():
			if _loop:
				_frame_index = 0
				texture = _frames[0] as Texture2D
				continue
			queue_free()
			return false
		texture = _frames[_frame_index] as Texture2D
	return true


func get_frame_index() -> int:
	return _frame_index


func get_duration_seconds() -> float:
	return float(_frames.size()) / _fps if _fps > 0.0 else 0.0


func set_follow_target(target: Node2D, follow_offset: Vector2) -> void:
	_follow_target = target
	_follow_offset = follow_offset
	_update_follow_position()


func set_looping(looping: bool) -> void:
	_loop = looping


func set_linear_velocity(linear_velocity: Vector2) -> void:
	_linear_velocity = linear_velocity


func set_lifetime(seconds: float) -> void:
	_lifetime_seconds = maxf(0.0, seconds)


func set_blend_mode(blend_mode: int) -> void:
	var canvas_material := CanvasItemMaterial.new()
	canvas_material.blend_mode = blend_mode as CanvasItemMaterial.BlendMode
	material = canvas_material


func is_following(target: Node2D) -> bool:
	return _follow_target == target


func _update_follow_position() -> bool:
	if _follow_target == null:
		return true
	if not is_instance_valid(_follow_target):
		queue_free()
		return false
	global_position = _follow_target.global_position + _follow_offset
	return true
