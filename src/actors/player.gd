extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal weapon_changed(showid: int, weapon_name: String)
signal body_changed(showid: int, body_name: String)
signal role_changed(role_id: int, display_name: String)

const WALK_SPEED := 144.0
const RUN_SPEED := 240.0
const RUN_DOUBLE_TAP_SECONDS := 0.5
const JUMP_SPEED := -500.0
const GRAVITY := 1450.0
const HURT_TIME := 8.0 / 24.0
const DOUBLE_JUMP_ANIMATION_TIME := 10.0 / 24.0
const FLASH_ACTOR_ORIGIN_Y := -50.0
const PROJECTILE_EFFECT_SCRIPT := preload("res://src/effects/projectile_sprite_effect.gd")
const SKILL_INPUTS: Array[StringName] = [&"skill", &"skill_2", &"skill_3", &"skill_4"]

@export var max_health := 100
@export var max_mana := 200
@export var role_definition: RoleDefinition
@export var role_id := 1
@export var animation_profile: RoleAnimationProfile
@export var combo_attack_profile: ComboAttackProfile
@export var body_showid := -1
@export var weapon_showid := -1
var health := max_health
var mana := max_mana
var facing := 1.0
var hurt_time := 0.0
var jump_count := 0
var double_jump_animation_time := 0.0
var is_running := false
var _running_direction := 0
var _last_direction_press := 0
var _last_direction_press_time := -1.0

@onready var layered_animator: LayeredSpriteAnimator = $LayeredSpriteAnimator
@onready var action_state_machine: CharacterStateMachine = $ActionStateMachine

var combo_attack_state: ComboAttackState
var air_attack_state: AirAttackState
var role_skill_state: RoleSkillState
var _effect_texture_cache: Dictionary = {}
var _lifesteal_accumulator := 0.0


func _ready() -> void:
	add_to_group(&"players")
	if role_definition != null:
		_apply_role_definition(role_definition)
	_configure_runtime_role()
	queue_redraw()


func configure_role(definition: RoleDefinition) -> bool:
	if definition == null:
		return false
	var errors := definition.validate()
	if not errors.is_empty():
		for validation_error in errors:
			push_error(validation_error)
		return false
	action_state_machine.clear_state()
	role_definition = definition
	_apply_role_definition(definition)
	if not _configure_runtime_role():
		return false
	velocity = Vector2.ZERO
	hurt_time = 0.0
	double_jump_animation_time = 0.0
	jump_count = 0
	_reset_locomotion_input()
	mana = max_mana
	_lifesteal_accumulator = 0.0
	mana_changed.emit(mana, max_mana)
	role_changed.emit(role_id, definition.display_name)
	body_changed.emit(body_showid, layered_animator.get_body_name())
	weapon_changed.emit(weapon_showid, layered_animator.get_weapon_name())
	return true


func _apply_role_definition(definition: RoleDefinition) -> void:
	role_id = definition.role_id
	animation_profile = definition.animation_profile
	body_showid = definition.default_body_showid
	weapon_showid = definition.default_weapon_showid
	combo_attack_profile = definition.get_combo_profile_for_weapon(weapon_showid)


func _configure_runtime_role() -> bool:
	if not layered_animator.register_role(role_id, animation_profile, body_showid, weapon_showid):
		push_error("Player failed to register role id %d." % role_id)
		return false
	body_showid = layered_animator.get_body_showid()
	weapon_showid = layered_animator.get_weapon_showid()
	var combo_errors := combo_attack_profile.validate_for_role(role_id) if combo_attack_profile != null else PackedStringArray(["Missing combo attack profile."])
	if not combo_errors.is_empty():
		for combo_error in combo_errors:
			push_error(combo_error)
		return false
	if combo_attack_state == null:
		combo_attack_state = ComboAttackState.new()
		combo_attack_state.setup(ComboAttackState.ID, self, layered_animator, action_state_machine)
		action_state_machine.register_state(combo_attack_state)
	combo_attack_state.configure(combo_attack_profile)
	if air_attack_state == null:
		air_attack_state = AirAttackState.new()
		air_attack_state.setup(AirAttackState.ID, self, layered_animator, action_state_machine)
		action_state_machine.register_state(air_attack_state)
	air_attack_state.configure(role_definition.get_air_attack_step(), combo_attack_profile.logical_fps)
	if role_skill_state != null:
		role_skill_state.dispose()
		action_state_machine.unregister_state(RoleSkillState.ID)
		role_skill_state = null
	if role_definition.skill_profile != null and role_definition.skill_state_script != null:
		role_skill_state = role_definition.skill_state_script.new() as RoleSkillState
		if role_skill_state == null:
			push_error("Role %d skill state script must extend RoleSkillState." % role_id)
			return false
		role_skill_state.setup(RoleSkillState.ID, self, layered_animator, action_state_machine)
		role_skill_state.configure(role_definition.skill_profile)
		if not action_state_machine.register_state(role_skill_state):
			return false
	return true


