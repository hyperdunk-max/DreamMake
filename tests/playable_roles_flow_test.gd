extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var load_error := change_scene_to_file("res://scenes/main.tscn")
	_assert(load_error == OK, "Main scene should load.")
	await process_frame
	await physics_frame

	var main := current_scene
	var player = main.get_node("Player")
	var enemy = main.get_node("TrainingEnemy")
	var animator: LayeredSpriteAnimator = player.get_node("LayeredSpriteAnimator")
	var definitions: Array = main.playable_roles
	var expected_step_counts := [5, 1, 3, 3]
	var expected_frame_sizes := [
		Vector2i(200, 200), Vector2i(200, 200),
		Vector2i(300, 200), Vector2i(200, 200),
	]
	var expected_visual_offsets := [
		Vector2(0, -72), Vector2(0, -56),
		Vector2(0, -56), Vector2(0, -68),
	]
	var expected_body_counts := [6, 7, 6, 7]
	var expected_weapon_counts := [9, 7, 9, 9]
	var required_shared_actions := [
		&"idle", &"run", &"jump_up", &"jump_double", &"jump_fall", &"hurt",
	]

	_assert(definitions.size() == 4, "Four playable roles should be registered.")
	for index in range(definitions.size()):
		var definition: RoleDefinition = definitions[index]
		var profile := definition.animation_profile
		_assert(definition.validate().is_empty(), "Role %d definition should validate." % definition.role_id)
		_assert(profile.frame_size == expected_frame_sizes[index], "Role %d should use its source cell size." % definition.role_id)
		_assert(profile.visual_offset == expected_visual_offsets[index], "Role %d should use its measured shared foot anchor." % definition.role_id)
		_assert(profile.get_body_showids().size() == expected_body_counts[index], "Role %d should expose every selected body atlas." % definition.role_id)
		_assert(profile.get_weapon_showids().size() == expected_weapon_counts[index], "Role %d should expose every selected weapon atlas." % definition.role_id)
		for action in required_shared_actions:
			_assert(profile.actions.has(action), "Role %d should provide shared action '%s'." % [definition.role_id, action])
		for combo_step in definition.combo_attack_profile.steps:
			_assert(profile.actions.has(combo_step["action"]), "Role %d should provide every combo animation." % definition.role_id)

		_assert(player.configure_role(definition), "Role %d should configure on Player." % definition.role_id)
		_assert(animator.get_registered_role_id() == definition.role_id, "Animator should register role %d." % definition.role_id)
		_assert(animator.position == profile.visual_offset, "Animator should apply role %d visual anchor." % definition.role_id)
		for body_showid in profile.get_body_showids():
			_assert(player.select_body(int(body_showid)), "Role %d body %d should be selectable." % [definition.role_id, body_showid])
			_assert(animator.get_node("Body").texture != null, "Selected body texture should load.")
		for weapon_showid in profile.get_weapon_showids():
			_assert(player.select_weapon(int(weapon_showid)), "Role %d weapon %d should be selectable." % [definition.role_id, weapon_showid])
			_assert(animator.get_node("Weapon").texture != null, "Selected weapon texture should load.")

		_assert(player.configure_role(definition), "Role %d should reset after equipment cycling." % definition.role_id)
		_assert(player.combo_attack_profile.get_step_count() == expected_step_counts[index], "Role %d combo count should match source behavior." % definition.role_id)
		_assert(player.combo_attack_state.request_attack(), "Role %d should enter its combo." % definition.role_id)
		_assert(player.combo_attack_state.get_current_step_number() == 1, "A switched role should begin at combo step one.")
		player.action_state_machine.clear_state()

	var bajie: RoleDefinition = definitions[2]
	_assert(StringName(bajie.combo_attack_profile.steps[0]["action"]) == &"hit2", "Bajie combo should begin with source action hit2.")
	_assert(StringName(bajie.combo_attack_profile.steps[1]["action"]) == &"hit1", "Bajie combo second action should be source action hit1.")

	var shaseng: RoleDefinition = definitions[3]
	_assert(player.configure_role(shaseng), "Shaseng should configure for weapon-mode verification.")
	_assert(player.select_weapon(4), "Shaseng bow showid 4 should be selectable.")
	_assert(shaseng.animation_profile.get_weapon_mode(4) == &"arrow", "Shaseng weapon 4 should select arrow mode.")
	_assert(animator.get_node("Body").texture.resource_path.contains("/body_candidates/arrow/"), "Bow equipment should switch Shaseng to the arrow body atlas.")
	_assert(player.combo_attack_profile == shaseng.combo_attack_profiles_by_mode[&"arrow"], "Bow equipment should switch Shaseng to the arrow combo profile.")
	_assert(player.select_weapon(0), "Shaseng shovel showid 0 should be selectable again.")
	_assert(animator.get_node("Body").texture.resource_path.contains("/body_candidates/shovel/"), "Shovel equipment should restore the shovel body atlas.")

	# Every configured normal-attack step must load and spawn its own source effect.
	enemy.global_position.x = 910.0
	var expected_effect_counts := [
		[4, 4, 5, 4, 4], [24], [4, 4, 4], [4, 4, 4],
	]
	for role_index in range(definitions.size()):
		var definition: RoleDefinition = definitions[role_index]
		_assert(player.configure_role(definition), "Role effect verification should configure.")
		for step_index in range(definition.combo_attack_profile.steps.size()):
			var step: Dictionary = definition.combo_attack_profile.steps[step_index]
			_assert(_configured_effect_count(step) == expected_effect_counts[role_index][step_index], "Role %d combo step %d should reference every effect frame." % [definition.role_id, step_index + 1])
			var effect_count_before := _count_effects()
			player.perform_combo_hit(step, {})
			_assert(_count_effects() == effect_count_before + 1, "Role %d combo step %d should spawn an effect." % [definition.role_id, step_index + 1])
			var effect := current_scene.get_child(current_scene.get_child_count() - 1) as OneShotSpriteEffect
			_assert(effect != null, "The spawned attack effect should use the shared player.")
			_assert(effect.offset == Vector2(step["effect_sprite_offset"]), "Effect should preserve its Flash registration anchor.")

	_assert(player.configure_role(shaseng), "Shaseng arrow effects should configure.")
	_assert(player.select_weapon(4), "Shaseng arrow effect verification should select a bow.")
	var arrow_counts := [10, 10, 15]
	for step_index in range(player.combo_attack_profile.steps.size()):
		var step: Dictionary = player.combo_attack_profile.steps[step_index]
		_assert(_configured_effect_count(step) == arrow_counts[step_index], "Shaseng arrow combo should reference every source frame.")
		var effect_count_before := _count_effects()
		player.perform_combo_hit(step, {})
		_assert(_count_effects() == effect_count_before + 1, "Shaseng arrow combo should spawn its source effect.")

	# Wukong's reduced early knockback and wide finishers must keep all five
	# source-timed hits connected against one nearby target.
	var wukong: RoleDefinition = definitions[0]
	_assert(player.configure_role(wukong), "Wukong should configure for full combo verification.")
	player.global_position = Vector2(390, 515)
	enemy.global_position = Vector2(465, 515)
	enemy.health = enemy.max_health
	enemy.velocity = Vector2.ZERO
	await physics_frame
	_assert(player.combo_attack_state.request_attack(), "Wukong full combo should start.")
	for step_index in range(player.combo_attack_profile.steps.size()):
		var step: Dictionary = player.combo_attack_profile.steps[step_index]
		if step_index + 1 < player.combo_attack_profile.steps.size():
			_assert(player.combo_attack_state.request_attack(), "Wukong next attack should buffer.")
		for _tick in range(int(step["duration_ticks"])):
			player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(enemy.health == enemy.max_health - 90, "All five Wukong normal attacks should connect without pushing the target out early.")
	_assert(not player.action_state_machine.has_active_state(), "Wukong full combo should return to locomotion.")

	# The training attack must enter hurt synchronously, not merely reduce health.
	_assert(player.configure_role(wukong), "Wukong should configure for hurt verification.")
	enemy.velocity = Vector2.ZERO
	player.global_position = enemy.global_position + Vector2(-80.0, 0.0)
	var health_before: int = player.health
	var hurt_observation := {"animation_seen": false, "hurt_timer_seen": false}
	player.health_changed.connect(
		func(_current: int, _maximum: int) -> void:
			hurt_observation["animation_seen"] = animator.get_current_action() == &"hurt"
			hurt_observation["hurt_timer_seen"] = player.hurt_time > 0.0
	)
	_assert(enemy.request_test_attack(), "Training enemy test attack should start.")
	for _frame in range(30):
		await physics_frame
	_assert(player.health < health_before, "Training enemy attack should damage a nearby player.")
	_assert(hurt_observation["animation_seen"], "Taking damage should enter the hurt animation.")
	_assert(hurt_observation["hurt_timer_seen"], "Taking damage should start the hurt pose timer.")

	if _failed:
		quit(1)
	else:
		print("PASS: anchors, equipment variants, weapon modes, effects, combos, and hurt flow.")
		quit(0)


func _configured_effect_count(step: Dictionary) -> int:
	var direct_frames: Array = step.get("effect_frames", [])
	if not direct_frames.is_empty():
		return direct_frames.size()
	return int(step.get("effect_frame_count", 0))


func _count_effects() -> int:
	var result := 0
	for child in current_scene.get_children():
		if child is OneShotSpriteEffect:
			result += 1
	return result


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
