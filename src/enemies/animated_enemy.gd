class_name AnimatedEnemy
extends SandbagEnemy

## Data-driven monster runtime.
##
## Visual frames always come from EnemyAnimationProfile sprite atlases. Source
## combat values come from EnemyCombatCatalog, while Godot physics queries
## replace Flash hit-test calls at the reviewed animation frames.

enum State { IDLE, WALK, ATTACK, HURT, DEATH }

signal source_stage_effect_requested(effect: Dictionary, enemy: AnimatedEnemy)
signal source_screen_shake_requested(strength: float)

const BULLET_SCENE := preload("res://scenes/effects/enemy_bullet.tscn")
const HIT_FLASH_SHADER := preload("res://resources/shaders/enemy_hit_flash.gdshader")
const ZMX1_STRATEGY := preload("res://src/enemies/zmxiyou1_enemy_strategy.gd")
const ZMX1_LOOT_CATALOG := preload("res://src/enemies/zmxiyou1_enemy_loot_catalog.gd")
const ZMX1_LOOT_RUNTIME := preload("res://src/enemies/zmxiyou1_enemy_loot_runtime.gd")
const M18_DEFINITION := preload("res://resources/enemies/zmxiyou1_m18.tres")
const M10_BACK_HIT_SHEET := "res://assets/selected/zmxiyou1/monsters/m10_jiao/effects/BeAttack/sprite.png"
const M10_BACK_HIT_JSON := "res://assets/selected/zmxiyou1/monsters/m10_jiao/effects/BeAttack/sprite.json"
const BOSS_DEAD_SHEET := "res://assets/selected/zmxiyou1/monsters/shared/effects/BossDead/sprite.png"
const BOSS_DEAD_JSON := "res://assets/selected/zmxiyou1/monsters/shared/effects/BossDead/sprite.json"

static var _boss_dead_frames: SpriteFrames
static var _m10_back_hit_frames: SpriteFrames
static var _source_visible_bounds_cache: Dictionary = {}

var _state := State.IDLE
var _current_animation: StringName = &""
var _current_attack_spec: Dictionary = {}
var _attack_actions := PackedStringArray()
var _attack_cooldowns: Dictionary = {}
var _attack_hits: Dictionary = {}
var _spawned_projectile_frames := PackedInt32Array()
var _spawned_warning_frames := PackedInt32Array()
var _hurt_timer := 0.0
var _player_ref: CharacterBody2D
var _facing := -1
var _invulnerable := false
var _contact_action: StringName = &""
var _source_tick_accumulator := 0.0
var _source_tick := 0
var _combat_phase := 1
var _source_high_level_variant := false
var _source_attack_variant := -1
var _source_motion_velocity := Vector2.ZERO
var _source_invulnerability_ticks := 0
var _source_target_acquired := false
var _source_provoked := false
var _source_patrol_tick := 0
var _source_patrol_direction := -1
var _source_patrol_stop_tick := 72
var _source_patrol_reset_tick := 96
var _source_patrol_pauses := false
var _source_before_despawn_called := false
var _source_death_started_called := false
var _boss_dead_spawned := false
var _source_loot_dropped := false
var _ai_rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()
var _summoned_source_child: AnimatedEnemy
var _grabbed_target: Node2D
var _peng_flying := false
var _peng_floor_ticks := 240
var _peng_fly_ticks := 720
var _peng_egg_active := false
var _peng_reburning := false
var _peng_egg_ticks := 0
var _peng_egg_hits_remaining := 0

var _bullet_cache: Dictionary = {}
var _warning_cache: Dictionary = {}
var _event_dispatcher: EnemyAnimationEventDispatcher
var _hit_flash_material: ShaderMaterial
var _source_controller: Node

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = get_node_or_null("AttackArea") as Area2D


func _ready() -> void:
	super._ready()
	if definition == null or definition.animation_profile == null or animated_sprite == null:
		return
	_configure_source_runtime_variant()
	_configure_source_lifecycle()
	sprite.visible = false
	_load_animations()
	_configure_hit_flash()
	_attach_source_controller()
	_disable_legacy_attack_area()
	_attack_actions = _find_attack_actions()
	_contact_action = _find_contact_action()
	_preload_projectiles()
	_ai_rng.seed = hash("%s:%s" % [definition.enemy_id, spawn_id])
	_loot_rng.seed = hash("loot:%s:%s" % [definition.enemy_id, spawn_id])

	_event_dispatcher = EnemyAnimationEventDispatcher.new()
	add_child(_event_dispatcher)
	_event_dispatcher.source_event.connect(_on_source_event)
	_event_dispatcher.bind(animated_sprite, definition.animation_profile)
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	var source_controls_ai := (
		_source_controller != null
		and _source_controller.has_method(&"blocks_host_ai")
		and bool(_source_controller.call(&"blocks_host_ai"))
	)
	if not source_controls_ai:
		_switch_state(State.IDLE)
		_update_ai()


func _load_animations() -> void:
	var profile := definition.animation_profile
	animated_sprite.sprite_frames = profile.build_sprite_frames()
	animated_sprite.scale = definition.visual_scale
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _physics_process(delta: float) -> void:
	if definition == null or animated_sprite == null:
		return
	if not _uses_flight_physics() and not is_on_floor():
		velocity.y += GRAVITY * delta
	if _state == State.WALK and stun_seconds <= 0.0:
		velocity.x = _runtime_move_speed() * _facing
	elif _state == State.ATTACK and not is_zero_approx(_source_motion_velocity.x):
		velocity.x = _source_motion_velocity.x
	else:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	hit_flash_seconds = maxf(0.0, hit_flash_seconds - delta)
	stun_seconds = maxf(0.0, stun_seconds - delta)
	if _hit_flash_material != null:
		_hit_flash_material.set_shader_parameter("flash_amount", 1.0 if hit_flash_seconds > 0.0 else 0.0)

	if health <= 0 and _state != State.DEATH and not _peng_egg_active:
		_switch_state(State.DEATH)
	_source_tick_accumulator += delta
	while _source_tick_accumulator >= 1.0 / ZMX1_STRATEGY.SOURCE_TICK_RATE:
		_source_tick_accumulator -= 1.0 / ZMX1_STRATEGY.SOURCE_TICK_RATE
		_advance_source_tick()
	if stun_seconds > 0.0:
		velocity.x = 0.0
	move_and_slide()
	_process_contact_attack()
	_process_contact_projectile()


