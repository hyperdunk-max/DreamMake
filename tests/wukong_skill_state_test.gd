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

	_assert(profile != null, "Wukong should provide a skill profile.")
	_assert(profile.validate_for_role(1, wukong.animation_profile).is_empty(), "Wukong skill profile should validate.")
	_assert(profile.get_skill_count() == 4, "Wukong should expose four active classic skills plus the passive.")
	_assert(is_equal_approx(profile.passive_lifesteal_ratio, 0.05), "Wukong Bloodthirst should restore 5% dealt damage.")
	for action in [&"skill_qishier_zhan", &"skill_zhongzhan", &"skill_lieyan_shan", &"skill_huoyan_jinjing"]:
		_assert(wukong.animation_profile.actions.has(action), "Wukong should provide skill action '%s'." % action)

	_assert(player.configure_role(wukong), "Wukong should configure for skill verification.")
	_assert(player.role_skill_state is WukongSkillState, "Wukong should own an instance of WukongSkillState.")
	_assert(player.mana == player.max_mana, "Role configuration should provide full test mana.")
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(310, 515)
	enemy.health = enemy.max_health
	player.health = 50
	await physics_frame

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

	# 重斩: 20 MP, frozen charge, source tick-16 strike, 5x base damage.
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(365, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(1), "重斩 should start.")
	_assert(player.mana == 140, "重斩 should cost 20 MP.")
	_assert(player.action_state_machine.blocks_gravity(), "重斩 should freeze vertical velocity like source hit14.")
	_advance(player, 16)
	_assert(enemy.health == enemy.max_health - 90, "重斩 should deal the source 5x base damage on tick 16.")
	_advance(player, 14)
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
	_assert(player.mana == 80, "火眼金睛 should cost 40 MP.")
	_advance(player, 17)
	_assert(enemy.health == enemy.max_health - 27, "火眼金睛 should immediately create its first 1.5x explosion.")
	_assert(not player.action_state_machine.has_active_state(), "火眼金睛 cast should release the actor after 17 ticks.")
	await create_timer(4.1).timeout
	_assert(enemy.health == enemy.max_health - 81, "火眼金睛 should repeat on the same target at two-second intervals.")

	_assert(player.configure_role(tangseng), "Role switching should remove Wukong's skill state.")
	_assert(player.role_skill_state == null, "A role without a configured skill profile must not share Wukong's skill instance.")
	_assert(not player.request_role_skill(0), "Tangseng must not invoke Wukong's skills.")

	if _failed:
		quit(1)
	else:
		print("PASS: Wukong classic skills preserve source costs, timing, movement, damage, effects, and passive lifesteal.")
		quit(0)


func _advance(player: CharacterBody2D, ticks: int) -> void:
	for _tick in range(ticks):
		player.action_state_machine.physics_process(1.01 / 24.0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
