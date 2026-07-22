class_name EnemyAnimationEventDispatcher
extends Node

## Emits source-traceable animation events without executing translated
## gameplay behavior. Enemy logic chooses which event ids it supports.

signal source_event(action: StringName, event: Dictionary)

var _sprite: AnimatedSprite2D
var _profile: EnemyAnimationProfile
var _last_animation: StringName = &""
var _last_frame := -1


func bind(sprite: AnimatedSprite2D, profile: EnemyAnimationProfile) -> void:
	_unbind_sprite()
	_sprite = sprite
	_profile = profile
	_last_animation = &""
	_last_frame = -1
	if _sprite == null:
		return
	_sprite.frame_changed.connect(_on_frame_changed)
	_sprite.animation_changed.connect(_on_animation_changed)
	emit_current_frame(true)


func emit_current_frame(force := false) -> void:
	if _sprite == null or _profile == null:
		return
	var action := _sprite.animation
	var frame := _sprite.frame
	if not force and action == _last_animation and frame == _last_frame:
		return
	_last_animation = action
	_last_frame = frame
	for event: Dictionary in _profile.get_source_events_at_frame(action, frame):
		source_event.emit(action, event.duplicate(true))


func _exit_tree() -> void:
	_unbind_sprite()


func _on_frame_changed() -> void:
	emit_current_frame()


func _on_animation_changed() -> void:
	_last_animation = &""
	_last_frame = -1
	emit_current_frame.call_deferred()


func _unbind_sprite() -> void:
	if _sprite == null:
		return
	if _sprite.frame_changed.is_connected(_on_frame_changed):
		_sprite.frame_changed.disconnect(_on_frame_changed)
	if _sprite.animation_changed.is_connected(_on_animation_changed):
		_sprite.animation_changed.disconnect(_on_animation_changed)
	_sprite = null