func _advance_source_tick() -> void:
	if _source_invulnerability_ticks > 0:
		_source_invulnerability_ticks -= 1
		if _source_invulnerability_ticks == 0 and _state != State.DEATH:
			_invulnerable = false
	for action: Variant in _attack_cooldowns.keys():
		_attack_cooldowns[action] = maxi(0, int(_attack_cooldowns[action]) - 1)
	if _source_controller != null and _source_controller.has_method(&"source_tick"):
		_source_controller.call(&"source_tick", _source_tick)
	var lifecycle_blocks_ai := _update_peng_lifecycle()
	if (
		_source_controller != null
		and _source_controller.has_method(&"blocks_host_ai")
		and bool(_source_controller.call(&"blocks_host_ai"))
	):
		lifecycle_blocks_ai = true
	_update_source_phase()
	if stun_seconds <= 0.0 and not lifecycle_blocks_ai:
		_update_ai()
	_source_tick += 1


func _update_ai() -> void:
	if _state in [State.DEATH, State.HURT, State.ATTACK]:
		if _state == State.HURT and _hurt_timer <= 0.0:
			_switch_state(State.IDLE)
		return
	_find_player()
	if _player_ref == null:
		_switch_state(State.IDLE)
		return
	var delta_to_player := _player_ref.global_position - global_position
	var horizontal_distance := absf(delta_to_player.x)
	var reviewed_strategy := ZMX1_STRATEGY.has_reviewed_strategy(definition.animation_profile)
	if reviewed_strategy and not _source_target_acquired:
		if (
			definition.animation_profile.source_monster_id != &"M01"
			and horizontal_distance <= definition.detection_range
			and absf(delta_to_player.y) <= definition.default_attack_range
		):
			_source_target_acquired = true
	elif not reviewed_strategy and horizontal_distance > definition.detection_range:
		_switch_state(State.IDLE)
		return
	_facing = -1 if delta_to_player.x < 0.0 else 1
	animated_sprite.flip_h = _facing > 0
	var decision: Dictionary = ZMX1_STRATEGY.decide(
		definition.animation_profile,
		horizontal_distance,
		_source_tick,
		_attack_cooldowns,
		_combat_phase,
		_source_high_level_variant,
		_ai_rng,
		{
			"flying": _peng_flying,
			"vertical_distance": absf(delta_to_player.y),
			"vertical_delta": delta_to_player.y,
			"target_acquired": _source_target_acquired,
			"provoked": _source_provoked,
		}
	)
	if bool(decision.get("reviewed", false)):
		_apply_source_vertical_decision(decision)
		var source_action := StringName(decision.get("action", &""))
		if source_action != &"" and _start_attack(source_action):
			return
		if bool(decision.get("patrol", false)):
			_update_source_patrol()
			return
		if bool(decision.get("move", false)):
			if bool(decision.get("move_away", false)):
				_facing *= -1
				animated_sprite.flip_h = _facing > 0
			_switch_state(State.WALK)
			velocity.x = _runtime_move_speed() * _facing
		else:
			_switch_state(State.IDLE)
		return

	var attack := _select_attack(horizontal_distance)
	if attack != &"":
		_start_attack(attack)
		return
	var closest_range := _closest_ready_attack_range()
	if horizontal_distance > closest_range:
		_switch_state(State.WALK)
		velocity.x = _runtime_move_speed() * _facing
	else:
		_switch_state(State.IDLE)


func _select_attack(distance: float) -> StringName:
	var selected: StringName = &""
	var selected_priority := -2147483648
	for raw_action: String in _attack_actions:
		var action := StringName(raw_action)
		if float(_attack_cooldowns.get(action, 0.0)) > 0.0:
			continue
		var spec := _merged_attack_spec(action)
		if spec.is_empty():
			continue
		var min_range := float(spec.get("min_range", 0.0))
		var max_range := float(spec.get("max_range", definition.default_attack_range))
		if distance < min_range or distance > max_range:
			continue
		var priority := int(spec.get("priority", 0))
		if selected == &"" or priority > selected_priority:
			selected = action
			selected_priority = priority
	return selected


func _closest_ready_attack_range() -> float:
	var result := definition.default_attack_range
	for raw_action: String in _attack_actions:
		var action := StringName(raw_action)
		var spec := definition.animation_profile.get_spec(action)
		result = maxf(result, float(spec.get("preferred_range", 0.0)))
	return result


func _start_attack(action: StringName, chained := false) -> bool:
	if not _has_animation(action):
		return false
	var spec := _merged_attack_spec(action)
	if spec.is_empty():
		return false
	_state = State.ATTACK
	_current_attack_spec = spec
	_attack_hits.clear()
	_spawned_projectile_frames.clear()
	_spawned_warning_frames.clear()
	_source_motion_velocity = Vector2.ZERO
	velocity.x = 0.0
	_source_invulnerability_ticks = ZMX1_STRATEGY.get_invulnerability_ticks(
		definition.animation_profile, action
	)
	if _source_invulnerability_ticks > 0:
		_invulnerable = true
	elif _state != State.DEATH:
		_invulnerable = false
	if not chained:
		var cooldown_key := ZMX1_STRATEGY.get_cooldown_key(definition.animation_profile, action)
		_attack_cooldowns[cooldown_key] = ZMX1_STRATEGY.get_cooldown_ticks(
			definition.animation_profile,
			action,
			float(spec.get("cooldown", definition.default_attack_cooldown)),
			_source_high_level_variant
		)
	if animated_sprite.animation == action:
		animated_sprite.stop()
		animated_sprite.frame = 0
	_play_anim(action)
	_on_animation_frame_changed()
	return true


func _switch_state(new_state: State) -> void:
	if _state == State.DEATH and new_state != State.DEATH:
		return
	if _state == new_state and new_state in [State.IDLE, State.WALK]:
		return
	if _current_animation == &"attack5" and new_state != State.ATTACK:
		_release_grabbed_target()
	_state = new_state
	if new_state != State.ATTACK:
		_source_motion_velocity = Vector2.ZERO
		if _source_invulnerability_ticks <= 0:
			_invulnerable = false
	_current_attack_spec = {}
	_attack_hits.clear()
	_spawned_projectile_frames.clear()
	_spawned_warning_frames.clear()
	match new_state:
		State.IDLE:
			_play_anim(_idle_action())
			velocity.x = 0.0
		State.WALK:
			_play_anim(_move_action())
		State.HURT:
			_invulnerable = false
			var hurt_action := &"hurt"
			if _has_animation(hurt_action):
				_play_anim(hurt_action)
				_hurt_timer = _animation_duration(hurt_action)
			else:
				_hurt_timer = 0.2
			velocity.x = 0.0
		State.DEATH:
			_invulnerable = true
			velocity.x = 0.0
			collision_shape.set_deferred(&"disabled", true)
			_notify_source_death_started()
			if (
				_source_controller != null
				and _source_controller.has_method(&"begin_death")
				and bool(_source_controller.call(&"begin_death"))
			):
				return
			if _has_animation(&"death"):
				_play_anim(&"death")
			else:
				_despawn_after_death()
		State.ATTACK:
			pass


