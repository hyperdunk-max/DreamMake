class_name Zmxiyou1M24Controller
extends Node2D

## Source-faithful composite controller for Monster24.
##
## Flash advanced the heart, eyes, hands, and fire as independent clips.  The
## controller preserves those 24 Hz clocks while using Godot shape queries in
## place of complexHitTestObject.  Every visual still comes from the selected
## sprite.png + sprite.json atlases declared by the animation profile.

signal screen_shake_requested(strength: float)
signal hazard_hit(target: Node2D, action: StringName, source_frame: int)

enum HeartPhase { HIDDEN, FADING_IN, VULNERABLE, FADING_OUT }

const SOURCE_TICK_RATE := 24
const FADE_TICKS := 2 * SOURCE_TICK_RATE
const BODY_X := -141.0 / 20.0
const HEART_POSITION := Vector2(BODY_X + 491.0 / 20.0, 2322.0 / 20.0)
const RIGHT_EYE_POSITION := Vector2(BODY_X + 905.0 / 20.0, -1552.0 / 20.0)
const LEFT_EYE_POSITION := Vector2(BODY_X - 172.0 / 20.0, -1552.0 / 20.0)
const HAND_PARENT_Y := 18.0
const LEFT_HAND_X := -300.0
const RIGHT_HAND_X := 300.0
const HAND_MIN_X := -400.0
const HAND_MAX_X := 400.0
const HAND_SLAM_Y := 126.0
const SOURCE_HURTBOX_SIZE := Vector2(100.0 * 0.83226013, 90.0 * 1.7772522)
const SOURCE_HURTBOX_POSITION := Vector2(363.0 / 20.0, 2820.0 / 20.0)
const FIRE_ACTIVE_FRAMES := Vector2i(24, 35)
const FIRE_DESTROY_FRAME := 35
const FIRE_CANVAS_OFFSET := Vector2(0.0, -137.5)


class HandRuntime:
	extends RefCounted

	var sprite: AnimatedSprite2D
	var x := 0.0
	var y := 0.0
	var move_ticks := 0
	var direction := 0
	var direction_ticks := 24
	var hold_ticks := 24
	var down_speed := 3.0


class FireRuntime:
	extends RefCounted

	var sprite: AnimatedSprite2D
	var frame := 0


var _host: AnimatedEnemy
var _profile: EnemyAnimationProfile
var _frames: SpriteFrames
var _rng := RandomNumberGenerator.new()
var _background: AnimatedSprite2D
var _heart: AnimatedSprite2D
var _left_eye: AnimatedSprite2D
var _right_eye: AnimatedSprite2D
var _hands: Array = []
var _fires: Array = []
var _hand_bounds: Array[Rect2] = []
var _fire_bounds: Array[Rect2] = []
var _hand_attack: Dictionary = {}
var _fire_attack: Dictionary = {}
var _heart_phase := HeartPhase.HIDDEN
var _heart_timer := 0
var _heart_fade_tick := 0
var _background_tick := 0
var _hands_initialized := false
var _fire_timer := 0
var _next_fire_count := 2
var _fire_spawn_history := PackedInt32Array()
var _attack_generation := 0
var _target_attack_generation: Dictionary = {}
var _death_tick := -1


func setup(host: AnimatedEnemy) -> void:
	_host = host
	_profile = host.definition.animation_profile
	_frames = host.animated_sprite.sprite_frames
	_rng.seed = hash("%s:%s:m24" % [host.definition.enemy_id, host.spawn_id])
	host.animated_sprite.visible = false
	_configure_source_hurtbox()
	_create_body_visuals()
	_load_collision_bounds()
	_hand_attack = EnemyCombatCatalog.resolve_attack(_profile, &"attack1")
	_fire_attack = EnemyCombatCatalog.resolve_attack(_profile, &"attack2")
	_heart_timer = _rng.randi_range(5, 9) * SOURCE_TICK_RATE
	_fire_timer = _rng.randi_range(2, 6) * SOURCE_TICK_RATE


