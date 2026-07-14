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

	_assert(definitions.size() == 4, "Four playable roles should be registered.")
	for index in range(definitions.size()):
		var definition: RoleDefinition = definitions[index]
		_assert(definition.validate().is_empty(), "Role %d definition should validate." % definition.role_id)
		_assert(player.configure_role(definition), "Role %d should configure on Player." % definition.role_id)
		_assert(animator.get_registered_role_id() == definition.role_id, "Animator should register role %d." % definition.role_id)
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
	player.perform_combo_hit(wukong.combo_attack_profile.steps[0], {})
	await process_frame
	var effect_found := false
	for child in current_scene.get_children():
		if child is OneShotSpriteEffect:
			effect_found = true
			break
	_assert(effect_found, "Wukong hit1 should spawn a one-shot source effect.")

	player.global_position = enemy.global_position + Vector2(-80.0, 0.0)
	var health_before: int = player.health
	_assert(enemy.request_test_attack(), "Training enemy test attack should start.")
	for _frame in range(30):
		await physics_frame
	_assert(player.health < health_before, "Training enemy attack should damage a nearby player.")

	print("PASS: four-role switching, source combos, Wukong effect, and player hurt flow.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: %s" % message)
	quit(1)