func _play_anim(action: StringName) -> void:
	if not _has_animation(action):
		action = definition.animation_profile.default_animation
	if not _has_animation(action):
		return
	_current_animation = action
	animated_sprite.position = definition.visual_offset + definition.animation_profile.get_offset(action)
	animated_sprite.play(action)


func _on_animation_frame_changed() -> void:
	if _state != State.ATTACK:
		return
	var frame := animated_sprite.frame
	if _has_projectile(_current_animation):
		if bool(_current_attack_spec.get("projectile_contact_trigger", false)):
			return
		var spawn_frame := int(_current_attack_spec.get("projectile_spawn_frame", -1))
		if spawn_frame >= 0 and frame == spawn_frame and frame not in _spawned_projectile_frames:
			_spawn_projectile(_current_animation, frame)
		return
	if _is_event_driven_damage_action(_current_animation):
		return
	var active_frames := Vector2i(_current_attack_spec.get("active_frame_range", Vector2i(-1, -1)))
	if frame >= active_frames.x and frame <= active_frames.y:
		_perform_melee_hits(frame)


func _on_animation_finished() -> void:
	if _peng_egg_active:
		if _current_animation == &"egg":
			animated_sprite.pause()
			return
		if _current_animation == &"reburn":
			_finish_peng_reburn()
			return
	match _state:
		State.DEATH:
			_despawn_after_death()
		State.HURT:
			if health > 0:
				_switch_state(State.IDLE)
		State.ATTACK:
			var next := definition.animation_profile.get_next_animation(_current_animation)
			if str(next).begins_with("attack") and _start_attack(next, true):
				return
			_switch_state(State.IDLE)


func _perform_melee_hits(frame: int) -> void:
	var hitboxes := _melee_hitboxes_for_frame(frame)
	var targets: Dictionary = {}
	for hitbox: Rect2 in hitboxes:
		var shape := RectangleShape2D.new()
		shape.size = hitbox.size
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, global_position + hitbox.get_center())
		query.collision_mask = 2
		query.exclude = [get_rid()]
		for result: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 16):
			var target := result.get("collider") as Node2D
			if target == null or not target.is_in_group(&"players") or not target.has_method(&"take_hit"):
				continue
			targets[target] = true
	for raw_target: Variant in targets:
		var target := raw_target as Node2D
		if target != null and _can_hit_target(target, frame):
			_apply_attack_hit(target, frame)


func _melee_hitboxes_for_frame(frame: int) -> Array[Rect2]:
	if bool(_current_attack_spec.get("melee_geometry_reviewed", false)):
		return _reviewed_melee_hitboxes_for_frame(frame)
	return [_fallback_melee_hitbox()]


func _reviewed_melee_hitboxes_for_frame(frame: int) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var frames: Variant = _current_attack_spec.get("melee_frame_hitboxes", [])
	if not frames is Array:
		return result
	var frame_boxes := frames as Array
	if frame < 0 or frame >= frame_boxes.size() or not frame_boxes[frame] is Array:
		return result
	var registration := Vector2(
		_current_attack_spec.get("melee_registration_to_atlas_center", Vector2.ZERO)
	)
	var visual_scale := animated_sprite.scale.abs()
	var horizontal_draw_sign := -float(_facing)
	var boxes := frame_boxes[frame] as Array
	for raw_box: Variant in boxes:
		if not raw_box is Array or (raw_box as Array).size() < 4:
			continue
		var values := raw_box as Array
		var source_box := Rect2(
			float(values[0]), float(values[1]), float(values[2]), float(values[3])
		)
		if source_box.size.x <= 0.0 or source_box.size.y <= 0.0:
			continue
		var center := (source_box.get_center() + registration) * visual_scale
		center.x *= horizontal_draw_sign
		center += animated_sprite.position
		result.append(Rect2(center - source_box.size * visual_scale * 0.5, source_box.size * visual_scale))
	return result


func _fallback_melee_hitbox() -> Rect2:
	var size := Vector2(_current_attack_spec.get("hitbox_size", definition.melee_hitbox_size))
	var offset := Vector2(_current_attack_spec.get("hitbox_offset", definition.melee_hitbox_offset))
	offset.x = absf(offset.x) * _facing
	return Rect2(offset - size * 0.5, size)


func _can_hit_target(target: Node2D, frame: int) -> bool:
	var record: Dictionary = _attack_hits.get(target, {"count": 0, "last_frame": -999999})
	if int(record["count"]) >= int(_current_attack_spec.get("hit_max_count", 1)):
		return false
	return frame - int(record["last_frame"]) >= int(_current_attack_spec.get("rehit_interval_frames", 999))


func _apply_attack_hit(target: Node2D, frame: int) -> void:
	var record: Dictionary = _attack_hits.get(target, {"count": 0, "last_frame": -999999})
	record["count"] = int(record["count"]) + 1
	record["last_frame"] = frame
	_attack_hits[target] = record
	var knockback := Vector2(_current_attack_spec.get("knockback_velocity", Vector2.ZERO))
	knockback.x = absf(knockback.x) * _facing
	target.take_hit(
		int(_current_attack_spec.get("damage", 0)),
		knockback,
		StringName(_current_attack_spec.get("damage_kind", &"physical")),
		self
	)
	_apply_status_effects(target, _current_attack_spec)


func _process_contact_attack() -> void:
	if _contact_action == &"" or _current_animation != _contact_action:
		return
	var previous_spec := _current_attack_spec
	_current_attack_spec = _merged_attack_spec(_contact_action)
	_perform_melee_hits(animated_sprite.frame)
	_current_attack_spec = previous_spec