func source_tick(_source_tick: int) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	if _death_tick >= 0:
		_step_death_fade()
		return
	_advance_loop(_heart, &"idle")
	_advance_loop(_left_eye, &"eyes")
	_advance_loop(_right_eye, &"eyes")
	_step_background_intro()
	_step_heart()
	for hand: HandRuntime in _hands:
		_step_hand(hand)
	_step_fires()
	_step_fire_timer()


func can_receive_hit() -> bool:
	return _death_tick < 0 and _heart_phase == HeartPhase.VULNERABLE and is_equal_approx(_heart.modulate.a, 1.0)


func keeps_idle_on_hit() -> bool:
	return true


func begin_death() -> bool:
	if _death_tick < 0:
		_death_tick = 0
		_set_hurtbox_enabled(false)
		for fire: FireRuntime in _fires:
			fire.sprite.set_process(false)
	return true


func get_heart_phase() -> StringName:
	return StringName(HeartPhase.keys()[_heart_phase].to_lower())


func get_heart_alpha() -> float:
	return _heart.modulate.a if _heart != null else 0.0


func get_hand_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hand: HandRuntime in _hands:
		result.append({
			"x": hand.x,
			"y": hand.y,
			"move_ticks": hand.move_ticks,
			"direction": hand.direction,
			"direction_ticks": hand.direction_ticks,
			"hold_ticks": hand.hold_ticks,
			"down_speed": hand.down_speed,
		})
	return result


func get_fire_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fire: FireRuntime in _fires:
		result.append({"frame": fire.frame, "global_position": fire.sprite.global_position})
	return result


func get_fire_spawn_history() -> PackedInt32Array:
	return _fire_spawn_history.duplicate()


func get_attack_generation() -> int:
	return _attack_generation


func _configure_source_hurtbox() -> void:
	var shape := RectangleShape2D.new()
	shape.size = SOURCE_HURTBOX_SIZE
	_host.collision_shape.shape = shape
	_host.collision_shape.position = SOURCE_HURTBOX_POSITION
	_host.collision_shape.disabled = true


func _create_body_visuals() -> void:
	_background = _new_sprite(&"background", "Background", -20)
	_background.modulate.a = 0.0
	_heart = _new_sprite(&"idle", "Heart", 1)
	_heart.position = HEART_POSITION
	_heart.modulate.a = 0.0
	_heart.material = _host.animated_sprite.material
	_left_eye = _new_sprite(&"eyes", "LeftEye", 2)
	_left_eye.position = LEFT_EYE_POSITION
	_left_eye.flip_h = true
	_right_eye = _new_sprite(&"eyes", "RightEye", 2)
	_right_eye.position = RIGHT_EYE_POSITION


func _load_collision_bounds() -> void:
	var hand_spec := _profile.get_spec(&"attack1")
	_hand_bounds = SpriteSheetAtlas.build_visible_bounds(
		str(hand_spec.get("sprite_sheet", "")), str(hand_spec.get("sprite_sheet_json", ""))
	)
	var fire_spec := _profile.get_spec(&"attack2")
	_fire_bounds = SpriteSheetAtlas.build_visible_bounds(
		str(fire_spec.get("sprite_sheet", "")), str(fire_spec.get("sprite_sheet_json", ""))
	)


func _new_sprite(action: StringName, node_name: String, draw_order: int) -> AnimatedSprite2D:
	var result := AnimatedSprite2D.new()
	result.name = node_name
	result.sprite_frames = _frames
	result.animation = action
	result.frame = 0
	result.pause()
	result.z_index = draw_order
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(result)
	return result


func _advance_loop(sprite: AnimatedSprite2D, action: StringName) -> void:
	if sprite == null or _frames == null or not _frames.has_animation(action):
		return
	var count := _frames.get_frame_count(action)
	if count > 0:
		sprite.frame = (sprite.frame + 1) % count