func _physics_process(delta: float) -> void:
	hurt_time = maxf(0.0, hurt_time - delta)
	double_jump_animation_time = maxf(0.0, double_jump_animation_time - delta)
	if Input.is_action_just_released("attack") and combo_attack_state != null:
		combo_attack_state.release_attack()
		if role_skill_state != null:
			role_skill_state.release_normal_attack()
	action_state_machine.physics_process(delta)
	if is_on_floor():
		jump_count = 0
		double_jump_animation_time = 0.0
	elif jump_count == 0:
		# Walking off a ledge consumes the first jump but still allows one air jump.
		jump_count = 1
	if action_state_machine.blocks_gravity():
		velocity.y = action_state_machine.get_vertical_velocity()
	elif not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("switch_weapon") and not action_state_machine.has_active_state():
		select_weapon(animation_profile.get_next_weapon_showid(weapon_showid))

	if Input.is_action_just_pressed("switch_body") and not action_state_machine.has_active_state():
		select_body(animation_profile.get_next_body_showid(body_showid))

	for skill_slot in range(SKILL_INPUTS.size()):
		if Input.is_action_just_pressed(SKILL_INPUTS[skill_slot]):
			request_role_skill(skill_slot)

	_process_direction_input()
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0 and not action_state_machine.has_active_state():
		facing = sign(direction)

	if Input.is_action_just_pressed("attack"):
		request_normal_attack()

	if action_state_machine.blocks_horizontal_movement():
		velocity.x = action_state_machine.get_horizontal_velocity(facing)
	else:
		velocity.x = direction * get_horizontal_move_speed(direction)

	if Input.is_action_just_pressed("jump"):
		request_jump()

	move_and_slide()
	global_position.x = clampf(global_position.x, 24.0, 916.0)
	_update_pose()
	queue_redraw()


func request_normal_attack() -> bool:
	if combo_attack_state == null:
		return false
	if not is_on_floor() and air_attack_state != null and air_attack_state.is_configured():
		if action_state_machine.has_active_state():
			return false
		combo_attack_state.reset_progress()
		return air_attack_state.request_attack()
	if role_skill_state != null and role_skill_state.request_charged_normal_attack():
		combo_attack_state.reset_progress()
		return true
	if is_running and not action_state_machine.is_in_state(ComboAttackState.ID):
		# In the source, a learned 火眼突击 replaces Wukong's running hit1.
		if role_skill_state != null and role_skill_state.request_skill_by_id(&"huoyan_tuji"):
			combo_attack_state.reset_progress()
			return true
		combo_attack_state.reset_progress()
	return combo_attack_state.request_attack()


func request_role_skill(slot: int) -> bool:
	if role_skill_state == null:
		return false
	return role_skill_state.request_skill(slot)


func can_spend_mana(amount: int) -> bool:
	return amount >= 0 and mana >= amount


func spend_mana(amount: int) -> bool:
	if not can_spend_mana(amount):
		return false
	mana -= amount
	mana_changed.emit(mana, max_mana)
	return true


func restore_mana(amount: int) -> void:
	if amount <= 0:
		return
	var previous := mana
	mana = mini(max_mana, mana + amount)
	if mana != previous:
		mana_changed.emit(mana, max_mana)


func on_role_skill_started(_skill: Dictionary) -> void:
	combo_attack_state.reset_progress()
	_reset_locomotion_input()


func set_role_skill_visual_hidden(hidden: bool) -> void:
	layered_animator.visible = not hidden