func _apply_source_vertical_decision(decision: Dictionary) -> void:
	if bool(decision.get("vertical_stop", false)):
		velocity.y = 0.0
		return
	if not decision.has("flight_vertical_target_delta"):
		return
	var target_delta := float(decision["flight_vertical_target_delta"])
	var acceleration := float(decision.get("vertical_acceleration", 0.0))
	var maximum := float(decision.get("vertical_max_speed", 0.0))
	if target_delta > 0.0 and velocity.y < maximum:
		velocity.y = minf(maximum, velocity.y + acceleration)
	elif target_delta <= 0.0 and velocity.y > -maximum:
		velocity.y = maxf(-maximum, velocity.y - acceleration)


func _update_source_patrol() -> void:
	_source_patrol_tick += 1
	if _source_patrol_tick == 12:
		var viewport_center := get_viewport_rect().get_center().x
		if global_position.x < viewport_center - 400.0:
			_source_patrol_direction = 1
		elif global_position.x > viewport_center + 400.0:
			_source_patrol_direction = -1
		else:
			_source_patrol_direction = -1 if _ai_rng.randi_range(0, 99) < 50 else 1
		_source_patrol_stop_tick = 72 if _ai_rng.randi_range(0, 99) < 50 else 96
		_source_patrol_reset_tick = _source_patrol_stop_tick + _ai_rng.randi_range(0, 29)
		_source_patrol_pauses = _ai_rng.randi_range(0, 99) < 50
	if _source_patrol_tick >= _source_patrol_reset_tick:
		_source_patrol_tick = 0
		_switch_state(State.IDLE)
		return
	if _source_patrol_tick < 12 or (
		_source_patrol_tick >= _source_patrol_stop_tick and _source_patrol_pauses
	):
		_switch_state(State.IDLE)
		return
	_facing = _source_patrol_direction
	animated_sprite.flip_h = _facing > 0
	_switch_state(State.WALK)
	velocity.x = _runtime_move_speed() * _facing


func _on_source_event(action: StringName, event: Dictionary) -> void:
	if action != _current_animation:
		return
	var event_id := StringName(event.get("id", &""))
	var event_types := PackedStringArray(event.get("types", PackedStringArray()))
	var source_code := str(event.get("source_code", ""))
	_emit_source_screen_shakes(source_code)
	if _state == State.DEATH and "dropAura()" in source_code:
		_spawn_source_loot()
	if event_id == &"visibility":
		animated_sprite.visible = "visible = true" in source_code
		return
	if event_id == &"spawn_object" and _state == State.DEATH:
		if "BossDead" in source_code:
			_spawn_boss_dead_effect()
		return
	if _state != State.ATTACK:
		return
	if event_id == &"refresh_attack_id":
		_attack_hits.clear()
	elif event_id == &"set_invulnerable":
		_invulnerable = true
	elif event_id == &"projectile_warning":
		_spawn_projectile_warning(action, int(event.get("frame", animated_sprite.frame)))
		return
	elif event_id == &"grab_check":
		if not _try_grab_target():
			_complete_source_action.call_deferred(action)
		return
	elif event_id == &"life_steal_tick":
		_process_life_steal_tick()
		return
	elif event_id == &"motion" and action == &"attack1" and definition.animation_profile.source_monster_id == &"M18":
		_source_motion_velocity.x = 20.0 * EnemyCombatCatalog.SOURCE_TICK_RATE * _facing
	elif event_id == &"action_transition" and action == &"reburn" and _peng_egg_active:
		_finish_peng_reburn()
		return
	if _has_projectile(action) and (
		"bullet_spawn" in event_types or event_id in [&"fire_hit", &"doHit1", &"doHit2", &"doHit3", &"doHit4"]
	):
		_spawn_projectile(action, int(event.get("frame", animated_sprite.frame)))
	# `types` preserves every label from the exported ActionScript for
	# provenance.  A normalized timeline_branch can therefore still contain
	# the source label `action_transition`; only the canonical event id is an
	# unconditional top-level action completion.
	if event_id == &"action_transition":
		_release_grabbed_target()
		_complete_source_action.call_deferred(action)


func _emit_source_screen_shakes(source_code: String) -> void:
	const MARKER := "vControllor.shake("
	var cursor := 0
	while cursor < source_code.length():
		var marker_start := source_code.find(MARKER, cursor)
		if marker_start < 0:
			return
		var value_start := marker_start + MARKER.length()
		var value_end := source_code.find(")", value_start)
		if value_end < 0:
			return
		var source_value := source_code.substr(value_start, value_end - value_start).strip_edges()
		if source_value.is_valid_float():
			source_screen_shake_requested.emit(source_value.to_float())
		cursor = value_end + 1


func _complete_source_action(action: StringName) -> void:
	if _state != State.ATTACK or _current_animation != action:
		return
	var next := definition.animation_profile.get_next_animation(action)
	if str(next).begins_with("attack") and _start_attack(next, true):
		return
	_switch_state(State.IDLE)


func _preload_projectiles() -> void:
	for raw_action: Variant in definition.animation_profile.actions:
		var action := StringName(raw_action)
		var spec := definition.animation_profile.get_spec(action)
		var sheet_path := str(spec.get("bullet_sprite_sheet", ""))
		var json_path := str(spec.get("bullet_sprite_json", ""))
		if sheet_path.is_empty() or json_path.is_empty():
			continue
		var frames := SpriteFrames.new()
		frames.remove_animation(&"default")
		var animation_name := StringName("projectile")
		var count := SpriteSheetAtlas.append_animation(
			frames,
			animation_name,
			sheet_path,
			json_path,
			float(spec.get("bullet_fps", spec.get("fps", 24.0))),
			bool(spec.get("bullet_loop", false))
		)
		if count <= 0:
			continue
		_bullet_cache[action] = {
			"frames": frames,
			"animation": animation_name,
			"bounds": SpriteSheetAtlas.build_visible_bounds(sheet_path, json_path),
		}
		var warning_sheet := str(spec.get("bullet_pre_sprite_sheet", ""))
		var warning_json := str(spec.get("bullet_pre_sprite_json", ""))
		if warning_sheet.is_empty() or warning_json.is_empty():
			continue
		var warning_frames := SpriteFrames.new()
		warning_frames.remove_animation(&"default")
		var warning_name := StringName("warning")
		var warning_count := SpriteSheetAtlas.append_animation(
			warning_frames,
			warning_name,
			warning_sheet,
			warning_json,
			float(spec.get("bullet_pre_fps", 24.0)),
			false
		)
		if warning_count > 0:
			_warning_cache[action] = {"frames": warning_frames, "animation": warning_name}