func _step_background_intro() -> void:
	if _background_tick >= FADE_TICKS:
		return
	_background_tick += 1
	_background.modulate.a = float(_background_tick) / float(FADE_TICKS)
	if _background_tick == FADE_TICKS:
		_initialize_hands()


func _initialize_hands() -> void:
	if _hands_initialized:
		return
	_hands_initialized = true
	_hands.append(_create_hand(LEFT_HAND_X, false, "LeftHand"))
	_hands.append(_create_hand(RIGHT_HAND_X, true, "RightHand"))


func _create_hand(source_x: float, mirrored: bool, node_name: String) -> HandRuntime:
	var hand := HandRuntime.new()
	hand.sprite = _new_sprite(&"attack1", node_name, 3)
	hand.sprite.flip_h = mirrored
	hand.x = source_x
	hand.move_ticks = _rng.randi_range(2, 4) * SOURCE_TICK_RATE
	_sync_hand_sprite(hand)
	return hand


func _step_hand(hand: HandRuntime) -> void:
	# The two `if` blocks intentionally mirror Hands.step(): a reset performed
	# by downAttack immediately executes one horizontal movement on that tick.
	if hand.move_ticks == 0:
		_step_hand_slam(hand)
	if hand.move_ticks > 0:
		_step_hand_move(hand)
		hand.move_ticks -= 1
	_sync_hand_sprite(hand)


func _step_hand_move(hand: HandRuntime) -> void:
	if hand.direction == 0:
		hand.x -= 3.0
	elif hand.direction == 1:
		hand.x += 3.0
	if hand.x < HAND_MIN_X:
		hand.direction = 1
	elif hand.x > HAND_MAX_X:
		hand.direction = 0
	if hand.direction_ticks == 0:
		if _rng.randf() > 0.5:
			hand.direction = (hand.direction + 2) % 3
		else:
			hand.direction = (hand.direction + 1) % 3
		hand.direction_ticks = _rng.randi_range(1, 2) * SOURCE_TICK_RATE
	hand.direction_ticks -= 1


func _step_hand_slam(hand: HandRuntime) -> void:
	if hand.y >= HAND_SLAM_Y:
		screen_shake_requested.emit(10.0)
		hand.hold_ticks -= 1
		if hand.hold_ticks == 0:
			hand.hold_ticks = SOURCE_TICK_RATE
			hand.down_speed = 2.0
			hand.y = 0.0
			hand.move_ticks = _rng.randi_range(3, 6) * SOURCE_TICK_RATE
			_refresh_attack_id()
		return
	hand.y += hand.down_speed
	hand.down_speed += 0.5
	_sync_hand_sprite(hand)
	if not _hand_bounds.is_empty():
		_damage_overlaps(hand.sprite, _hand_bounds[0], _hand_attack, &"attack1", 0)


func _sync_hand_sprite(hand: HandRuntime) -> void:
	hand.sprite.position = Vector2(hand.x, HAND_PARENT_Y + hand.y)


func _step_fire_timer() -> void:
	if _fire_timer <= 0:
		return
	_fire_timer -= 1
	if _fire_timer == 0:
		_spawn_fire_batch(_next_fire_count)
		match _next_fire_count:
			2:
				_next_fire_count = 4
			4:
				_next_fire_count = 6
			_:
				_next_fire_count = 2
		_fire_timer = _rng.randi_range(2, 6) * SOURCE_TICK_RATE


func _spawn_fire_batch(count: int) -> void:
	_fire_spawn_history.append(count)
	for _index in count:
		var fire := FireRuntime.new()
		fire.sprite = _new_sprite(&"attack2", "Fire", 4)
		fire.sprite.offset = FIRE_CANVAS_OFFSET
		fire.sprite.global_position = Vector2(_rng.randf_range(900.0, 1700.0), 520.0)
		_fires.append(fire)


