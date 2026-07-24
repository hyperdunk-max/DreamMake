extends SceneTree

const CASES := [
	["res://resources/enemies/zmxiyou1_m04_monkey_king.tres", &"attack3", &"timeline"],
	["res://resources/enemies/zmxiyou1_peng_demon_king.tres", &"attack1", &"timeline"],
	["res://resources/enemies/zmxiyou1_peng_demon_king.tres", &"attack3", &"timeline"],
	["res://resources/enemies/zmxiyou1_m10_jiao.tres", &"attack2", &"timeline"],
	["res://resources/enemies/zmxiyou1_m11_lion.tres", &"attack3", &"timeline"],
	["res://resources/enemies/zmxiyou1_m13.tres", &"attack2", &"timeline"],
	["res://resources/enemies/zmxiyou1_m14.tres", &"attack1", &"accelerating"],
	["res://resources/enemies/zmxiyou1_m18.tres", &"attack1", &"timeline"],
	["res://resources/enemies/zmxiyou1_m18.tres", &"attack2", &"timeline"],
	["res://resources/enemies/zmxiyou1_m19_shark.tres", &"attack2_1", &"timeline"],
	["res://resources/enemies/zmxiyou1_m19_shark.tres", &"attack2_2", &"timeline"],
	["res://resources/enemies/zmxiyou1_m19_shark.tres", &"attack3_1", &"timeline"],
	["res://resources/enemies/zmxiyou1_m19_shark.tres", &"attack3_2", &"timeline"],
	["res://resources/enemies/zmxiyou1_m26_dragon.tres", &"attack1", &"timeline"],
	["res://resources/enemies/zmxiyou1_m26_dragon.tres", &"attack4", &"timeline"],
]

const BULLET_SCENE := preload("res://scenes/effects/enemy_bullet.tscn")

var _failed := false


