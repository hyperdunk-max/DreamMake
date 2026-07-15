extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal weapon_changed(showid: int, weapon_name: String)
signal body_changed(showid: int, body_name: String)
signal role_changed(role_id: int, display_name: String)

const MOVE_SPEED := 245.0
const JUMP_SPEED := -500.0
const GRAVITY := 1450.0
const HURT_TIME := 8.0 / 24.0
const DOUBLE_JUMP_ANIMATION_TIME := 10.0 / 24.0

@export var max_health := 100
@export var role_definition: RoleDefinition
@export var role_id := 1
@export var animation_profile: RoleAnimationProfile
@export var combo_attack_profile: ComboAttackProfile
@export var body_showid := -1
@export var weapon_showid := -1
var health := max_health
var facing := 1.0
var hurt_time := 0.0
var jump_count := 0
var double_jump_animation_time := 0.0

@onready var layered_animator: LayeredSpriteAnimator = $LayeredSpriteAnimator
@onready var action_state_machine: CharacterStateMachine = $ActionStateMachine

var combo_attack_state: ComboAttackState
var _effect_texture_cache: Dictionary = {}


func _ready() -> void:
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
	return true


func _physics_process(delta: float) -> void:
	hurt_time = maxf(0.0, hurt_time - delta)
	double_jump_animation_time = maxf(0.0, double_jump_animation_time - delta)
	action_state_machine.physics_process(delta)
	if is_on_floor():
		jump_count = 0
		double_jump_animation_time = 0.0
	elif jump_count == 0:
		# Walking off a ledge consumes the first jump but still allows one air jump.
		jump_count = 1
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("switch_weapon") and not action_state_machine.has_active_state():
		select_weapon(animation_profile.get_next_weapon_showid(weapon_showid))

	if Input.is_action_just_pressed("switch_body") and not action_state_machine.has_active_state():
		select_body(animation_profile.get_next_body_showid(body_showid))

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = sign(direction)

	if Input.is_action_just_pressed("attack") and combo_attack_state != null:
		combo_attack_state.request_attack()

	if action_state_machine.blocks_horizontal_movement():
		velocity.x = combo_attack_state.get_attack_velocity(facing) if combo_attack_state != null else 0.0
	else:
		velocity.x = direction * MOVE_SPEED

	if Input.is_action_just_pressed("jump") and not action_state_machine.has_active_state():
		if is_on_floor():
			jump_count = 1
			velocity.y = JUMP_SPEED
			layered_animator.play_action(&"jump_up", true)
		elif jump_count < 2:
			jump_count = 2
			velocity.y = JUMP_SPEED
			double_jump_animation_time = DOUBLE_JUMP_ANIMATION_TIME
			layered_animator.play_action(&"jump_double", true)

	move_and_slide()
	global_position.x = clampf(global_position.x, 24.0, 916.0)
	_update_pose()
	queue_redraw()


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
		next_pose = &"run"
	layered_animator.play_action(next_pose)
	layered_animator.set_facing(facing)

func perform_combo_hit(step: Dictionary, hit_targets: Dictionary) -> void:
	_spawn_attack_effect(step)
	var space := get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(step.get("hitbox_size", Vector2(72, 48)))
	var hitbox_offset := Vector2(step.get("hitbox_offset", Vector2(48, -31)))
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
			knockback.x *= facing
			target.take_hit(int(step.get("damage", 18)), knockback)


func _spawn_attack_effect(step: Dictionary) -> void:
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
		return
	var effect := OneShotSpriteEffect.new()
	var effect_fps := float(step.get("effect_fps", combo_attack_profile.logical_fps))
	var source_facing := int(step.get("effect_source_facing", animation_profile.source_facing))
	var sprite_offset := Vector2(step.get("effect_sprite_offset", Vector2.ZERO))
	if not effect.configure(effect_frames, effect_fps, source_facing, facing, sprite_offset):
		effect.queue_free()
		return
	var offset := Vector2(step.get("effect_offset", Vector2.ZERO))
	offset.x *= facing
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position + offset


func take_hit(damage: int, impulse: Vector2) -> void:
	action_state_machine.clear_state()
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
