extends SceneTree


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
	var animator = player.get_node("LayeredSpriteAnimator")
	var definitions: Array = main.playable_roles
	var expected_step_counts := [5, 1, 3, 3]
	var expected_frame_sizes := [Vector2i(200, 200), Vector2i(200, 200), Vector2i(300, 200), Vector2i(200, 200)]
	var required_shared_actions := [&"idle", &"run", &"jump_up", &"jump_double", &"jump_fall", &"hurt"]

	_assert(definitions.size() == 4, "Four playable roles should be registered.")
	for index in range(definitions.size()):
		var definition: RoleDefinition = definitions[index]
		_assert(definition.validate().is_empty(), "Role %d definition should validate." % definition.role_id)
		_assert(definition.animation_profile.frame_size == expected_frame_sizes[index], "Role %d should use its source atlas cell size." % definition.role_id)
		for action in required_shared_actions:
			_assert(definition.animation_profile.actions.has(action), "Role %d should provide shared action '%s'." % [definition.role_id, action])
		for combo_step in definition.combo_attack_profile.steps:
			_assert(definition.animation_profile.actions.has(combo_step["action"]), "Role %d should provide every configured combo animation." % definition.role_id)
		_assert(player.configure_role(definition), "Role %d should configure on Player." % definition.role_id)
		_assert(animator.get_registered_role_id() == definition.role_id, "Animator should register role %d." % definition.role_id)
		_assert(animator.get_node("Body").texture != null, "Role %d should load its selected body atlas." % definition.role_id)
		_assert(animator.get_node("Weapon").texture != null, "Role %d should load its selected weapon atlas." % definition.role_id)
		_assert(player.combo_attack_profile.get_step_count() == expected_step_counts[index], "Role %d combo count should match source behavior." % definition.role_id)
		_assert(player.combo_attack_state.request_attack(), "Role %d should enter its combo." % definition.role_id)
		_assert(player.combo_attack_state.get_current_step_number() == 1, "A newly switched role should always begin at combo step one.")
		player.action_state_machine.clear_state()

	var bajie: RoleDefinition = definitions[2]
	_assert(StringName(bajie.combo_attack_profile.steps[0]["action"]) == &"hit2", "Bajie combo should begin with source action hit2.")
	_assert(StringName(bajie.combo_attack_profile.steps[1]["action"]) == &"hit1", "Bajie combo second action should be source action hit1.")

	var wukong: RoleDefinition = definitions[0]
	_assert(player.configure_role(wukong), "Wukong should reconfigure after role switching.")
	player.facing = 1.0
	var expected_effect_frame_counts := [4, 4, 5, 4, 4]
	var spawned_effect_count := 0
	for step_index in range(wukong.combo_attack_profile.steps.size()):
		var step: Dictionary = wukong.combo_attack_profile.steps[step_index]
		var effect_frames: Array = step.get("effect_frames", [])
		_assert(effect_frames.size() == expected_effect_frame_counts[step_index], "Wukong combo step %d should contain every source effect frame." % (step_index + 1))
		player.perform_combo_hit(step, {})
		spawned_effect_count += 1
	var live_effect_count := 0
	for child in current_scene.get_children():
		if child is OneShotSpriteEffect:
			live_effect_count += 1
	_assert(live_effect_count == spawned_effect_count, "Every Wukong combo step should spawn its configured one-shot effect.")
	var hit1_frames: Array = wukong.combo_attack_profile.steps[0]["effect_frames"]
	var hit2_frames: Array = wukong.combo_attack_profile.steps[1]["effect_frames"]
	_assert(hit1_frames[0].resource_path == hit2_frames[0].resource_path, "Wukong hit1 and hit2 should reuse source Role1Bullet1.")
	await process_frame

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
	_assert(hurt_observation["animation_seen"], "Taking damage should synchronously enter the role's hurt animation.")
	_assert(hurt_observation["hurt_timer_seen"], "Taking damage should start the hurt pose timer.")

	print("PASS: four-role switching, source combos, Wukong effect, and player hurt flow.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: %s" % message)
	quit(1)