class ProjectileTarget:
	extends CharacterBody2D

	var hit_count := 0

	func take_hit(
		_damage: int,
		_impulse: Vector2,
		_damage_kind: StringName = &"physical",
		_source: Object = null
	) -> void:
		hit_count += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var accelerating_count := 0
	var bounds_cache: Dictionary = {}
	for test_case: Array in CASES:
		var definition := load(test_case[0]) as EnemyDefinition
		var action := StringName(test_case[1])
		_assert(definition != null, "Projectile definition should load: %s" % test_case[0])
		if definition == null:
			continue
		var spec := definition.animation_profile.get_spec(action)
		_assert(not spec.is_empty(), "%s should configure %s." % [definition.enemy_id, action])
		var sheet := str(spec.get("bullet_sprite_sheet", ""))
		var json := str(spec.get("bullet_sprite_json", ""))
		_assert(FileAccess.file_exists(sheet), "%s/%s projectile sheet should exist." % [definition.enemy_id, action])
		_assert(FileAccess.file_exists(json), "%s/%s projectile JSON should exist." % [definition.enemy_id, action])
		if not bounds_cache.has(json):
			var atlas := SpriteSheetAtlas.load_atlas(sheet, json)
			var frame_bounds := SpriteSheetAtlas.build_visible_bounds(sheet, json)
			bounds_cache[json] = frame_bounds
			_assert(not atlas.is_empty(), "%s/%s projectile atlas should load through SpriteSheetAtlas." % [definition.enemy_id, action])
			_assert(
				frame_bounds.size() == Dictionary(atlas.get("frames", {})).size(),
				"%s/%s should derive one Godot collision rectangle per packed projectile frame." % [definition.enemy_id, action]
			)
			_assert(
				frame_bounds.any(func(bounds: Rect2) -> bool: return bounds.has_area()),
				"%s/%s projectile atlas should contain visible collision geometry." % [definition.enemy_id, action]
			)
		var combat := EnemyCombatCatalog.resolve_attack(definition.animation_profile, action)
		_assert(int(combat.get("damage", 0)) > 0, "%s/%s should resolve source damage." % [definition.enemy_id, action])
		var expected_motion := StringName(test_case[2])
		var motion := StringName(spec.get("projectile_motion", &"timeline"))
		_assert(motion == expected_motion, "%s/%s should use %s motion." % [definition.enemy_id, action, expected_motion])
		if motion != &"timeline":
			accelerating_count += 1
	_assert(CASES.size() == 15, "Projectile audit should cover all 15 source-backed attack bindings.")
	_assert(accelerating_count == 1, "M14 should remain the only code-driven projectile.")
	_test_source_spawn_coordinates()
	await _test_m14_source_motion_and_lifetime()
	await _test_source_attack_interval()
	await _test_per_frame_collision_geometry()
	print("ZMX1 enemy projectile profile test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_source_spawn_coordinates() -> void:
	var m09 := load("res://resources/enemies/zmxiyou1_m09_peng.tres") as EnemyDefinition
	for action: StringName in [&"attack1", &"attack3"]:
		var fire := m09.animation_profile.get_spec(action)
		_assert(bool(fire.get("bullet_loop", false)), "M09 persistent flame should not disappear as a one-frame atlas.")
		_assert(is_equal_approx(float(fire.get("projectile_activation_delay", 0.0)), 0.6), "M09 flame should preserve its 0.6-second fade-in.")

	var m18 := load("res://resources/enemies/zmxiyou1_m18.tres") as EnemyDefinition
	var contact := m18.animation_profile.get_spec(&"attack1")
	_assert(bool(contact.get("projectile_contact_trigger", false)), "M18 hit1 should wait for Godot contact collision.")
	_assert(
		Vector2(contact.get("projectile_contact_target_offset", Vector2.ZERO)) == Vector2(-100, -100),
		"M18 hit1 should spawn at the source target offset."
	)
	var teleport := m18.animation_profile.get_spec(&"attack2")
	_assert(float(teleport.get("projectile_warning_ground_y", 0.0)) == 510.0, "M18 warning should use source ground y=510.")

	var m19 := load("res://resources/enemies/zmxiyou1_m19_shark.tres") as EnemyDefinition
	for action: StringName in [&"attack2_1", &"attack2_2"]:
		_assert(
			Vector2(m19.animation_profile.get_spec(action).get("projectile_spawn_offset", Vector2.ZERO)) == Vector2(600, -40),
			"M19 %s should retain the source ±600/-40 projectile offset." % action
		)
	for action: StringName in [&"attack3_1", &"attack3_2"]:
		var warning := m19.animation_profile.get_spec(action)
		_assert(bool(warning.get("projectile_warning_target_x", false)), "M19 warning should follow target x.")
		_assert(Vector2(warning.get("projectile_warning_offset", Vector2.ZERO)) == Vector2(-100, -100), "M19 warning should use source target -100/-100.")

	var m26 := load("res://resources/enemies/zmxiyou1_m26_dragon.tres") as EnemyDefinition
	var dragon_burst := m26.animation_profile.get_spec(&"attack4")
	_assert(bool(dragon_burst.get("projectile_target_x", false)), "M26 hit4 should use target x.")
	_assert(
		Vector2(dragon_burst.get("projectile_spawn_offset", Vector2.ZERO)) == Vector2(-65, -120),
		"M26 hit4 should spawn at target.x-65/boss.y-120."
	)


func _test_m14_source_motion_and_lifetime() -> void:
	var definition := load("res://resources/enemies/zmxiyou1_m14.tres") as EnemyDefinition
	var spec := _merged_projectile_spec(definition, &"attack1")
	_assert(
		is_equal_approx(float(spec.get("projectile_initial_speed", 0.0)), 96.0),
		"M14 EnemyMoveBullet should start at source speed 4 px/tick."
	)
	_assert(
		is_equal_approx(float(spec.get("projectile_max_distance", 0.0)), 1000.0),
		"M14 EnemyMoveBullet should preserve source setDistance(1000)."
	)
	var source := Node2D.new()
	root.add_child(source)
	var left := _create_projectile(definition, &"attack1", -1, source)
	var right := _create_projectile(definition, &"attack1", 1, source)
	_assert(left != null and right != null, "M14 runtime projectiles should configure in both directions.")
	if left != null and right != null:
		left.position = Vector2(500, 200)
		right.position = Vector2(500, 240)
		left.call(&"_advance_source_tick")
		right.call(&"_advance_source_tick")
		_assert(is_equal_approx(left.position.x, 496.0), "Left M14 bullet should move -4 px on its first source tick.")
		_assert(is_equal_approx(right.position.x, 504.0), "Right M14 bullet should move +4 px on its first source tick.")
		_assert(
			is_equal_approx(float(left.call(&"get_source_speed_px_per_tick")), -4.4),
			"Left M14 bullet should apply the source signed -0.4 acceleration after moving."
		)
		_assert(
			is_equal_approx(float(right.call(&"get_source_speed_px_per_tick")), 4.4),
			"Right M14 bullet should apply the source +0.4 acceleration after moving."
		)
		_assert(
			is_equal_approx(float(right.call(&"get_source_distance_remaining")), 995.6),
			"M14 distance budget should subtract the post-acceleration source speed."
		)
		for _tick: int in 8:
			left.call(&"_advance_source_tick")
			right.call(&"_advance_source_tick")
		_assert(
			is_equal_approx(float(right.call(&"get_source_speed_px_per_tick")), 7.2),
			"Right M14 source code should overshoot its speed threshold once, ending at 7.2 px/tick."
		)
		_assert(
			is_equal_approx(float(left.call(&"get_source_speed_px_per_tick")), -7.6),
			"Left M14 source code should preserve its signed speed<7 behavior instead of applying a symmetric cap."
		)
	source.queue_free()
	await process_frame
	_assert(
		left != null and is_instance_valid(left) and left.is_inside_tree(),
		"A fired source projectile should outlive its monster like BaseMonster.destroy()."
	)
	_assert(
		right != null and is_instance_valid(right) and right.is_inside_tree(),
		"Both projectile directions should remain stage-owned after source teardown."
	)
	if left != null and is_instance_valid(left):
		left.queue_free()
	if right != null and is_instance_valid(right):
		right.queue_free()
	await process_frame


func _test_per_frame_collision_geometry() -> void:
	var definition := load("res://resources/enemies/zmxiyou1_m11_lion.tres") as EnemyDefinition
	var spec := definition.animation_profile.get_spec(&"attack3")
	var sheet := str(spec.get("bullet_sprite_sheet", ""))
	var json := str(spec.get("bullet_sprite_json", ""))
	var bounds := SpriteSheetAtlas.build_visible_bounds(sheet, json)
	var first_index := -1
	var second_index := -1
	for index: int in bounds.size():
		if not bounds[index].has_area():
			continue
		if first_index < 0:
			first_index = index
		elif not bounds[index].is_equal_approx(bounds[first_index]):
			second_index = index
			break
	_assert(first_index >= 0 and second_index >= 0, "M11 projectile should expose changing visible-frame geometry.")
	var source := Node2D.new()
	root.add_child(source)
	var bullet := _create_projectile(definition, &"attack3", -1, source)
	if bullet != null and first_index >= 0 and second_index >= 0:
		var sprite := bullet.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var collision := bullet.get_node("CollisionShape2D") as CollisionShape2D
		sprite.pause()
		for frame_index: int in [first_index, second_index]:
			sprite.frame = frame_index
			bullet.call(&"_refresh_collision")
			var shape := collision.shape as RectangleShape2D
			_assert(
				shape != null and shape.size.is_equal_approx(bounds[frame_index].size),
				"Projectile collision size should follow each atlas frame's visible pixels."
			)
			_assert(
				collision.position.is_equal_approx(bounds[frame_index].get_center()),
				"Left-facing projectile collision center should follow the source atlas frame."
			)
		sprite.flip_h = true
		bullet.call(&"_refresh_collision")
		_assert(
			is_equal_approx(collision.position.x, -bounds[second_index].get_center().x),
			"Right-facing projectile collision should mirror around its AnimatedSprite2D registration."
		)
	source.queue_free()
	if bullet != null:
		bullet.queue_free()
	await process_frame


func _test_source_attack_interval() -> void:
	var definition := load("res://resources/enemies/zmxiyou1_peng_demon_king.tres") as EnemyDefinition
	var source := Node2D.new()
	root.add_child(source)
	var target := ProjectileTarget.new()
	target.add_to_group(&"players")
	target.collision_layer = 2
	target.collision_mask = 0
	var target_shape := CollisionShape2D.new()
	var target_rectangle := RectangleShape2D.new()
	target_rectangle.size = Vector2(160, 160)
	target_shape.shape = target_rectangle
	target.add_child(target_shape)
	root.add_child(target)
	var bullet := _create_projectile(definition, &"attack1", -1, source)
	_assert(bullet != null, "Persistent M09 flame should configure for interval testing.")
	if bullet != null:
		bullet.set_physics_process(false)
		bullet.set("_damage", 1)
		bullet.set("_max_hits", 3)
		bullet.set("_rehit_interval_frames", 4)
		bullet.set("_activation_delay_remaining", 0.0)
		var bullet_collision := bullet.get_node("CollisionShape2D") as CollisionShape2D
		bullet.position = Vector2.ZERO
		target.position = Vector2.ZERO
		await physics_frame
		bullet_collision.disabled = false
		target.position = bullet.position + bullet_collision.position
		for _frame: int in 3:
			await physics_frame
		_assert(
			not bullet_collision.disabled and bullet.monitoring and bullet.get_overlapping_bodies().has(target),
			"Interval test target should overlap the enabled projectile Godot Area2D (disabled=%s monitoring=%s overlaps=%s)." % [
				bullet_collision.disabled,
				bullet.monitoring,
				bullet.get_overlapping_bodies(),
			]
		)
		bullet.call(&"_advance_source_tick")
		_assert(target.hit_count == 1, "Persistent projectile should hit once with its initial source attack id.")
		for _tick: int in 3:
			bullet.call(&"_advance_source_tick")
		_assert(
			target.hit_count == 2 and int(bullet.call(&"get_attack_generation")) == 1,
			"BaseBullet attackInterval=4 should refresh its attack id on the fourth source tick."
		)
		for _tick: int in 3:
			bullet.call(&"_advance_source_tick")
		_assert(target.hit_count == 3, "Refreshed persistent projectile should honor source hitMaxCount.")
		_assert(bullet.is_queued_for_deletion(), "Projectile should destroy itself after source hitMaxCount contacts.")
	source.queue_free()
	target.queue_free()
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()
	await process_frame


func _create_projectile(
	definition: EnemyDefinition, action: StringName, facing: int, source: Node2D
) -> EnemyBullet:
	var spec := _merged_projectile_spec(definition, action)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var count := SpriteSheetAtlas.append_animation(
		frames,
		&"projectile",
		str(spec.get("bullet_sprite_sheet", "")),
		str(spec.get("bullet_sprite_json", "")),
		float(spec.get("bullet_fps", 24.0)),
		bool(spec.get("bullet_loop", false))
	)
	if count <= 0:
		return null
	var bounds := SpriteSheetAtlas.build_visible_bounds(
		str(spec.get("bullet_sprite_sheet", "")),
		str(spec.get("bullet_sprite_json", ""))
	)
	var bullet := BULLET_SCENE.instantiate() as EnemyBullet
	root.add_child(bullet)
	if not bullet.configure(frames, &"projectile", facing, source, spec, bounds):
		bullet.queue_free()
		return null
	return bullet


func _merged_projectile_spec(definition: EnemyDefinition, action: StringName) -> Dictionary:
	var result := definition.animation_profile.get_spec(action).duplicate(true)
	result.merge(EnemyCombatCatalog.resolve_attack(definition.animation_profile, action), true)
	return result


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
