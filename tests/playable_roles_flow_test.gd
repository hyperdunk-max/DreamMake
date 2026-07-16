extends SceneTree

var _failed := false
const PROJECTILE_EFFECT_SCRIPT := preload("res://src/effects/projectile_sprite_effect.gd")


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
	var expected_runtime_visual_offsets := [
		Vector2(0, -67), Vector2(0, -51),
		Vector2(0, -51), Vector2(0, -63),
	]
	var expected_body_counts := [6, 7, 6, 7]
	var expected_weapon_counts := [9, 7, 9, 9]
	var required_shared_actions := [
		&"idle", &"walk", &"run", &"jump_up", &"jump_double", &"jump_fall", &"hurt",
	]

	_assert(definitions.size() == 4, "Four playable roles should be registered.")
	for index in range(definitions.size()):
		var definition: RoleDefinition = definitions[index]
		var profile := definition.animation_profile
		_assert(definition.validate().is_empty(), "Role %d definition should validate." % definition.role_id)
		_assert(profile.frame_size == expected_frame_sizes[index], "Role %d should use its source cell size." % definition.role_id)
		_assert(profile.visual_offset == expected_visual_offsets[index], "Role %d should use its measured shared foot anchor." % definition.role_id)
		_assert(profile.visual_nudge == Vector2(0, 5), "Role %d should apply the requested 5px downward tuning nudge." % definition.role_id)
		_assert(profile.get_body_showids().size() == expected_body_counts[index], "Role %d should expose every selected body atlas." % definition.role_id)
		_assert(profile.get_weapon_showids().size() == expected_weapon_counts[index], "Role %d should expose every selected weapon atlas." % definition.role_id)
		for action in required_shared_actions:
			_assert(profile.actions.has(action), "Role %d should provide shared action '%s'." % [definition.role_id, action])
		for combo_step in definition.combo_attack_profile.steps:
			_assert(profile.actions.has(combo_step["action"]), "Role %d should provide every combo animation." % definition.role_id)

		_assert(player.configure_role(definition), "Role %d should configure on Player." % definition.role_id)
		_assert(animator.get_registered_role_id() == definition.role_id, "Animator should register role %d." % definition.role_id)
		_assert(animator.position == expected_runtime_visual_offsets[index], "Animator should apply role %d source anchor plus tuning nudge." % definition.role_id)
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

	# Source locomotion walks on the first press and runs when the same direction
	# is pressed again within 500ms. Entering run clears stored combo progress.
	_assert(player.configure_role(definitions[0]), "Wukong should configure for locomotion verification.")
	player.global_position = Vector2(390, 515)
	await physics_frame
	_assert(not player.register_direction_press(1, 10.0), "The first direction press should enter walk, not run.")
	_assert(is_equal_approx(player.get_horizontal_move_speed(1.0), player.WALK_SPEED), "Walk should use the source 144px/s speed.")
	player.velocity.x = player.WALK_SPEED
	player._update_pose()
	_assert(animator.get_current_action() == &"walk", "A first direction press should play walk.")
	_assert(player.register_direction_press(1, 10.49), "A same-direction second press within 500ms should enter run.")
	_assert(is_equal_approx(player.get_horizontal_move_speed(1.0), player.RUN_SPEED), "Run should use the source 240px/s speed.")
	player.velocity.x = player.RUN_SPEED
	player._update_pose()
	_assert(animator.get_current_action() == &"run", "A successful double tap should play run.")
	player.register_direction_release(1)
	_assert(not player.is_running, "Releasing the running direction should leave run.")
	player._reset_locomotion_input()
	_assert(not player.register_direction_press(1, 20.0), "A fresh first tap should walk.")
	_assert(not player.register_direction_press(1, 20.501), "A second press after 500ms should remain walk.")
	player._reset_locomotion_input()
	_assert(not player.register_direction_press(-1, 30.0), "A left first tap should walk.")
	_assert(not player.register_direction_press(1, 30.2), "Changing direction must not count as a double tap.")

	player.action_state_machine.clear_state()
	player.combo_attack_state.reset_progress()
	_assert(player.combo_attack_state.request_attack(), "Locomotion combo setup should start hit1.")
	_assert(player.combo_attack_state.request_attack(), "Locomotion combo setup should hold a retry for hit2.")
	var first_step: Dictionary = player.combo_attack_profile.steps[0]
	for _tick in range(int(first_step["duration_ticks"])):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(player.combo_attack_state.get_current_step_number() == 2, "Locomotion combo setup should reach hit2.")
	player.action_state_machine.clear_state()
	player._reset_locomotion_input()
	_assert(not player.register_direction_press(1, 40.0), "The first post-combo tap should walk.")
	_assert(player.combo_attack_state.get_current_step_number() == 2, "Walking should preserve combo progress.")
	_assert(player.register_direction_press(1, 40.49), "The second post-combo tap should run.")
	_assert(player.combo_attack_state.get_current_step_number() == 0, "Entering run should clear combo progress.")
	_assert(player.request_normal_attack(), "A running attack should start.")
	_assert(
		player.role_skill_state.get_current_skill_id() == &"huoyan_tuji",
		"A Wukong who learned 火眼突击 should replace running hit1 with the source skill."
	)
	_assert(player.combo_attack_state.get_current_step_number() == 0, "火眼突击 should keep normal combo progress reset.")
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
	var arrow_actions: Dictionary = shaseng.animation_profile.actions_by_mode[&"arrow"]
	_assert(arrow_actions[&"hit1"]["segments"][0]["row"] == 6, "Shaseng bow hit1 should use source row 6.")
	_assert(arrow_actions[&"hit2"]["segments"][0]["row"] == 6, "Shaseng bow hit2 should reuse source row 6.")
	_assert(arrow_actions[&"hit3"]["segments"][0]["row"] == 7, "Shaseng bow hit3 should use source row 7.")
	_assert(arrow_actions[&"hit3"]["segments"][0]["holds"] == PackedInt32Array([2, 2, 2, 2, 2, 10]), "Shaseng bow hit3 should preserve its 20 source ticks.")
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

	# Tangseng creates Role2Bullet1 on source tick 7.  Damage must follow the
	# visible projectile instead of applying across the whole trajectory at spawn.
	_clear_effects()
	await process_frame
	var tangseng: RoleDefinition = definitions[1]
	_assert(player.configure_role(tangseng), "Tangseng projectile timing should configure.")
	player.global_position = Vector2(170, 515)
	enemy.global_position = Vector2(430, 515)
	enemy.health = enemy.max_health
	enemy.velocity = Vector2.ZERO
	await physics_frame
	var tangseng_health_before: int = enemy.health
	_assert(player.combo_attack_state.request_attack(), "Tangseng source projectile attack should start.")
	for _tick in range(6):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(_count_projectiles() == 0, "Tangseng projectile must not appear before source tick 7.")
	_assert(enemy.health == tangseng_health_before, "Tangseng must not damage before its projectile exists.")
	player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(_count_projectiles() == 1, "Tangseng projectile should leave the staff on source tick 7.")
	_assert(enemy.health == tangseng_health_before, "Tangseng projectile spawn must not instantly damage its full path.")
	var tangseng_hit_frame := {"value": -1}
	var tangseng_projectile := _last_projectile()
	if tangseng_projectile != null:
		tangseng_projectile.target_hit.connect(func(_target: Object, frame_index: int) -> void: tangseng_hit_frame["value"] = frame_index)
	for _frame in range(40):
		await physics_frame
		if enemy.health < tangseng_health_before:
			break
	_assert(enemy.health < tangseng_health_before, "Tangseng visible projectile should damage when it reaches the enemy.")
	_assert(int(tangseng_hit_frame["value"]) > 0, "Tangseng damage should be reported from a travelled projectile frame.")
	_clear_effects()
	await process_frame
	player.facing = -1.0
	player.global_position = Vector2(770, 515)
	enemy.global_position = Vector2(510, 515)
	enemy.health = enemy.max_health
	enemy.velocity = Vector2.ZERO
	await physics_frame
	var left_health_before: int = enemy.health
	player.perform_combo_hit(player.combo_attack_profile.steps[0], {})
	await physics_frame
	_assert(enemy.health == left_health_before, "Left-facing Tangseng projectile must also travel before damage.")
	for _frame in range(40):
		await physics_frame
		if enemy.health < left_health_before:
			break
	_assert(enemy.health < left_health_before, "Tangseng projectile hitboxes should mirror and hit to the left.")
	_assert(enemy.velocity.x < 0.0, "Left-facing projectile knockback should point left.")
	player.facing = 1.0

	# Role4BulletArrow2 is a three-arrow fan.  Its three alpha components use
	# independent per-frame boxes and must travel to the target before damage.
	_clear_effects()
	await process_frame
	_assert(player.configure_role(shaseng), "Shaseng bow finisher timing should configure.")
	_assert(player.select_weapon(4), "Shaseng bow finisher timing should select a bow.")
	player.global_position = Vector2(170, 515)
	enemy.global_position = Vector2(520, 515)
	enemy.health = enemy.max_health
	enemy.velocity = Vector2.ZERO
	await physics_frame
	var arrow_health_before: int = enemy.health
	player.perform_combo_hit(player.combo_attack_profile.steps[2], {})
	_assert(_count_projectiles() == 1, "Shaseng bow finisher should create one Role4BulletArrow2 projectile.")
	await physics_frame
	_assert(enemy.health == arrow_health_before, "Shaseng bow finisher must not use the old full-path instant hitbox.")
	var arrow_hit_frame := {"value": -1}
	var arrow_projectile := _last_projectile()
	if arrow_projectile != null:
		arrow_projectile.target_hit.connect(func(_target: Object, frame_index: int) -> void: arrow_hit_frame["value"] = frame_index)
	for _frame in range(50):
		await physics_frame
		if enemy.health < arrow_health_before:
			break
	_assert(enemy.health < arrow_health_before, "Shaseng bow finisher should damage when one visible arrow reaches the enemy.")
	_assert(int(arrow_hit_frame["value"]) > 0, "Shaseng bow finisher damage should come from a travelled arrow frame.")

	# Source Role4 applies 8px horizontal speed on every active hit3 frame and
	# clears it when the 15th animation tick completes: 14 * 8px = 112px.
	_clear_effects()
	await process_frame
	_assert(player.configure_role(shaseng), "Shaseng shovel lunge should configure.")
	_assert(player.select_weapon(0), "Shaseng shovel lunge should select a melee weapon.")
	player.facing = 1.0
	player.global_position = Vector2(390, 515)
	enemy.global_position = Vector2(900, 515)
	await physics_frame
	var lunge_step: Dictionary = player.combo_attack_profile.steps[2]
	player.perform_combo_hit(lunge_step, {})
	var lunge_effect := current_scene.get_child(current_scene.get_child_count() - 1) as OneShotSpriteEffect
	_assert(lunge_effect != null, "Shaseng hit3 should spawn its follow effect.")
	if lunge_effect != null:
		_assert(lunge_effect.is_following(player), "Shaseng hit3 effect should follow the moving actor.")
		_assert(is_equal_approx(lunge_effect.get_duration_seconds(), 15.0 / 24.0), "Shaseng hit3 effect should span all 15 movement ticks.")
		var effect_start_x: float = lunge_effect.global_position.x
		player.global_position.x += 24.0
		await process_frame
		await process_frame
		_assert(is_equal_approx(lunge_effect.global_position.x - effect_start_x, 24.0), "Shaseng hit3 effect should preserve its actor-relative offset while moving.")
	_clear_effects()
	await process_frame
	player.global_position = Vector2(390, 515)
	_assert(player.combo_attack_state.request_attack(), "Shaseng shovel combo should start.")
	_assert(player.combo_attack_state.request_attack(), "Shaseng shovel hit2 should be held through hit1.")
	for _tick in range(13):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(player.combo_attack_state.request_attack(), "Shaseng shovel hit3 should be held through hit2.")
	for _tick in range(13):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(player.combo_attack_state.get_current_step_number() == 3, "Shaseng shovel combo should enter hit3.")
	var lunge_start_x: float = player.global_position.x
	for _frame in range(60):
		await physics_frame
		if not player.action_state_machine.has_active_state():
			break
	var lunge_distance: float = player.global_position.x - lunge_start_x
	_assert(lunge_distance >= 108.0 and lunge_distance <= 116.0, "Shaseng hit3 should reproduce the source 112px lunge, got %.2fpx." % lunge_distance)

	# Role1 uses hit3 as a dedicated 15-tick aerial normal attack, sets hitNum
	# to zero, and therefore restarts the next grounded combo from hit1.
	var wukong: RoleDefinition = definitions[0]
	var air_step := wukong.get_air_attack_step()
	_assert(StringName(air_step.get("action", &"")) == &"hit3", "Wukong air normal attack should use source hit3 animation.")
	_assert(int(air_step.get("duration_ticks", 0)) == 15, "Wukong air normal attack should preserve the source 15-tick lock.")
	_assert(player.configure_role(wukong), "Wukong air attack should configure.")
	_assert(player.combo_attack_state.request_attack(), "Wukong combo progress setup should start hit1.")
	_assert(player.combo_attack_state.request_attack(), "Wukong combo progress setup should hold a retry for hit2.")
	for _tick in range(9):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	for _tick in range(9):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(player.combo_attack_state.get_current_step_number() == 2, "Wukong setup should retain ground combo step two.")
	player.global_position = Vector2(390, 400)
	player.velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	_assert(not player.is_on_floor(), "Wukong air attack verification should be airborne.")
	_assert(player.jump_count == 1, "Walking into the air should preserve one available double jump.")
	player.velocity.y = -250.0
	_assert(player.request_normal_attack(), "Wukong airborne normal attack should start independently.")
	_assert(player.action_state_machine.is_in_state(AirAttackState.ID), "Wukong airborne normal attack should use AirAttackState.")
	_assert(animator.get_current_action() == &"hit3", "Wukong airborne normal attack should play hit3.")
	_assert(player.combo_attack_state.get_current_step_number() == 0, "Wukong air attack should reset stored ground combo progress.")
	for _tick in range(14):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(player.action_state_machine.is_in_state(AirAttackState.ID), "Wukong air attack should remain active through tick 14.")
	player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	_assert(not player.action_state_machine.has_active_state(), "Wukong air attack should finish on source tick 15.")
	player._update_pose()
	_assert(animator.get_current_action() == &"jump_up", "An air attack ending with upward velocity should return to jump_up.")
	player.velocity.y = 120.0
	_assert(player.request_normal_attack(), "Wukong should be able to air attack while falling.")
	for _tick in range(15):
		player.action_state_machine.physics_process(1.01 / player.combo_attack_profile.logical_fps)
	player._update_pose()
	_assert(animator.get_current_action() == &"jump_fall", "An air attack ending with downward velocity should return to jump_fall.")
	player.velocity.y = -120.0
	_assert(player.request_normal_attack(), "Wukong should start an air attack before double-jump interruption.")
	_assert(player.request_jump(), "Wukong should retain and activate the second jump during an air attack.")
	_assert(not player.action_state_machine.has_active_state(), "Double jump should exit AirAttackState immediately.")
	_assert(player.jump_count == 2, "Air attack must not consume the second jump before it is pressed.")
	_assert(is_equal_approx(player.velocity.y, player.JUMP_SPEED), "Double jump should restore the configured upward speed.")
	_assert(animator.get_current_action() == &"jump_double", "Air attack to double jump should play jump_double.")
	_assert(not player.request_jump(), "A completed double jump must still prevent a third jump.")
	player.global_position = Vector2(390, 515)
	player.velocity = Vector2.ZERO
	await physics_frame
	_assert(player.request_normal_attack(), "Wukong should attack after landing.")
	_assert(player.combo_attack_state.get_current_step_number() == 1, "The first grounded attack after an air attack must restart at hit1.")
	player.action_state_machine.clear_state()

	# Wukong's reduced early knockback and wide finishers must keep all five
	# source-timed hits connected against one nearby target.
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
			_assert(player.combo_attack_state.request_attack(), "Wukong next attack should remain held through the current step.")
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


func _count_projectiles() -> int:
	var result := 0
	for child in current_scene.get_children():
		if child.get_script() == PROJECTILE_EFFECT_SCRIPT and not child.is_queued_for_deletion():
			result += 1
	return result


func _last_projectile() -> Node:
	for index in range(current_scene.get_child_count() - 1, -1, -1):
		var child := current_scene.get_child(index)
		if child.get_script() == PROJECTILE_EFFECT_SCRIPT and not child.is_queued_for_deletion():
			return child
	return null


func _clear_effects() -> void:
	for child in current_scene.get_children():
		if child is OneShotSpriteEffect:
			child.queue_free()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