func register_direction_press(direction: int, pressed_at_seconds := -1.0) -> bool:
	if direction == 0:
		return false
	var normalized_direction := -1 if direction < 0 else 1
	var now := pressed_at_seconds
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	var is_double_tap := (
		_last_direction_press == normalized_direction
		and _last_direction_press_time >= 0.0
		and now - _last_direction_press_time <= RUN_DOUBLE_TAP_SECONDS
	)
	_last_direction_press = normalized_direction
	_last_direction_press_time = now
	if not is_double_tap:
		is_running = false
		_running_direction = 0
		return false
	var entered_run := not is_running or _running_direction != normalized_direction
	is_running = true
	_running_direction = normalized_direction
	if entered_run and combo_attack_state != null:
		combo_attack_state.reset_progress()
	return true


func register_direction_release(direction: int) -> void:
	var normalized_direction := -1 if direction < 0 else 1
	if is_running and _running_direction == normalized_direction:
		is_running = false
		_running_direction = 0


func get_horizontal_move_speed(direction: float) -> float:
	if is_running and signf(direction) == float(_running_direction):
		return RUN_SPEED
	return WALK_SPEED


func _process_direction_input() -> void:
	# Locomotion cannot enter a new walk/run state while an action owns the actor.
	if not action_state_machine.has_active_state():
		if Input.is_action_just_pressed("move_left"):
			register_direction_press(-1)
		if Input.is_action_just_pressed("move_right"):
			register_direction_press(1)
	if Input.is_action_just_released("move_left"):
		register_direction_release(-1)
	if Input.is_action_just_released("move_right"):
		register_direction_release(1)
	if is_running:
		var run_action := "move_left" if _running_direction < 0 else "move_right"
		if not Input.is_action_pressed(run_action):
			is_running = false
			_running_direction = 0


func _reset_locomotion_input() -> void:
	is_running = false
	_running_direction = 0
	_last_direction_press = 0
	_last_direction_press_time = -1.0


func request_jump() -> bool:
	if is_on_floor():
		if action_state_machine.has_active_state():
			return false
		jump_count = 1
		velocity.y = JUMP_SPEED
		layered_animator.play_action(&"jump_up", true)
		return true
	if jump_count >= 2:
		return false
	if action_state_machine.has_active_state():
		if not action_state_machine.is_in_state(AirAttackState.ID):
			return false
		action_state_machine.clear_state(air_attack_state)
	jump_count = 2
	velocity.y = JUMP_SPEED
	double_jump_animation_time = DOUBLE_JUMP_ANIMATION_TIME
	layered_animator.play_action(&"jump_double", true)
	return true


func _update_pose() -> void:
	if action_state_machine.has_active_state():
		layered_animator.set_facing(facing)
		return
	var next_pose := &"idle"
	if hurt_time > 0.0:
		next_pose = &"hurt"
	elif not is_on_floor():
		if double_jump_animation_time > 0.0:
			next_pose = &"jump_double"
		elif velocity.y < 0.0:
			next_pose = &"jump_up"
		else:
			next_pose = &"jump_fall"
	elif absf(velocity.x) > 25.0:
		next_pose = &"run" if is_running and signf(velocity.x) == float(_running_direction) else &"walk"
	layered_animator.play_action(next_pose)
	layered_animator.set_facing(facing)

func perform_combo_hit(step: Dictionary, hit_targets: Dictionary) -> void:
	_spawn_attack_effect(step)
	if StringName(step.get("delivery", &"melee")) == &"projectile":
		return
	var space := get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(step.get("hitbox_size", Vector2(72, 48)))
	var hitbox_offset := Vector2(step.get("hitbox_offset", Vector2(48, -31)))
	hitbox_offset += animation_profile.visual_nudge
	hitbox_offset.x *= facing
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + hitbox_offset)
	query.collision_mask = 4
	query.exclude = [get_rid()]
	for result in space.intersect_shape(query, 8):
		var target: Object = result.collider
		if target.has_method("take_hit") and not hit_targets.has(target):
			hit_targets[target] = true
			var knockback := Vector2(step.get("knockback", Vector2(220, -120)))
			apply_role_skill_hit(target, int(step.get("damage", 18)), knockback)