func _step_fires() -> void:
	for index in range(_fires.size() - 1, -1, -1):
		var fire: FireRuntime = _fires[index]
		fire.sprite.frame = fire.frame
		if fire.frame >= FIRE_ACTIVE_FRAMES.x and fire.frame <= FIRE_ACTIVE_FRAMES.y:
			if fire.frame < _fire_bounds.size():
				_damage_overlaps(fire.sprite, _fire_bounds[fire.frame], _fire_attack, &"attack2", fire.frame)
		if fire.frame >= FIRE_DESTROY_FRAME:
			fire.sprite.queue_free()
			_fires.remove_at(index)
		else:
			fire.frame += 1


func _damage_overlaps(
	sprite: AnimatedSprite2D,
	bounds: Rect2,
	attack: Dictionary,
	action: StringName,
	source_frame: int
) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or attack.is_empty():
		return
	var shape := RectangleShape2D.new()
	var sprite_scale := sprite.global_transform.get_scale().abs()
	shape.size = bounds.size * sprite_scale
	var local_center := bounds.get_center() + sprite.offset
	if sprite.flip_h:
		local_center.x = -bounds.get_center().x + sprite.offset.x
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(sprite.global_rotation, sprite.to_global(local_center))
	query.collision_mask = 2
	for result: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target := result.get("collider") as Node2D
		if target == null or not target.is_in_group(&"players") or not target.has_method(&"take_hit"):
			continue
		if int(_target_attack_generation.get(target, -1)) == _attack_generation:
			continue
		_target_attack_generation[target] = _attack_generation
		var knockback := Vector2(attack.get("knockback_velocity", Vector2.ZERO))
		var away := signf(target.global_position.x - _host.global_position.x)
		if is_zero_approx(away):
			away = 1.0
		knockback.x = absf(knockback.x) * away
		target.call(
			&"take_hit",
			int(attack.get("damage", 0)),
			knockback,
			StringName(attack.get("damage_kind", &"magic")),
			_host
		)
		hazard_hit.emit(target, action, source_frame)


func _refresh_attack_id() -> void:
	_attack_generation += 1
	_target_attack_generation.clear()


func _step_heart() -> void:
	match _heart_phase:
		HeartPhase.HIDDEN:
			_heart_timer -= 1
			if _heart_timer <= 0:
				_heart_phase = HeartPhase.FADING_IN
				_heart_fade_tick = 0
		HeartPhase.FADING_IN:
			_heart_fade_tick += 1
			_heart.modulate.a = float(_heart_fade_tick) / float(FADE_TICKS)
			if _heart_fade_tick >= FADE_TICKS:
				_heart_phase = HeartPhase.VULNERABLE
				_heart_timer = _rng.randi_range(2, 5) * SOURCE_TICK_RATE
				_heart.modulate.a = 1.0
				_set_hurtbox_enabled(true)
		HeartPhase.VULNERABLE:
			_heart_timer -= 1
			if _heart_timer <= 0:
				_heart_phase = HeartPhase.FADING_OUT
				_heart_fade_tick = 0
				_set_hurtbox_enabled(false)
		HeartPhase.FADING_OUT:
			_heart_fade_tick += 1
			_heart.modulate.a = 1.0 - float(_heart_fade_tick) / float(FADE_TICKS)
			if _heart_fade_tick >= FADE_TICKS:
				_heart_phase = HeartPhase.HIDDEN
				_heart_timer = _rng.randi_range(5, 11) * SOURCE_TICK_RATE
				_heart.modulate.a = 0.0


func _set_hurtbox_enabled(enabled: bool) -> void:
	if _host == null or _host.collision_shape == null:
		return
	_host.collision_shape.set_deferred(&"disabled", not enabled)


func _step_death_fade() -> void:
	_death_tick += 1
	_host.modulate.a = 1.0 - clampf(float(_death_tick) / float(FADE_TICKS), 0.0, 1.0)
	if _death_tick >= FADE_TICKS:
		_host.call_deferred(&"_complete_source_controlled_death")