func _spawn_projectile(action: StringName, source_frame: int) -> void:
	var origin := global_position
	if definition.animation_profile.source_monster_id == &"M09" and action in [&"attack1", &"attack3"]:
		origin += Vector2(_ai_rng.randf_range(-100.0, 100.0), -100.0 - _ai_rng.randf_range(0.0, 150.0))
	if bool(_current_attack_spec.get("projectile_target_x", false)):
		_find_player()
		if _player_ref != null:
			origin.x = _player_ref.global_position.x
	if bool(_current_attack_spec.get("projectile_target_y", false)):
		_find_player()
		if _player_ref != null:
			origin.y = _player_ref.global_position.y
	_spawn_projectile_from(
		action,
		source_frame,
		_current_attack_spec,
		origin,
		_facing
	)


func _spawn_projectile_from(
	action: StringName, source_frame: int, attack_spec: Dictionary, origin: Vector2, facing: int
) -> void:
	if source_frame in _spawned_projectile_frames:
		return
	var cached: Dictionary = _bullet_cache.get(action, {})
	if cached.is_empty():
		return
	_spawned_projectile_frames.append(source_frame)
	var bullet := BULLET_SCENE.instantiate() as EnemyBullet
	get_parent().add_child(bullet)
	var spawn_offset := Vector2(attack_spec.get("projectile_spawn_offset", Vector2.ZERO))
	if bool(attack_spec.get("projectile_spawn_offset_mirrors", true)):
		spawn_offset.x *= facing
	bullet.global_position = origin + spawn_offset
	bullet.scale = definition.visual_scale
	var configured := bullet.configure(
		cached["frames"],
		StringName(cached["animation"]),
		facing,
		self,
		attack_spec,
		cached["bounds"]
	)
	if not configured:
		bullet.queue_free()


func _spawn_projectile_warning(action: StringName, source_frame: int) -> void:
	if source_frame in _spawned_warning_frames:
		return
	var cached: Dictionary = _warning_cache.get(action, {})
	if cached.is_empty():
		_spawn_projectile(action, source_frame)
		return
	_spawned_warning_frames.append(source_frame)
	var attack_spec := _current_attack_spec.duplicate(true)
	var spawn_facing := _facing
	var origin := global_position
	_find_player()
	if _player_ref != null:
		if bool(attack_spec.get("projectile_warning_target_x", false)):
			origin.x = _player_ref.global_position.x
		if bool(attack_spec.get("projectile_warning_target_y", false)):
			origin.y = _player_ref.global_position.y
	if attack_spec.has("projectile_warning_ground_y"):
		origin.y = float(attack_spec["projectile_warning_ground_y"])
	var warning_offset := Vector2(attack_spec.get("projectile_warning_offset", Vector2.ZERO))
	if bool(attack_spec.get("projectile_warning_offset_mirrors", false)):
		warning_offset.x *= spawn_facing
	origin += warning_offset
	if bool(attack_spec.get("projectile_warning_hide_source", false)):
		animated_sprite.visible = false
	var effect := AnimatedSprite2D.new()
	effect.sprite_frames = cached["frames"]
	effect.flip_h = spawn_facing > 0
	effect.scale = definition.visual_scale
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 3
	get_parent().add_child(effect)
	effect.global_position = origin
	effect.animation_finished.connect(
		_on_projectile_warning_finished.bind(effect, action, source_frame, attack_spec, origin, spawn_facing),
		CONNECT_ONE_SHOT
	)
	effect.play(StringName(cached["animation"]))


func _on_projectile_warning_finished(
	effect: AnimatedSprite2D,
	action: StringName,
	source_frame: int,
	attack_spec: Dictionary,
	origin: Vector2,
	facing: int
) -> void:
	if is_instance_valid(effect):
		effect.queue_free()
	if bool(attack_spec.get("projectile_warning_hide_source", false)) and is_instance_valid(animated_sprite):
		animated_sprite.visible = true
	if not is_inside_tree() or _state == State.DEATH:
		return
	_spawn_projectile_from(action, source_frame + 100000, attack_spec, origin, facing)


func _process_contact_projectile() -> void:
	if (
		_state != State.ATTACK
		or not bool(_current_attack_spec.get("projectile_contact_trigger", false))
		or not _has_projectile(_current_animation)
	):
		return
	var shape := RectangleShape2D.new()
	shape.size = definition.collision_size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + collision_shape.position)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	for result: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target := result.get("collider") as Node2D
		if target == null or not target.is_in_group(&"players"):
			continue
		var origin := target.global_position + Vector2(
			_current_attack_spec.get("projectile_contact_target_offset", Vector2.ZERO)
		)
		_spawn_projectile_from(
			_current_animation,
			900000 + animated_sprite.frame,
			_current_attack_spec,
			origin,
			_facing
		)
		_complete_source_action.call_deferred(_current_animation)
		return


func _merged_attack_spec(action: StringName) -> Dictionary:
	var source_spec := EnemyCombatCatalog.resolve_attack(
		definition.animation_profile, action, _source_attack_variant
	)
	if source_spec.is_empty():
		return {}
	# Animation profile fields only describe delivery/range/collision overrides;
	# reviewed source fields remain authoritative for damage semantics.
	var result := definition.animation_profile.get_spec(action).duplicate(true)
	result.merge(source_spec, true)
	return result


func _find_attack_actions() -> PackedStringArray:
	var result := PackedStringArray()
	for action: String in EnemyCombatCatalog.get_attack_actions(definition.animation_profile):
		if action.begins_with("attack"):
			result.append(action)
	result.sort()
	return result


func _find_contact_action() -> StringName:
	for action: String in EnemyCombatCatalog.get_attack_actions(definition.animation_profile):
		if not action.begins_with("attack"):
			return StringName(action)
	return &""


func _has_projectile(action: StringName) -> bool:
	return _bullet_cache.has(action)


func _has_animation(action: StringName) -> bool:
	return (
		animated_sprite != null
		and animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(action)
	)


func _idle_action() -> StringName:
	if _peng_flying and _has_animation(&"fly"):
		return &"fly"
	if _combat_phase >= 2 and _has_animation(&"idle2"):
		return &"idle2"
	if _has_animation(&"idle1"):
		return &"idle1"
	var preferred := definition.animation_profile.default_animation
	return preferred if _has_animation(preferred) else &"idle"


func _move_action() -> StringName:
	if _peng_flying and _has_animation(&"fly"):
		return &"fly"
	var idle := str(_idle_action())
	var suffix := idle.trim_prefix("idle")
	var preferred := StringName("move%s" % suffix)
	return preferred if _has_animation(preferred) else &"move"


