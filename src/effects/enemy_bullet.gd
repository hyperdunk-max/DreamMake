class_name EnemyBullet
extends Area2D

## Source-timeline projectile rendered from the existing sprite atlas.
## Collision follows each frame's visible bounds; only projectiles explicitly
## marked as code-driven receive velocity (M14 in the original game).

signal bullet_destroyed
signal target_hit(target: Node2D, damage: int, frame: int)

const SOURCE_TICK_RATE := 24.0

# Damage and source attack-id state.
var _source_actor: Node2D
var _damage := 0
var _damage_kind: StringName = &"physical"
var _knockback := Vector2.ZERO
var _max_hits := 1
var _rehit_interval_frames := 999
var _hits := 0
var _target_last_hit_generation: Dictionary = {}

# Visual registration and code-driven movement state.
var _frame_bounds: Array[Rect2] = []
var _fallback_collision_size := Vector2(48.0, 48.0)
var _facing := -1
var _source_facing := -1
var _motion: StringName = &"timeline"
var _speed := 0.0
var _acceleration := 0.0
var _max_speed := 0.0
var _remaining_distance := 0.0

# Playback lifecycle. The attack interval is intentionally counted in source
# ticks so physics FPS does not alter repeat-hit timing.
var _configured := false
var _status_effects: Array = []
var _activation_delay_total := 0.0
var _activation_delay_remaining := 0.0
var _source_tick_accumulator := 0.0
var _attack_interval_count := 0
var _attack_generation := 0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# Configuration

func configure(
	sprite_frames: SpriteFrames,
	animation_name: StringName,
	facing: int,
	source_actor: Node2D,
	spec: Dictionary,
	frame_bounds: Array[Rect2] = []
) -> bool:
	if sprite_frames == null or not sprite_frames.has_animation(animation_name):
		return false
	_source_actor = source_actor
	_facing = -1 if facing < 0 else 1
	_source_facing = -1 if int(spec.get("projectile_source_facing", -1)) < 0 else 1
	_damage = maxi(0, int(spec.get("bullet_damage", spec.get("damage", 0))))
	_damage_kind = StringName(spec.get("bullet_damage_kind", spec.get("damage_kind", &"physical")))
	var raw_knockback := Vector2(spec.get(
		"bullet_knockback_velocity",
		spec.get("knockback_velocity", spec.get("bullet_knockback", Vector2.ZERO))
	))
	_knockback = Vector2(absf(raw_knockback.x) * _facing, raw_knockback.y)
	_max_hits = maxi(1, int(spec.get("bullet_hit_max_count", spec.get("hit_max_count", 1))))
	_rehit_interval_frames = maxi(
		1, int(spec.get("bullet_rehit_interval_frames", spec.get("rehit_interval_frames", 999)))
	)
	_fallback_collision_size = Vector2(
		spec.get("projectile_collision_size", spec.get("bullet_collision_size", Vector2(48, 48)))
	)
	_frame_bounds = frame_bounds
	_motion = StringName(spec.get("projectile_motion", "timeline"))
	_speed = absf(float(spec.get("projectile_initial_speed", 0.0))) * _facing
	_acceleration = float(spec.get("projectile_acceleration", 0.0))
	_max_speed = float(spec.get("projectile_max_speed", absf(_speed)))
	_remaining_distance = float(spec.get("projectile_max_distance", 0.0))
	_status_effects = Array(spec.get("status_effects", [])).duplicate(true)
	_activation_delay_total = maxf(0.0, float(spec.get("projectile_activation_delay", 0.0)))
	_activation_delay_remaining = _activation_delay_total
	_source_tick_accumulator = 0.0
	_attack_interval_count = 0
	_attack_generation = 0
	_target_last_hit_generation.clear()

	anim.sprite_frames = sprite_frames
	anim.flip_h = _facing != _source_facing
	anim.frame = 0
	anim.play(animation_name)
	if _activation_delay_remaining > 0.0:
		anim.pause()
		anim.modulate.a = 0.0
	if _motion != &"timeline" and sprite_frames.get_frame_count(animation_name) == 1:
		sprite_frames.set_animation_loop(animation_name, true)
	if not anim.frame_changed.is_connected(_on_frame_changed):
		anim.frame_changed.connect(_on_frame_changed)
	if not anim.animation_finished.is_connected(_on_animation_finished):
		anim.animation_finished.connect(_on_animation_finished)
	_refresh_collision()
	if _activation_delay_remaining > 0.0:
		collision_shape.set_deferred(&"disabled", true)
	_configured = true
	return true


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	if _advance_activation_delay(delta):
		return
	_source_tick_accumulator += maxf(0.0, delta) * SOURCE_TICK_RATE
	var pending_ticks := int(_source_tick_accumulator)
	_source_tick_accumulator -= pending_ticks
	for _tick in pending_ticks:
		_advance_source_tick()
		if is_queued_for_deletion():
			return


