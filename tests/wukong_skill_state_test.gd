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
	var animator: LayeredSpriteAnimator = player.get_node("LayeredSpriteAnimator")
	var wukong: RoleDefinition = main.playable_roles[0]
	var tangseng: RoleDefinition = main.playable_roles[1]
	var profile: RoleSkillProfile = wukong.skill_profile
	var extraction_manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/selected/zmxiyou3/wukong/effects/skills/manifest.json")
	)

	_assert(profile != null, "Wukong should provide a skill profile.")
	_assert(extraction_manifest.get("flash_actor_origin_y") == -50, "Skill manifest should preserve the Flash actor origin conversion.")
	_assert((extraction_manifest.get("source_calibration", {}) as Dictionary).size() == 9, "Every active Wukong skill should have source placement calibration.")
	_assert(profile.validate_for_role(1, wukong.animation_profile).is_empty(), "Wukong skill profile should validate.")
	_assert(profile.get_skill_count() == 9, "Wukong should expose all nine active skills plus Bloodthirst.")
	_assert(is_equal_approx(profile.passive_lifesteal_ratio, 0.05), "Wukong Bloodthirst should restore 5% dealt damage.")
	for action in [
		&"skill_qishier_zhan", &"skill_zhongzhan", &"skill_lieyan_shan",
		&"skill_huoyan_jinjing", &"skill_shenglong_zhan", &"skill_huomo_zhan",
		&"skill_huoyan_tuji", &"skill_lieyan_fengbao", &"skill_jindou_yun",
		&"skill_jindou_yun_vertical"
	]:
		_assert(wukong.animation_profile.actions.has(action), "Wukong should provide skill action '%s'." % action)

	_assert(player.configure_role(wukong), "Wukong should configure for skill verification.")
	_assert(player.role_skill_state is WukongSkillState, "Wukong should own an instance of WukongSkillState.")
	_assert(player.mana == player.max_mana, "Role configuration should provide full test mana.")
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(310, 515)
	enemy.health = enemy.max_health
	player.health = 50
	await physics_frame
	_assert(
		player.flash_actor_point(Vector2(120, -50)).is_equal_approx(Vector2(370, 420)),
		"Flash actor coordinates should include the source delta, -50px origin, and +5px visual nudge."
	)
	_assert(
		player.flash_target_point(enemy).is_equal_approx(Vector2(310, 465)),
		"Target-bound effects should convert the Godot foot point to the Flash actor origin."
	)

	# 七十二斩: 40 MP, source hit13 dash, five low-damage contact hits,
	# and the passive converts the accumulated 20 damage into 1 HP.
	_assert(player.combo_attack_state.request_attack(), "Combo progress setup should start.")
	player.action_state_machine.clear_state()
	_assert(player.combo_attack_state.get_current_step_number() == 1, "Combo setup should retain hit1 progress.")
	_assert(player.request_role_skill(0), "七十二斩 should start.")
	_assert(not player.request_normal_attack(), "Normal attack must not interrupt an active role skill.")
	_assert(player.mana == 160, "七十二斩 should cost 40 MP.")
	_assert(player.combo_attack_state.get_current_step_number() == 0, "Starting a skill should clear normal combo progress.")
	_assert(animator.get_current_action() == &"skill_qishier_zhan", "七十二斩 should play source hit13 body action.")
	_advance(player, 15)
	_assert(enemy.health == enemy.max_health - 20, "七十二斩 should apply five source 0.24x hits.")
	_assert(player.health == 51, "嗜血 should restore 5% of 七十二斩's accumulated damage.")
	_advance(player, 15)
	_assert(not player.action_state_machine.has_active_state(), "七十二斩 contact effect should finish after 30 ticks.")
	_assert(animator.visible, "七十二斩 should restore the layered actor after its impact effect.")

	# 重斩: 20 MP, frozen charge, and the third source frame starts on tick 15.
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(365, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(1), "重斩 should start.")
	_assert(player.mana == 140, "重斩 should cost 20 MP.")
	_assert(player.action_state_machine.blocks_gravity(), "重斩 should freeze vertical velocity like source hit14.")
	_advance(player, 14)
	_assert(enemy.health == enemy.max_health, "重斩 must wait for the source third frame.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 90, "重斩 should deal the source 5x base damage on tick 15.")
	_advance(player, 15)
	_assert(not player.action_state_machine.has_active_state(), "重斩 should finish with its 30-tick body animation.")

	# 烈焰闪: 20 MP, 40px/tick dash, one hit, and invulnerability.
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(330, 515)
	enemy.health = enemy.max_health
	await physics_frame
	var health_before_dash: int = player.health
	_assert(player.request_role_skill(2), "烈焰闪 should start.")
	_assert(player.mana == 120, "烈焰闪 should cost 20 MP.")
	_assert(player.action_state_machine.is_invulnerable(), "烈焰闪 should enable its source invulnerability window.")
	player.take_hit(12, Vector2(200, -100))
	_assert(player.health == health_before_dash, "烈焰闪 should ignore incoming damage during the dash.")
	_advance(player, 10)
	_assert(enemy.health == enemy.max_health - 100, "烈焰闪 should deal its fixed source 100 damage once.")
	_assert(not player.action_state_machine.has_active_state(), "烈焰闪 should finish after 10 ticks.")
	_assert(animator.visible, "烈焰闪 should restore the body after the fireball effect.")

	# 火眼金睛: ground-only, 40 MP, target in facing direction, immediate first
	# explosion followed by two source-timed repeats.
	player.global_position = Vector2(250, 515)
	player.facing = 1.0
	enemy.global_position = Vector2(500, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(3), "火眼金睛 should start on the floor.")
	_assert(player.mana == 70, "火眼金睛 should use the source Config.needMMP cost of 50 MP.")
	_advance(player, 17)
	_assert(enemy.health == enemy.max_health - 27, "火眼金睛 should immediately create its first 1.5x explosion.")
	_assert(not player.action_state_machine.has_active_state(), "火眼金睛 cast should release the actor after 17 ticks.")
	await create_timer(4.1).timeout
	_assert(enemy.health == enemy.max_health - 81, "火眼金睛 should repeat on the same target at two-second intervals.")

	# 升龙斩: source hit6, 10 MP, callback on the second frame's first tick.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	player.velocity = Vector2.ZERO
	player.facing = 1.0
	enemy.global_position = Vector2(280, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame
	_assert(
		not player.find_role_skill_targets(Vector2(142, 193), Vector2(30, -5)).is_empty(),
		"升龙斩 source hitbox should overlap the nearby target."
	)
	_assert(player.request_role_skill(4), "升龙斩 should start.")
	_assert(player.mana == 190, "升龙斩 should cost 10 MP.")
	_advance(player, 2)
	_assert(enemy.health == enemy.max_health, "升龙斩 should not hit before source tick 3.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 36, "升龙斩 should deal the source 2x damage (health=%d)." % enemy.health)
	_advance(player, 8)

	# 火魔斩: launch, proximity hover, falling strike, and landing explosion.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(300, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(5), "火魔斩 should start.")
	_assert(player.mana == 150, "火魔斩 should cost 50 MP.")
	_assert(player.action_state_machine.is_invulnerable(), "火魔斩 should preserve source father frames.")
	_advance(player, 6)
	_assert(not animator.visible, "火魔斩 should hide the body during the hover effect.")
	_advance(player, 46)
	_assert(enemy.health == enemy.max_health - 176, "火魔斩 hover should apply nine 1x hits plus its falling hit.")
	_advance(player, 2)
	_assert(enemy.health == enemy.max_health - 266, "火魔斩 landing should apply its source 5x hit.")
	_advance(player, 11)
	_assert(not player.action_state_machine.has_active_state(), "火魔斩 should recover after its landing effect.")
	_assert(animator.visible, "火魔斩 should restore the body after landing.")

	# 火眼突击: running attack replacement, source deceleration, four interval hits.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	player.velocity = Vector2.ZERO
	enemy.global_position = Vector2(350, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	player.facing = 1.0
	await physics_frame
	player.is_running = true
	_assert(player.request_normal_attack(), "A learned 火眼突击 should replace running hit1.")
	_assert(player.role_skill_state.get_current_skill_id() == &"huoyan_tuji", "Running attack should enter 火眼突击.")
	_assert(player.mana == 180, "火眼突击 should cost 20 MP.")
	_advance(player, 1)
	_assert(is_equal_approx(player.action_state_machine.get_horizontal_velocity(1.0), 600.0), "火眼突击 should start at source speed 25px/tick.")
	_advance(player, 14)
	_assert(enemy.health == enemy.max_health - 36, "火眼突击 should hit every four ticks during 15 frames.")

	# 烈焰风暴: 40 MP, ten frames, damage every three source ticks.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(300, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(7), "烈焰风暴 should start.")
	_assert(player.mana == 160, "烈焰风暴 should cost 40 MP.")
	_advance(player, 10)
	_assert(enemy.health == enemy.max_health - 84, "烈焰风暴 should floor 1.2x damage and apply four interval hits.")

	# 筋斗云: second press changes horizontal cloud to vertical without extra MP.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(320, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(8), "筋斗云 should start horizontally.")
	_assert(player.mana == 160, "筋斗云 should cost 40 MP once.")
	_advance(player, 1)
	_assert(is_equal_approx(player.action_state_machine.get_horizontal_velocity(1.0), 600.0), "筋斗云 first phase should move horizontally.")
	_assert(player.request_role_skill(8), "A second 筋斗云 press should change direction.")
	_assert(player.mana == 160, "筋斗云 direction change must not spend MP twice.")
	_assert(animator.get_current_action() == &"skill_jindou_yun_vertical", "筋斗云 should switch to source hit11_2.")
	_assert(player.action_state_machine.blocks_gravity(), "Vertical 筋斗云 should suspend gravity.")
	_assert(is_equal_approx(player.action_state_machine.get_vertical_velocity(), -600.0), "Vertical 筋斗云 should rise at 25px/tick.")
	_advance(player, 34)
	_assert(not player.action_state_machine.has_active_state(), "筋斗云 should preserve the shared 35-tick source lifetime.")

	var wukong_state: RoleSkillState = player.role_skill_state
	_assert(player.configure_role(tangseng), "Role switching should remove Wukong's skill state.")
	_assert(player.role_skill_state is TangsengSkillState, "Tangseng should receive its own role-specific skill state.")
	_assert(player.role_skill_state != wukong_state, "Tangseng must not share Wukong's skill instance.")
	_assert(player.role_skill_state.get_current_skill_id() != &"qishier_zhan", "Tangseng must not retain Wukong skill state.")

	if _failed:
		quit(1)
	else:
		print("PASS: all Wukong skills preserve source costs, timing, movement, damage, effects, and passive lifesteal.")
		quit(0)


func _advance(player: CharacterBody2D, ticks: int) -> void:
	for _tick in range(ticks):
		player.action_state_machine.physics_process(1.01 / 24.0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