func _runtime_move_speed() -> float:
	return ZMX1_STRATEGY.get_move_speed(definition.animation_profile, definition.move_speed)


func _uses_flight_physics() -> bool:
	if definition.animation_profile.source_monster_id == &"M09":
		return _peng_flying
	return ZMX1_STRATEGY.is_flying(definition.animation_profile)


func _configure_source_runtime_variant() -> void:
	var context_stats := ZMX1_STRATEGY.get_source_context_stats(
		definition.animation_profile, source_stage, source_level
	)
	_apply_source_runtime_stats(context_stats)
	if definition.source_level_threshold >= 0:
		var minimum_level := definition.source_default_player_level
		var found_level := false
		for candidate: Node in get_tree().get_nodes_in_group(&"players"):
			var value: Variant = candidate.get("level")
			if value == null:
				continue
			var candidate_level := maxi(1, int(value))
			minimum_level = mini(minimum_level, candidate_level) if found_level else candidate_level
			found_level = true
		_source_high_level_variant = minimum_level > definition.source_level_threshold
		var level_stats := (
			definition.source_high_level_stats
			if _source_high_level_variant
			else definition.source_low_level_stats
		)
		_apply_source_runtime_stats(level_stats)
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()


func _apply_source_runtime_stats(stats: Dictionary) -> void:
	if stats.is_empty():
		return
	if stats.has("max_health"):
		actor_property.max_health = int(stats["max_health"])
		health = actor_property.get_effective_max_health()
	if stats.has("defense"):
		actor_property.defense = int(stats["defense"])
	if stats.has("is_boss"):
		runtime_is_boss = bool(stats["is_boss"])
		if runtime_is_boss:
			add_to_group(&"bosses")
		else:
			remove_from_group(&"bosses")
	_source_attack_variant = int(stats.get("source_attack_variant", -1))


func _configure_source_lifecycle() -> void:
	if definition.animation_profile.source_monster_id != &"M09":
		return
	_peng_flying = false
	_peng_floor_ticks = 240
	_peng_fly_ticks = 720
	_peng_egg_hits_remaining = _peng_required_egg_hits()


func _update_peng_lifecycle() -> bool:
	if definition.animation_profile.source_monster_id != &"M09":
		return false
	if _peng_egg_active:
		if _state == State.DEATH:
			return true
		if not _peng_reburning:
			_peng_egg_ticks += 1
			if _peng_egg_ticks >= 168:
				_begin_peng_reburn()
				_spawn_peng_fire()
			elif _peng_egg_ticks % 24 == 0:
				_spawn_peng_fire()
		return true
	if _state == State.DEATH:
		return true
	if _peng_flying:
		_peng_fly_ticks -= 1
		if _peng_fly_ticks <= 0:
			_peng_flying = false
			global_position.y = 150.0
			velocity.y = 0.0
			_peng_floor_ticks = _ai_rng.randi_range(10, 19) * 24
			if _state == State.IDLE:
				_play_anim(_idle_action())
			elif _state == State.WALK:
				_play_anim(_move_action())
		elif _state not in [State.ATTACK, State.HURT]:
			velocity.y = signf(150.0 - global_position.y) * 3.0 * EnemyCombatCatalog.SOURCE_TICK_RATE
	else:
		_peng_floor_ticks -= 1
		if _peng_floor_ticks <= 0:
			_peng_flying = true
			velocity.y = -10.0 * EnemyCombatCatalog.SOURCE_TICK_RATE
			_peng_fly_ticks = _ai_rng.randi_range(10, 19) * 24
			# Monster9.step() calls setYourFather(72) on the takeoff tick.
			_source_invulnerability_ticks = 72
			_invulnerable = true
			if _state in [State.IDLE, State.WALK]:
				_play_anim(&"fly")
	return false


func _peng_required_egg_hits() -> int:
	return 10 if get_tree().get_nodes_in_group(&"players").size() >= 2 else 5


func _enter_peng_egg() -> void:
	_peng_egg_active = true
	_peng_reburning = false
	_peng_egg_ticks = 1
	_peng_egg_hits_remaining = _peng_required_egg_hits()
	_peng_flying = false
	_invulnerable = false
	_state = State.ATTACK
	_current_attack_spec = {}
	_source_motion_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	_play_anim(&"egg")
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()


func _begin_peng_reburn() -> void:
	if not _peng_egg_active or _state == State.DEATH:
		return
	_peng_reburning = true
	_peng_egg_ticks = 0
	health = actor_property.get_effective_max_health()
	_peng_egg_hits_remaining = _peng_required_egg_hits()
	_state = State.ATTACK
	_play_anim(&"reburn")
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()


func _finish_peng_reburn() -> void:
	if not _peng_egg_active or _state == State.DEATH:
		return
	_peng_egg_active = false
	_peng_reburning = false
	_peng_egg_ticks = 0
	_switch_state(State.IDLE)


func _spawn_peng_fire() -> void:
	if not _bullet_cache.has(&"attack1"):
		return
	var attack_spec := _merged_attack_spec(&"attack1")
	var origin := global_position + Vector2(
		_ai_rng.randf_range(-100.0, 100.0),
		-100.0 - _ai_rng.randf_range(0.0, 150.0)
	)
	_spawn_projectile_from(&"attack1", 2000000 + _source_tick, attack_spec, origin, _facing)


func _apply_status_effects(target: Node2D, attack_spec: Dictionary) -> void:
	if not target.has_method(&"apply_combat_status"):
		return
	for raw_status: Variant in attack_spec.get("status_effects", []):
		if raw_status is Dictionary:
			target.call(&"apply_combat_status", raw_status, self)


func _is_event_driven_damage_action(action: StringName) -> bool:
	for raw_event: Variant in definition.animation_profile.get_source_events(action):
		if raw_event is Dictionary:
			var event_id := StringName((raw_event as Dictionary).get("id", &""))
			if event_id in [&"grab_check", &"life_steal_tick"]:
				return true
	return false


func _try_grab_target() -> bool:
	_release_grabbed_target()
	for candidate: Node in get_tree().get_nodes_in_group(&"players"):
		if not candidate is Node2D:
			continue
		var target := candidate as Node2D
		if absf(target.global_position.x - global_position.x) > 200.0:
			continue
		if target.get("health") != null and int(target.get("health")) <= 0:
			continue
		_grabbed_target = target
		if target.has_method(&"set_external_control_locked"):
			target.call(&"set_external_control_locked", self, true)
		if target.has_method(&"set_external_visual_hidden"):
			target.call(&"set_external_visual_hidden", self, true)
		else:
			target.visible = false
		return true
	return false


