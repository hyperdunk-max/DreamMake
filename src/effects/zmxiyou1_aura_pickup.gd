class_name Zmxiyou1AuraPickup
extends Node2D

## Source-accurate 24 Hz aura drop. The 19-frame visuals are loaded through
## the same sprite.png + sprite.json path used by all monster animations.

signal collected(kind: StringName, power: int, target: Node2D)

enum MotionState { WAIT, RISE, HOMING }

const SOURCE_TICK_RATE := 24.0
const WAIT_TICKS := 20
const RISE_TICKS := 24
const MAX_COUNTER_TICKS := 2400
const COLLECT_DISTANCE := 10.0
const ATLAS_ROOT := "res://assets/selected/zmxiyou1/monsters/shared/effects"
const SOURCE_NAMES := {
	&"red": "auraRed",
	&"green": "auraGreen",
	&"blue": "auraBlue",
	&"white": "auraWhile",
}

static var _frames_cache: Dictionary = {}

var aura_kind: StringName = &"red"
var power := 0
var target: Node2D

var _motion_state := MotionState.WAIT
var _source_tick_accumulator := 0.0
var _wait_ticks_remaining := WAIT_TICKS
var _lifetime_counter := 0
var _rise_tick := 0
var _rise_origin := Vector2.ZERO
var _rise_distance := 40.0
var _speed_px_per_tick := 5.0
var _collected := false
var _rng := RandomNumberGenerator.new()
var _sprite: AnimatedSprite2D


func setup(kind: StringName, source_target: Node2D, source_power: int, random_seed: int) -> void:
	aura_kind = kind
	target = source_target
	power = source_power
	_rng.seed = random_seed
	_speed_px_per_tick = 4.0 + _rng.randf() * 2.0


func _ready() -> void:
	add_to_group(&"zmxiyou1_aura_pickups")
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "AnimatedSprite2D"
	_sprite.sprite_frames = _frames_for_kind(aura_kind)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 8
	add_child(_sprite)
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"aura"):
		_sprite.play(&"aura")


func _physics_process(delta: float) -> void:
	_source_tick_accumulator += delta
	while _source_tick_accumulator >= 1.0 / SOURCE_TICK_RATE:
		_source_tick_accumulator -= 1.0 / SOURCE_TICK_RATE
		source_tick()


func source_tick() -> void:
	if _collected:
		return
	match _motion_state:
		MotionState.WAIT:
			if _wait_ticks_remaining > 0:
				_wait_ticks_remaining -= 1
			else:
				_begin_rise()
			_lifetime_counter += 1
		MotionState.RISE:
			_rise_tick += 1
			var progress := clampf(float(_rise_tick) / float(RISE_TICKS), 0.0, 1.0)
			# TweenMax's default ease is Quad.easeOut.
			var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
			global_position = _rise_origin + Vector2.UP * _rise_distance * eased
			if _rise_tick >= RISE_TICKS:
				_motion_state = MotionState.HOMING
		MotionState.HOMING:
			_homing_tick()
			_lifetime_counter += 1
	if _lifetime_counter > MAX_COUNTER_TICKS:
		_collect()


func get_motion_state_name() -> StringName:
	return MotionState.keys()[_motion_state].to_lower()


func get_source_speed_px_per_tick() -> float:
	return _speed_px_per_tick


func _begin_rise() -> void:
	_motion_state = MotionState.RISE
	_rise_tick = 0
	_rise_origin = global_position
	_rise_distance = 50.0 - _rng.randf() * 20.0


func _homing_tick() -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	var delta_to_target := target.global_position - global_position
	if not delta_to_target.is_zero_approx():
		global_position += delta_to_target.normalized() * _speed_px_per_tick
	_speed_px_per_tick = minf(20.0, _speed_px_per_tick + 2.0)
	if global_position.distance_to(target.global_position) <= COLLECT_DISTANCE:
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	if target != null and is_instance_valid(target):
		match aura_kind:
			&"green":
				if target.has_method(&"heal"):
					target.call(&"heal", power)
			&"blue":
				if target.has_method(&"restore_mana"):
					target.call(&"restore_mana", power)
			&"red":
				if target.has_method(&"add_source_soul"):
					target.call(&"add_source_soul", power)
			&"white":
				if target.has_method(&"add_source_warrior_energy"):
					target.call(&"add_source_warrior_energy", power)
	collected.emit(aura_kind, power, target)
	queue_free()


static func _frames_for_kind(kind: StringName) -> SpriteFrames:
	if _frames_cache.has(kind):
		return _frames_cache[kind]
	var source_name := str(SOURCE_NAMES.get(kind, "auraRed"))
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var count := SpriteSheetAtlas.append_animation(
		frames,
		&"aura",
		"%s/%s/sprite.png" % [ATLAS_ROOT, source_name],
		"%s/%s/sprite.json" % [ATLAS_ROOT, source_name],
		SOURCE_TICK_RATE,
		true
	)
	if count <= 0:
		return null
	_frames_cache[kind] = frames
	return frames
