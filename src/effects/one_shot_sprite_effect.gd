class_name OneShotSpriteEffect
extends Sprite2D

const MAX_CATCH_UP_FRAMES := 8

var _frames: Array = []
var _fps := 24.0
var _frame_index := 0
var _frame_accumulator := 0.0


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
	_frame_accumulator += delta * _fps
	var pending_frames := mini(int(_frame_accumulator), MAX_CATCH_UP_FRAMES)
	_frame_accumulator -= pending_frames
	for _frame in range(pending_frames):
		_frame_index += 1
		if _frame_index >= _frames.size():
			queue_free()
			return
		texture = _frames[_frame_index] as Texture2D
