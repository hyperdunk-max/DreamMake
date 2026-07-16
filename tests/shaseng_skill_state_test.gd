extends SceneTree

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(change_scene_to_file("res://scenes/main.tscn") == OK, "Main scene should load.")
	await process_frame
	await physics_frame

	var main := current_scene
	var player = main.get_node("Player")
	var enemy = main.get_node("TrainingEnemy")
	var shaseng: RoleDefinition = main.playable_roles[3]
	var profile: RoleSkillProfile = shaseng.skill_profile
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/selected/zmxiyou3/shaseng/effects/skills/manifest.json")
	)

	_assert(profile != null, "Shaseng should provide a skill profile.")
	_assert(profile.validate_for_role(4, shaseng.animation_profile).is_empty(), "Shaseng skill profile should validate.")
	_assert(profile.get_skill_count() == 10, "Shaseng should expose both complete five-skill disciplines.")
	_assert((manifest.get("source_calibration", {}) as Dictionary).size() == 10, "Every Shaseng skill should have source calibration.")
	var effect_records: Array = manifest.get("effects", [])
	_assert(effect_records.size() == 23, "All twenty-two skill clips and the voodoo doll should be extracted.")
	for record in effect_records:
		_assert((record as Dictionary).has("source_registration"), "Every Shaseng effect should retain its SWF registration point.")
	for action_index in range(4, 13):
		var action := StringName("hit%d" % action_index)
		_assert(shaseng.animation_profile.actions.has(action), "Shovel mode should provide %s." % action)
		_assert((shaseng.animation_profile.actions_by_mode[&"arrow"] as Dictionary).has(action), "Arrow mode should provide %s." % action)

	# Keep delayed multi-hit tests focused; their source repeat schedules remain in the profile.
	profile.active_skills[0]["shovel_repeat_count"] = 1
	profile.active_skills[7]["shovel_repeat_count"] = 1
	profile.active_skills[9]["shovel_repeat_count"] = 1

	_assert(player.configure_role(shaseng), "Shaseng should configure.")
	_assert(player.role_skill_state is ShasengSkillState, "Shaseng should own an isolated ShasengSkillState.")
	player.facing = 1.0
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(360, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame

	# 瘴气: shovel hit4 fires on source tick 3, applies 0.3x damage and one poison stack.
	_assert(player.request_role_skill(0), "Miasma should start.")
	_assert(player.mana == 180, "Miasma should cost 20 MP.")
	_advance(player, 2)
	_assert(enemy.health == enemy.max_health, "Shovel Miasma should wait through source tick 2.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 6, "Shovel Miasma should deal source 0.3x base damage on tick 3.")
	_assert(player.role_skill_state.get_poison_stacks(enemy) == 1, "Miasma should add one poison counter.")
	player.role_skill_state.process_persistent(1.01)
	_assert(enemy.health == enemy.max_health - 16, "Miasma poison should tick for source 10 damage each second.")
	_advance(player, 18)

	# 猛毒素: level-one source formula is stacks² * attack * 0.25 and clears stacks.
	_assert(player.request_role_skill(4), "Toxicant should detonate stored poison.")
	_assert(player.mana == 120, "Toxicant should cost 60 MP.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 21, "One poison stack should detonate for 5 damage.")
	_assert(player.role_skill_state.get_poison_stacks(enemy) == 0, "Toxicant should clear detonated stacks.")

	# 麻痹药剂: source orb travels at 500/1.2 px/s, then stacks poison and stuns.
	_reset_role(player, shaseng, enemy, Vector2(350, 515))
	await physics_frame
	_assert(player.request_role_skill(1), "Paralysis Potion should start.")
	_advance(player, 1)
	await create_timer(0.35).timeout
	_assert(player.role_skill_state.get_poison_stacks(enemy) == 1, "Paralysis Potion should add a poison counter on arrival.")
	_assert(enemy.stun_time > 0.0, "Paralysis Potion should apply its source stun.")
	_advance(player, 9)

	# 巫毒娃娃: hitting the temporary like-monster transfers the same damage to its bound target.
	_reset_role(player, shaseng, enemy, Vector2(350, 515))
	await physics_frame
	_assert(player.request_role_skill(2), "Voodoo Doll should start.")
	_advance(player, 8)
	var doll: ShasengVoodooDoll = player.role_skill_state._doll
	_assert(doll != null and is_instance_valid(doll), "Voodoo Doll should bind the nearest forward target on source tick 8.")
	var health_before_doll: int = enemy.health
	if doll != null:
		player.apply_role_skill_hit(doll, 20, Vector2.ZERO)
	_assert(enemy.health == health_before_doll - 20, "Damage dealt to the doll should transfer to its bound target.")
	_advance(player, 13)

	# 剧毒阵: persistent array begins on tick 15; three poison bursts resolve on tick 27.
	_reset_role(player, shaseng, enemy, Vector2(304, 515))
	await physics_frame
	_assert(player.request_role_skill(3), "Poison Formation should start on the ground.")
	_advance(player, 26)
	_assert(enemy.health == enemy.max_health, "Poison Formation should not hit before source tick 27.")
	_advance(player, 1)
	_assert(enemy.health < enemy.max_health, "Poison Formation should release its three source bursts on tick 27.")
	_assert(player.role_skill_state.get_poison_stacks(enemy) > 0, "Poison Formation bursts should add poison counters.")
	_advance(player, 7)

	# 铲系第二心法 timings and source damage ratios.
	_reset_role(player, shaseng, enemy, Vector2(342, 515))
	await physics_frame
	_assert(player.request_role_skill(5), "Shovel Power Strike should start.")
	_advance(player, 4)
	_assert(enemy.health == enemy.max_health, "Shovel Power Strike should wait through tick 4.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 40, "Shovel Power Strike should deal source 2x damage on tick 5.")
	_advance(player, 16)

	_reset_role(player, shaseng, enemy, Vector2(250, 515))
	await physics_frame
	_assert(player.request_role_skill(6), "Shovel Rising Strike should start.")
	_advance(player, 7)
	_assert(enemy.health == enemy.max_health, "Shovel Rising Strike should wait through tick 7.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 80, "Shovel Rising Strike should deal source 4x damage on tick 8 (health %d)." % enemy.health)
	_assert(is_equal_approx(player.role_skill_state.get_vertical_velocity(), -240.0), "Shovel Rising Strike should map -10 px/tick to -240 px/s.")
	_advance(player, 12)

	_reset_role(player, shaseng, enemy, Vector2(354, 515))
	await physics_frame
	_assert(player.request_role_skill(7), "Shovel Multi Strike should start.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 24, "Shovel Multi Strike should begin its 1.2x hits on tick 1.")
	_assert(is_equal_approx(player.role_skill_state.get_horizontal_velocity(1.0), 480.0), "Shovel Multi Strike should map 20 px/tick to 480 px/s.")
	_advance(player, 33)

	# 绿叶标记: the second paid cast teleports without consuming the mark.
	_reset_role(player, shaseng, enemy, Vector2(800, 515))
	await physics_frame
	player.global_position = Vector2(250, 515)
	_assert(player.request_role_skill(8), "Leaf Mark should create a marker.")
	_advance(player, 4)
	_assert(not player.action_state_machine.has_active_state(), "Leaf Mark action should finish in four ticks (elapsed %d)." % player.role_skill_state.get_elapsed_ticks())
	player.global_position = Vector2(600, 515)
	_assert(player.request_role_skill(8), "Leaf Mark should reactivate from idle (active=%s marker=%s mana=%d)." % [player.action_state_machine.has_active_state(), is_instance_valid(player.role_skill_state._marker_effect), player.mana])
	_advance(player, 1)
	_assert(player.global_position.is_equal_approx(Vector2(250, 515)), "Leaf Mark should teleport to the exact stored actor position.")
	_assert(player.mana == 140, "Leaf Mark creation and teleport should each cost 30 MP.")

	# 木魔舞 shovel blade loops for ten seconds and begins damage on source tick 5.
	_reset_role(player, shaseng, enemy, Vector2(468, 515))
	await physics_frame
	_assert(player.request_role_skill(9), "Shovel Wood Demon Dance should start.")
	_advance(player, 4)
	_assert(enemy.health == enemy.max_health, "Shovel Wood Demon Dance should wait through tick 4.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 60, "Shovel Wood Demon Dance should deal source 3x damage on tick 5.")
	_advance(player, 13)

	# Bow mode shares one state instance but selects its own actions, timings and movement.
	_reset_role(player, shaseng, enemy, Vector2(331, 515))
	await physics_frame
	_assert(player.select_weapon(4), "Shaseng bow showid 4 should be selectable.")
	_assert(player.request_role_skill(5), "Bow Power Strike should start.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 40, "Bow Power Strike should hit on source tick 1.")
	_assert(is_equal_approx(player.role_skill_state.get_horizontal_velocity(1.0), -600.0), "Bow Power Strike should recoil at source 25 px/tick.")
	_assert(is_equal_approx(player.role_skill_state.get_vertical_velocity(), -600.0), "Bow Power Strike should rise at source 25 px/tick.")
	_advance(player, 17)

	_reset_role(player, shaseng, enemy, Vector2(330, 515))
	await physics_frame
	player.select_weapon(4)
	_assert(player.request_role_skill(7), "Bow Multi Strike should start.")
	_advance(player, 12)
	_assert(enemy.health == enemy.max_health, "Bow Multi Strike should wait through source tick 12.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 80, "Bow Multi Strike should deal source 4x damage on tick 13.")
	_advance(player, 23)

	_reset_role(player, shaseng, enemy, Vector2(340, 515))
	await physics_frame
	player.select_weapon(4)
	var facing_before: float = player.facing
	_assert(player.request_role_skill(9), "Bow Wood Demon Dance should start.")
	_advance(player, 24)
	_assert(player.facing == facing_before, "Bow Wood Demon Dance should keep direction through tick 24.")
	_advance(player, 1)
	_assert(player.facing == -facing_before, "Bow Wood Demon Dance should reverse on source tick 25.")
	_advance(player, 25)
	await create_timer(0.5).timeout
	player.role_skill_state.dispose()
	for child in current_scene.get_children():
		if child is OneShotSpriteEffect or child is ShasengVoodooDoll:
			child.queue_free()
	await process_frame
	await process_frame

	if _failed:
		quit(1)
	else:
		print("PASS: all Shaseng poison, doll, marker, shovel, bow, movement, and source timing branches preserve source behavior.")
		quit(0)


func _reset_role(player, shaseng: RoleDefinition, enemy, enemy_position: Vector2) -> void:
	_assert(player.configure_role(shaseng), "Shaseng should reset between skill branches.")
	player.facing = 1.0
	player.global_position = Vector2(250, 515)
	player.velocity = Vector2.ZERO
	enemy.global_position = enemy_position
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	enemy.stun_time = 0.0


func _advance(player: CharacterBody2D, ticks: int) -> void:
	for _tick in range(ticks):
		player.action_state_machine.physics_process(1.01 / 24.0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