func find_role_skill_targets(size: Vector2, offset: Vector2) -> Array:
	var mirrored_offset := offset
	mirrored_offset.x *= facing
	return find_role_skill_targets_at(size, global_position + mirrored_offset)


func find_role_skill_targets_at(size: Vector2, origin: Vector2) -> Array:
	var shape := RectangleShape2D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = 4
	query.exclude = [get_rid()]
	var targets: Array = []
	for result in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target: Object = result.collider
		if target.has_method("take_hit") and not targets.has(target):
			targets.append(target)
	return targets


func schedule_role_skill_box_hits(
	origin: Vector2, size: Vector2, damage: int, knockback: Vector2,
	repeat_count: int, interval_seconds: float
) -> void:
	_run_scheduled_role_skill_box_hits(
		origin, size, damage, knockback, repeat_count, interval_seconds
	)


func _run_scheduled_role_skill_box_hits(
	origin: Vector2, size: Vector2, damage: int, knockback: Vector2,
	repeat_count: int, interval_seconds: float
) -> void:
	for repeat_index in range(repeat_count):
		if repeat_index > 0:
			await get_tree().create_timer(interval_seconds).timeout
		for target in find_role_skill_targets_at(size, origin):
			apply_role_skill_hit(target, damage, knockback)


func move_role_skill_target(target: Node2D, destination: Vector2, duration_seconds: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target is CharacterBody2D:
		target.velocity = Vector2.ZERO
	var tween := get_tree().create_tween()
	tween.tween_property(target, "global_position", destination, duration_seconds)


func find_nearest_role_skill_target() -> Object:
	var candidates := find_role_skill_targets(Vector2(1880, 900), Vector2(0, -200))
	var nearest: Object
	var nearest_distance := INF
	for target in candidates:
		var delta_to_target: Vector2 = target.global_position - global_position
		if delta_to_target.x * facing < 0.0:
			continue
		var distance := delta_to_target.length_squared()
		if distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	return nearest


func apply_role_skill_hit(target: Object, damage: int, knockback: Vector2) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_hit"):
		return
	var resolved_damage := damage
	if role_skill_state != null:
		resolved_damage = role_skill_state.modify_outgoing_damage(damage)
	var health_before := int(target.get("health"))
	var directed_knockback := knockback
	directed_knockback.x *= facing
	target.take_hit(resolved_damage, directed_knockback)
	var actual_damage := maxi(0, health_before - int(target.get("health")))
	_apply_lifesteal(actual_damage)


func flash_actor_point(source_delta := Vector2.ZERO, mirror_x := true) -> Vector2:
	var mirrored_delta := source_delta
	if mirror_x:
		mirrored_delta.x *= facing
	mirrored_delta.y += FLASH_ACTOR_ORIGIN_Y
	if animation_profile != null:
		mirrored_delta += animation_profile.visual_nudge
	return global_position + mirrored_delta


func flash_target_point(target: Node2D, source_delta := Vector2.ZERO) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	return target.global_position + source_delta + Vector2(0, FLASH_ACTOR_ORIGIN_Y)


func spawn_role_skill_effect(spec: Dictionary, origin: Vector2, follow_actor := false) -> OneShotSpriteEffect:
	if spec.is_empty():
		return null
	var frames: Array = []
	var path_pattern := str(spec.get("effect_path_pattern", ""))
	for frame_index in range(int(spec.get("effect_frame_count", 0))):
		var path := path_pattern % frame_index
		if not _effect_texture_cache.has(path):
			_effect_texture_cache[path] = load(path) as Texture2D
		var texture := _effect_texture_cache[path] as Texture2D
		if texture != null:
			frames.append(texture)
	if frames.is_empty():
		return null
	var effect := OneShotSpriteEffect.new()
	if not effect.configure(
		frames,
		float(spec.get("effect_fps", 24.0)),
		int(spec.get("effect_source_facing", 1)),
		facing,
		Vector2(spec.get("effect_sprite_offset", Vector2.ZERO))
	):
		effect.queue_free()
		return null
	get_tree().current_scene.add_child(effect)
	effect.global_position = origin
	if follow_actor:
		effect.set_follow_target(self, origin - global_position)
	if bool(spec.get("loop", false)):
		effect.set_looping(true)
	if spec.has("linear_velocity"):
		var effect_velocity := Vector2(spec.get("linear_velocity", Vector2.ZERO))
		effect_velocity.x *= facing
		effect.set_linear_velocity(effect_velocity)
	if float(spec.get("lifetime_seconds", 0.0)) > 0.0:
		effect.set_lifetime(float(spec["lifetime_seconds"]))
	if spec.has("blend_mode"):
		effect.set_blend_mode(int(spec["blend_mode"]))
	return effect


func role_skill_effect_bounds_center(spec: Dictionary, registration_origin: Vector2) -> Vector2:
	var canvas := Vector2(spec.get("effect_source_canvas", Vector2.ZERO))
	var registration := Vector2(spec.get("effect_registration_point", canvas * 0.5))
	var local_center := canvas * 0.5 - registration
	var source_facing := int(spec.get("effect_source_facing", 1))
	var gameplay_facing := 1 if facing >= 0.0 else -1
	if gameplay_facing != source_facing:
		local_center.x *= -1.0
	return registration_origin + local_center


func heal(amount: int) -> int:
	if amount <= 0 or health <= 0:
		return 0
	var previous := health
	health = mini(max_health, health + amount)
	if health != previous:
		health_changed.emit(health, max_health)
	return health - previous


func heal_role_skill_allies(origin: Vector2, radius: float, amount: int) -> int:
	var total_healed := 0
	for candidate in get_tree().get_nodes_in_group(&"players"):
		if candidate is Node2D and candidate.has_method("heal"):
			if (candidate.global_position - origin).length() <= radius:
				total_healed += int(candidate.heal(amount))
	return total_healed


func schedule_role_skill_healing(
	origin: Vector2, radius: float, amount: int, repeat_count: int,
	interval_seconds: float, initial_delay_seconds := 0.0
) -> void:
	_run_scheduled_role_skill_healing(
		origin, radius, amount, repeat_count, interval_seconds, initial_delay_seconds
	)


func _run_scheduled_role_skill_healing(
	origin: Vector2, radius: float, amount: int, repeat_count: int,
	interval_seconds: float, initial_delay_seconds: float
) -> void:
	if initial_delay_seconds > 0.0:
		await get_tree().create_timer(initial_delay_seconds).timeout
	for repeat_index in range(repeat_count):
		if repeat_index > 0:
			await get_tree().create_timer(interval_seconds).timeout
		heal_role_skill_allies(origin, radius, amount)


func schedule_role_skill_hits(
	target: Object,
	effect_spec: Dictionary,
	damage: int,
	knockback: Vector2,
	repeat_count: int,
	interval_seconds: float
) -> void:
	_run_scheduled_role_skill_hits(
		target, effect_spec, damage, knockback, repeat_count, interval_seconds
	)


func _run_scheduled_role_skill_hits(
	target: Object,
	effect_spec: Dictionary,
	damage: int,
	knockback: Vector2,
	repeat_count: int,
	interval_seconds: float
) -> void:
	for repeat_index in range(repeat_count):
		if repeat_index > 0:
			await get_tree().create_timer(interval_seconds).timeout
		if target == null or not is_instance_valid(target):
			return
		spawn_role_skill_effect(effect_spec, flash_target_point(target as Node2D))
		apply_role_skill_hit(target, damage, knockback)


func _apply_lifesteal(actual_damage: int) -> void:
	if actual_damage <= 0 or role_definition == null or role_definition.skill_profile == null:
		return
	var ratio := role_definition.skill_profile.passive_lifesteal_ratio
	if ratio <= 0.0:
		return
	_lifesteal_accumulator += actual_damage * ratio
	var healing := int(floor(_lifesteal_accumulator))
	if healing <= 0:
		return
	_lifesteal_accumulator -= healing
	var previous := health
	health = mini(max_health, health + healing)
	if health != previous:
		health_changed.emit(health, max_health)


func _spawn_attack_effect(step: Dictionary) -> OneShotSpriteEffect:
	var effect_frames: Array = step.get("effect_frames", [])
	if effect_frames.is_empty():
		var effect_paths: Array = Array(step.get("effect_frame_paths", PackedStringArray()))
		var path_pattern := str(step.get("effect_path_pattern", ""))
		if not path_pattern.is_empty():
			for frame_index in range(int(step.get("effect_frame_count", 0))):
				effect_paths.append(path_pattern % frame_index)
		for raw_path in effect_paths:
			var path := str(raw_path)
			if not _effect_texture_cache.has(path):
				_effect_texture_cache[path] = load(path) as Texture2D
			var texture := _effect_texture_cache[path] as Texture2D
			if texture != null:
				effect_frames.append(texture)
	if effect_frames.is_empty():
		return null
	var is_projectile := StringName(step.get("delivery", &"melee")) == &"projectile"
	var effect: OneShotSpriteEffect = PROJECTILE_EFFECT_SCRIPT.new() if is_projectile else OneShotSpriteEffect.new()
	var effect_fps := float(step.get("effect_fps", combo_attack_profile.logical_fps))
	var effect_duration_ticks := int(step.get("effect_duration_ticks", 0))
	if effect_duration_ticks > 0:
		effect_fps = effect_frames.size() * combo_attack_profile.logical_fps / effect_duration_ticks
	var source_facing := int(step.get("effect_source_facing", animation_profile.source_facing))
	var sprite_offset := Vector2(step.get("effect_sprite_offset", Vector2.ZERO))
	var configured := false
	if is_projectile:
		configured = effect.configure_projectile(
			effect_frames, effect_fps, source_facing, facing, sprite_offset, self, step
		)
	else:
		configured = effect.configure(effect_frames, effect_fps, source_facing, facing, sprite_offset)
	if not configured:
		effect.queue_free()
		return null
	var offset := Vector2(step.get("effect_offset", Vector2.ZERO))
	offset += animation_profile.visual_nudge
	offset.x *= facing
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position + offset
	if bool(step.get("effect_follow_actor", false)):
		effect.set_follow_target(self, offset)
	return effect


func take_hit(damage: int, impulse: Vector2) -> void:
	if action_state_machine.is_invulnerable():
		return
	action_state_machine.clear_state()
	_reset_locomotion_input()
	health = maxi(0, health - damage)
	velocity = impulse
	hurt_time = HURT_TIME
	layered_animator.play_action(&"hurt", true)
	health_changed.emit(health, max_health)


func get_weapon_name() -> String:
	return layered_animator.get_weapon_name()


func get_body_name() -> String:
	return layered_animator.get_body_name()


func select_weapon(showid: int) -> bool:
	if not layered_animator.set_weapon(showid):
		return false
	weapon_showid = showid
	_refresh_combo_profile_for_weapon()
	weapon_changed.emit(weapon_showid, layered_animator.get_weapon_name())
	return true


func select_body(showid: int) -> bool:
	if not layered_animator.set_body(showid):
		return false
	body_showid = showid
	body_changed.emit(body_showid, layered_animator.get_body_name())
	return true


func _refresh_combo_profile_for_weapon() -> void:
	if role_definition == null:
		return
	var next_profile := role_definition.get_combo_profile_for_weapon(weapon_showid)
	if next_profile == null or next_profile == combo_attack_profile:
		return
	combo_attack_profile = next_profile
	combo_attack_state.configure(combo_attack_profile)


func _draw() -> void:
	var attacking := action_state_machine != null and action_state_machine.is_in_state(ComboAttackState.ID)
	draw_ellipse(Vector2(0, 1), 29.0, 7.0, Color(0.0, 0.0, 0.0, 0.35))
	if has_node("LayeredSpriteAnimator"):
		return
	# Readable fallback used before locally extracted art is available.
	draw_rect(Rect2(-16, -55, 32, 46), Color("d9772f"), true)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-22, -12), Vector2(22, -12), Vector2(17, 0), Vector2(-17, 0)]),
		Color("963f26")
	)
	draw_circle(Vector2(0, -69), 14, Color("f1bf83"))
	draw_rect(Rect2(-15, -84, 30, 7), Color("34251f"), true)
	draw_line(Vector2(-10, -51), Vector2(12, -28), Color("f4cc5a"), 5)
	var staff_end := Vector2(72 * facing, -43 if attacking else -20)
	draw_line(Vector2(3 * facing, -37), staff_end, Color("cf9a3c"), 6)
	draw_circle(staff_end, 5, Color("f2cf61"))