func _advance_activation_delay(delta: float) -> bool:
	if _activation_delay_remaining <= 0.0:
		return false
	# Persistent source flames fade in before they can attack. Pausing both the
	# animation and collision keeps the visual and damage windows synchronized.
	_activation_delay_remaining = maxf(0.0, _activation_delay_remaining - delta)
	anim.modulate.a = 1.0 - _activation_delay_remaining / _activation_delay_total
	if _activation_delay_remaining <= 0.0:
		anim.modulate.a = 1.0
		anim.play()
		_refresh_collision()
	return true


# Fixed-rate source simulation

func _advance_source_tick() -> void:
	# BaseBullet.checkAttack() refreshes its attack id before checking targets,
	# then increments attackIntervalCount after successful contact.
	if _attack_interval_count == _rehit_interval_frames:
		_attack_generation += 1
		_attack_interval_count = 0
	_check_overlapping_targets()
	if is_queued_for_deletion():
		return
	_update_code_movement_tick()
	if _attack_interval_count > 0:
		_attack_interval_count += 1


func _update_code_movement_tick() -> void:
	if _motion == &"timeline":
		return
	# EnemyMoveBullet moves with the old speed, then applies its 0.4 px/tick
	# acceleration, then subtracts the updated speed from its distance budget.
	# The signed comparison is intentional: the source accelerates left-facing
	# negative bullets beyond -7 because it checks `speed < 7` literally.
	global_position.x += _speed / SOURCE_TICK_RATE
	if _acceleration > 0.0 and _max_speed > 0.0 and _speed < _max_speed:
		var acceleration_per_tick := _acceleration / SOURCE_TICK_RATE
		_speed += acceleration_per_tick if _speed > 0.0 else -acceleration_per_tick
	if _remaining_distance <= 0.0:
		return
	_remaining_distance -= absf(_speed) / SOURCE_TICK_RATE
	if _remaining_distance <= 0.0:
		queue_free()


# Collision and animation lifecycle

func _check_overlapping_targets() -> void:
	if collision_shape.disabled or _damage <= 0:
		return
	for body: Node2D in get_overlapping_bodies():
		if not body.is_in_group(&"players") or not body.has_method(&"take_hit"):
			continue
		if int(_target_last_hit_generation.get(body, -1)) == _attack_generation:
			continue
		_target_last_hit_generation[body] = _attack_generation
		var valid_source: Object = _source_actor if is_instance_valid(_source_actor) else null
		body.take_hit(_damage, _knockback, _damage_kind, valid_source)
		if body.has_method(&"apply_combat_status"):
			for raw_status: Variant in _status_effects:
				if raw_status is Dictionary:
					body.call(&"apply_combat_status", raw_status, valid_source)
		_hits += 1
		if _attack_interval_count == 0:
			_attack_interval_count = 1
		target_hit.emit(body, _damage, anim.frame)
		if _hits >= _max_hits:
			queue_free()
			return


func _on_frame_changed() -> void:
	_refresh_collision()


func _refresh_collision() -> void:
	if collision_shape == null:
		return
	var bounds := Rect2(-_fallback_collision_size * 0.5, _fallback_collision_size)
	if anim.frame >= 0 and anim.frame < _frame_bounds.size():
		bounds = _frame_bounds[anim.frame]
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		collision_shape.set_deferred(&"disabled", true)
		return
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	collision_shape.shape = shape
	var center := bounds.get_center()
	if anim.flip_h:
		center.x = -center.x
	collision_shape.position = center
	collision_shape.set_deferred(&"disabled", false)


func _on_animation_finished() -> void:
	if _motion == &"timeline":
		queue_free()


func _exit_tree() -> void:
	bullet_destroyed.emit()


# Test/debug inspection API. Runtime gameplay does not depend on these values.

func get_source_speed_px_per_tick() -> float:
	return _speed / SOURCE_TICK_RATE


func get_source_distance_remaining() -> float:
	return _remaining_distance


func get_attack_generation() -> int:
	return _attack_generation