func _process_life_steal_tick() -> void:
	if _grabbed_target == null or not is_instance_valid(_grabbed_target):
		return
	if _grabbed_target.has_method(&"take_hit"):
		_grabbed_target.call(&"take_hit", 50, Vector2.ZERO, &"magic", self)
	if health <= 0:
		return
	health += 500
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()


func _release_grabbed_target() -> void:
	if _grabbed_target == null:
		return
	if is_instance_valid(_grabbed_target):
		if _grabbed_target.has_method(&"set_external_control_locked"):
			_grabbed_target.call(&"set_external_control_locked", self, false)
		if _grabbed_target.has_method(&"set_external_visual_hidden"):
			_grabbed_target.call(&"set_external_visual_hidden", self, false)
		else:
			_grabbed_target.visible = true
	_grabbed_target = null


func _exit_tree() -> void:
	_release_grabbed_target()


func _update_source_phase() -> void:
	if definition.animation_profile.source_monster_id != &"M19" or _combat_phase >= 2:
		return
	var maximum := maxi(1, actor_property.get_effective_max_health())
	if float(health) / float(maximum) >= 0.7:
		return
	_combat_phase = 2
	_spawn_m19_source_child()
	if _state == State.IDLE:
		_play_anim(_idle_action())
	elif _state == State.WALK:
		_play_anim(_move_action())


func _spawn_m19_source_child() -> void:
	if _summoned_source_child != null and is_instance_valid(_summoned_source_child):
		return
	var enemy_scene := load("res://scenes/enemies/animated_enemy.tscn") as PackedScene
	if enemy_scene == null or get_parent() == null:
		return
	var child := enemy_scene.instantiate() as AnimatedEnemy
	if child == null:
		return
	child.definition = M18_DEFINITION
	child.spawn_id = StringName("%s_m18" % spawn_id)
	child.set_source_stage_context(source_stage, source_level)
	get_parent().add_child(child)
	child.global_position = global_position
	_summoned_source_child = child


func _animation_duration(action: StringName) -> float:
	var spec := definition.animation_profile.get_spec(action)
	return float(spec.get("frame_count", 1)) / maxf(1.0, float(spec.get("fps", 24.0)))


func _find_player() -> void:
	if _player_ref != null and is_instance_valid(_player_ref):
		return
	var players := get_tree().get_nodes_in_group(&"players")
	if not players.is_empty():
		_player_ref = players[0] as CharacterBody2D


func _disable_legacy_attack_area() -> void:
	if attack_area == null:
		return
	attack_area.monitoring = false
	attack_area.monitorable = false
	for child: Node in attack_area.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).disabled = true


func _configure_hit_flash() -> void:
	_hit_flash_material = ShaderMaterial.new()
	_hit_flash_material.shader = HIT_FLASH_SHADER
	animated_sprite.material = _hit_flash_material


func _attach_source_controller() -> void:
	if definition.source_controller_scene == null:
		return
	var controller := definition.source_controller_scene.instantiate()
	if controller == null:
		push_error("Enemy source controller scene could not be instantiated: %s" % definition.enemy_id)
		return
	controller.name = "SourceController"
	add_child(controller)
	_source_controller = controller
	if controller.has_signal(&"screen_shake_requested"):
		controller.connect(&"screen_shake_requested", _on_source_controller_screen_shake_requested)
	if controller.has_method(&"setup"):
		controller.call(&"setup", self)


func _on_source_controller_screen_shake_requested(strength: float) -> void:
	source_screen_shake_requested.emit(strength)


func take_hit(damage: int, impulse: Vector2) -> void:
	take_hit_from(damage, impulse, &"physical", null)


func take_hit_from(
	damage: int, impulse: Vector2, damage_kind: StringName = &"physical", source: Object = null
) -> void:
	if _invulnerable or _state == State.DEATH:
		return
	if (
		_source_controller != null
		and _source_controller.has_method(&"can_receive_hit")
		and not bool(_source_controller.call(&"can_receive_hit"))
	):
		return
	_source_provoked = true
	_source_target_acquired = true
	if source is CharacterBody2D and (source as CharacterBody2D).is_in_group(&"players"):
		_player_ref = source as CharacterBody2D
	if _is_m10_back_hit(source):
		damage = 1
		if damage_kind == &"physical":
			_spawn_m10_back_hit_effect()
	if definition.animation_profile.source_monster_id == &"M09":
		_take_peng_hit(damage, impulse)
		return
	if health <= 0:
		return
	super.take_hit(damage, impulse)
	if health > 0:
		if not (
			_source_controller != null
			and _source_controller.has_method(&"keeps_idle_on_hit")
			and bool(_source_controller.call(&"keeps_idle_on_hit"))
		):
			_switch_state(State.HURT)
	else:
		_switch_state(State.DEATH)


func _is_m10_back_hit(source: Object) -> bool:
	return (
		definition.animation_profile.source_monster_id == &"M10"
		and source != null
		and is_instance_valid(source)
		and source.has_method(&"get_combat_facing")
		and int(source.call(&"get_combat_facing")) == _facing
	)


func _spawn_m10_back_hit_effect() -> void:
	if _m10_back_hit_frames == null:
		_m10_back_hit_frames = SpriteFrames.new()
		_m10_back_hit_frames.remove_animation(&"default")
		if SpriteSheetAtlas.append_animation(
			_m10_back_hit_frames,
			&"back_hit",
			M10_BACK_HIT_SHEET,
			M10_BACK_HIT_JSON,
			24.0,
			false
		) <= 0:
			_m10_back_hit_frames = null
			return
	var effect := AnimatedSprite2D.new()
	effect.name = "M10BackHit"
	effect.sprite_frames = _m10_back_hit_frames
	effect.scale = definition.visual_scale
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 6
	add_child(effect)
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.play(&"back_hit")


