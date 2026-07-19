class_name ProjectileSpriteEffect
extends OneShotSpriteEffect

signal target_hit(target: Object, frame_index: int)

var _source_actor: CollisionObject2D
var _step: Dictionary = {}
var _frame_hitboxes: Array = []
var _target_last_hit_frame: Dictionary = {}
var _last_checked_frame := -1
var _total_hits := 0


func configure_projectile(
	frames: Array,
	fps: float,
	source_facing: int,
	gameplay_facing: float,
	sprite_offset: Vector2,
	source_actor: CollisionObject2D,
	step: Dictionary
) -> bool:
	if not configure(frames, fps, source_facing, gameplay_facing, sprite_offset):
		return false
	_source_actor = source_actor
	_step = step
	_frame_hitboxes = Array(step.get("projectile_frame_hitboxes", []))
	return not _frame_hitboxes.is_empty()


func _physics_process(_delta: float) -> void:
	if is_queued_for_deletion() or _frame_index == _last_checked_frame:
		return
	_last_checked_frame = _frame_index
	if _frame_index < 0 or _frame_index >= _frame_hitboxes.size():
		return
	var raw_hitboxes: Array = Array(_frame_hitboxes[_frame_index])
	for raw_hitbox in raw_hitboxes:
		if _check_hitbox(Rect2(raw_hitbox)):
			return


func _check_hitbox(image_rect: Rect2) -> bool:
	if texture == null or image_rect.size.x <= 0.0 or image_rect.size.y <= 0.0:
		return false
	var texture_size := texture.get_size()
	var local_rect := Rect2(image_rect.position - texture_size * 0.5 + offset, image_rect.size)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(
		local_rect.size.x * global_transform.x.length(),
		local_rect.size.y * global_transform.y.length()
	)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, to_global(local_rect.get_center()))
	query.collision_mask = int(_step.get("collision_mask", 4))
	if _source_actor != null and is_instance_valid(_source_actor):
		query.exclude = [_source_actor.get_rid()]
	for result in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.collider
		if not target.has_method("take_hit") or not _can_hit_target(target):
			continue
		_apply_hit(target)
		if bool(_step.get("projectile_destroy_on_hit", false)):
			queue_free()
			return true
		var max_hits := int(_step.get("projectile_max_hits", 0))
		if max_hits > 0 and _total_hits >= max_hits:
			queue_free()
			return true
	return false


func _can_hit_target(target: Object) -> bool:
	var interval := maxi(1, int(_step.get("projectile_rehit_interval_frames", 999999)))
	var last_frame := int(_target_last_hit_frame.get(target, -interval))
	return _frame_index - last_frame >= interval


func _apply_hit(target: Object) -> void:
	_target_last_hit_frame[target] = _frame_index
	_total_hits += 1
	var raw_damage: int = int(_step.get("damage", 18))
	# Calculate stat-based damage through the source actor if available.
	if _source_actor != null and is_instance_valid(_source_actor) and _source_actor.has_method("calculate_damage_output"):
		raw_damage = _source_actor.calculate_damage_output(raw_damage, target)
	# Apply skill-specific modifiers if available.
	if _source_actor != null and is_instance_valid(_source_actor):
		var skill_state = _source_actor.get("role_skill_state")
		if skill_state != null and skill_state.has_method("modify_outgoing_damage"):
			raw_damage = skill_state.modify_outgoing_damage(raw_damage)
	# Knockback is projectile-specific — do NOT route through apply_role_skill_hit
	# because its facing calculation would corrupt the projectile's direction.
	var knockback := Vector2(_step.get("knockback", Vector2(220, -120)))
	knockback.x *= 1.0 if scale.x == 1.0 else -1.0
	var source_facing := int(_step.get("effect_source_facing", -1))
	knockback.x *= source_facing
	var health_before := int(target.get("health"))
	target.take_hit(raw_damage, knockback)
	# Apply lifesteal through the source actor.
	if _source_actor != null and is_instance_valid(_source_actor) and _source_actor.has_method("_apply_lifesteal"):
		var actual_damage := maxi(0, health_before - int(target.get("health")))
		if actual_damage > 0:
			_source_actor._apply_lifesteal(actual_damage)
	target_hit.emit(target, _frame_index)