func _take_peng_hit(damage: int, impulse: Vector2) -> void:
	if _peng_egg_active:
		_peng_egg_hits_remaining -= 1
		hit_flash_seconds = 0.09
		if _peng_egg_hits_remaining <= 0:
			health = 0
			_peng_egg_active = false
			_peng_reburning = false
			if not defeated_once:
				defeated_once = true
				defeated.emit()
			_switch_state(State.DEATH)
		return
	if health <= 0:
		return
	var resolved_damage := maxi(1, damage)
	health = maxi(0, health - resolved_damage)
	velocity = impulse
	hit_flash_seconds = 0.09
	hit_received.emit(resolved_damage)
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()
	if health <= 0:
		_enter_peng_egg()
	else:
		_switch_state(State.HURT)


func force_attack(action: StringName) -> bool:
	return _start_attack(action)


func get_current_action() -> StringName:
	return _current_animation


func get_current_attack_spec() -> Dictionary:
	return _current_attack_spec.duplicate(true)


func get_state_name() -> StringName:
	return State.keys()[_state].to_lower()


func get_combat_phase() -> int:
	return _combat_phase


func get_source_attack_variant() -> int:
	return _source_attack_variant


func is_source_flying() -> bool:
	return _peng_flying if definition.animation_profile.source_monster_id == &"M09" else _uses_flight_physics()


func get_peng_egg_hits_remaining() -> int:
	return _peng_egg_hits_remaining


func get_combat_facing() -> int:
	return _facing


func get_source_controller() -> Node:
	return _source_controller


func get_source_invulnerability_ticks_remaining() -> int:
	return _source_invulnerability_ticks


func has_spawned_source_boss_dead_effect() -> bool:
	return _boss_dead_spawned


func has_spawned_source_loot() -> bool:
	return _source_loot_dropped


func source_set_move_direction(direction: int) -> void:
	if _state == State.DEATH or direction == 0:
		return
	_facing = -1 if direction < 0 else 1
	animated_sprite.flip_h = _facing > 0
	_switch_state(State.WALK)
	velocity.x = _runtime_move_speed() * _facing


func source_set_idle() -> void:
	if _state != State.DEATH:
		_switch_state(State.IDLE)


func source_refresh_attack_id() -> void:
	_attack_hits.clear()


func _complete_source_controlled_death() -> void:
	if _state != State.DEATH or not is_inside_tree():
		return
	_notify_source_before_despawn()
	if _summoned_source_child != null and is_instance_valid(_summoned_source_child):
		_summoned_source_child.queue_free()
	queue_free()


func _despawn_after_death() -> void:
	if not is_inside_tree():
		return
	_notify_source_before_despawn()
	if _summoned_source_child != null and is_instance_valid(_summoned_source_child):
		_summoned_source_child.queue_free()
	await get_tree().create_timer(definition.death_despawn_delay).timeout
	if is_instance_valid(self):
		queue_free()


func _notify_source_before_despawn() -> void:
	if _source_before_despawn_called:
		return
	_source_before_despawn_called = true
	# M27 calls dropAura() from its destroy override rather than its death
	# timeline. The operation is idempotent so event-driven deaths stay exact.
	if definition.animation_profile.source_monster_id == &"M27":
		_spawn_source_loot()
	if _source_controller != null and _source_controller.has_method(&"before_despawn"):
		_source_controller.call(&"before_despawn")
	_emit_source_stage_effects(definition.source_despawn_effects)


func _notify_source_death_started() -> void:
	if _source_death_started_called:
		return
	_source_death_started_called = true
	_emit_source_stage_effects(definition.source_death_start_effects)


func _emit_source_stage_effects(effects: Array[Dictionary]) -> void:
	for raw_effect: Dictionary in effects:
		if bool(raw_effect.get("boss_only", false)) and not is_boss():
			continue
		var effect := raw_effect.duplicate(true)
		effect["source_stage"] = source_stage
		effect["source_level"] = source_level
		effect["source_monster_id"] = definition.animation_profile.source_monster_id
		source_stage_effect_requested.emit(effect, self)


func _spawn_source_loot() -> void:
	if _source_loot_dropped or definition == null or definition.animation_profile == null:
		return
	_find_player()
	if _player_ref == null or not is_instance_valid(_player_ref) or get_parent() == null:
		return
	var player_level_value: Variant = _player_ref.get("level")
	var player_level := int(player_level_value) if player_level_value != null else 1
	var owns_dhqf := (
		_player_ref.has_method(&"has_source_equipment")
		and bool(_player_ref.call(&"has_source_equipment", &"dhqf"))
	)
	var loot_profile := ZMX1_LOOT_CATALOG.resolve(
		definition.animation_profile,
		source_stage,
		source_level,
		player_level,
		owns_dhqf
	)
	if loot_profile.is_empty() or not bool(loot_profile.get("drop_aura", true)):
		return
	_source_loot_dropped = true
	ZMX1_LOOT_RUNTIME.spawn_drop_set(
		get_parent(), global_position, _player_ref, loot_profile, _loot_rng,
		-_source_visual_height()
	)


func _source_visual_height() -> float:
	if definition == null or definition.animation_profile == null:
		return 60.0
	var spec := definition.animation_profile.get_spec(_current_animation)
	var sheet_path := str(spec.get("sprite_sheet", ""))
	var json_path := str(spec.get("sprite_sheet_json", ""))
	if sheet_path.is_empty() or json_path.is_empty():
		return 60.0
	var cache_key := "%s|%s" % [sheet_path, json_path]
	var bounds: Array = _source_visible_bounds_cache.get(cache_key, [])
	if bounds.is_empty():
		bounds = SpriteSheetAtlas.build_visible_bounds(sheet_path, json_path)
		_source_visible_bounds_cache[cache_key] = bounds
	if bounds.is_empty():
		return 60.0
	var frame := clampi(animated_sprite.frame, 0, bounds.size() - 1)
	return maxf(1.0, bounds[frame].size.y * absf(animated_sprite.scale.y))


func _spawn_boss_dead_effect() -> void:
	if _boss_dead_spawned:
		return
	if _boss_dead_frames == null:
		_boss_dead_frames = SpriteFrames.new()
		_boss_dead_frames.remove_animation(&"default")
		if SpriteSheetAtlas.append_animation(
			_boss_dead_frames, &"burst", BOSS_DEAD_SHEET, BOSS_DEAD_JSON, 24.0, false
		) <= 0:
			_boss_dead_frames = null
			return
	var effect := AnimatedSprite2D.new()
	effect.sprite_frames = _boss_dead_frames
	effect.scale = definition.visual_scale
	effect.flip_h = animated_sprite.flip_h
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.z_index = 5
	get_parent().add_child(effect)
	_boss_dead_spawned = true
	effect.global_position = global_position + animated_sprite.position
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.play(&"burst")
