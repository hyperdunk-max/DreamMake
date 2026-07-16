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
	var bajie: RoleDefinition = main.playable_roles[2]
	var profile: RoleSkillProfile = bajie.skill_profile
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/selected/zmxiyou3/bajie/effects/skills/manifest.json")
	)

	_assert(profile != null, "Bajie should provide a skill profile.")
	_assert(profile.validate_for_role(3, bajie.animation_profile).is_empty(), "Bajie skill profile should validate.")
	_assert(profile.get_skill_count() == 9, "Bajie should expose nine active skills plus Blade Armor.")
	_assert(profile.passive_physical_defense == 30, "Blade Armor should preserve the source +30 physical defense.")
	_assert(is_equal_approx(profile.passive_damage_heal_chance, 0.1), "Blade Armor should preserve its source 10% heal chance.")
	_assert(profile.passive_damage_heal_amount == 20, "Blade Armor should heal the current level-one attack value.")
	_assert((manifest.get("source_calibration", {}) as Dictionary).size() == 10, "Every Bajie active or passive skill should have source calibration.")
	_assert((manifest.get("effects", []) as Array).size() == 13, "All thirteen Bajie effect clips should be extracted.")
	_assert(int(profile.active_skills[3].get("repeat_count", 0)) == 4, "Sanctuary Wall should retain four source hit opportunities.")
	_assert(int(profile.active_skills[4].get("repeat_count", 0)) == 4, "Crushing Stone should retain four source hit opportunities.")
	_assert(int(profile.active_skills[5].get("repeat_count", 0)) == 3, "Giant Stone should retain three source hit opportunities.")
	_assert(int(profile.active_skills[6].get("repeat_count", 0)) == 4, "Ground Rolling Ball should retain four source hit opportunities.")
	_assert(int(profile.active_skills[7].get("repeat_count", 0)) == 4, "Spinning Ball should retain four source hit opportunities.")
	_assert(int(profile.active_skills[8].get("stab_count", 0)) == 10, "Earth Demon Thorns should retain ten source stab bullets.")
	# Keep this focused test short after proving the source schedules above.
	for slot in [3, 4, 5, 6, 7]:
		profile.active_skills[slot]["repeat_count"] = 1
	profile.active_skills[8]["stab_count"] = 1
	profile.active_skills[8]["stab_delay_seconds"] = 0.01
	for action in [
		&"skill_dunji", &"skill_shengdun", &"skill_zhanzheng_nuhou",
		&"skill_shengyu_zhiqiang", &"skill_suishi_po", &"skill_jushi_po",
		&"skill_digun_qiu", &"skill_xuangun_qiu", &"skill_tumo_ci",
		&"skill_tumo_ci_finish"
	]:
		_assert(bajie.animation_profile.actions.has(action), "Bajie should provide action '%s'." % action)

	_assert(player.configure_role(bajie), "Bajie should configure.")
	_assert(player.role_skill_state is BajieSkillState, "Bajie should own an isolated BajieSkillState.")
	player.facing = 1.0
	player.global_position = Vector2(250, 515)
	player.velocity = Vector2.ZERO
	enemy.global_position = Vector2(350, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame

	# 盾击: source hit4 starts its bullet on tick 1 for 2x base damage.
	_assert(player.request_role_skill(0), "Shield Bash should start.")
	_assert(player.mana == 190, "Shield Bash should cost 10 MP.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 40, "Shield Bash should deal source 2x base damage on tick 1.")
	_advance(player, 33)

	# 圣盾: a short cast installs ten seconds of full damage and knockback immunity.
	player.restore_mana(player.max_mana)
	player.health = 100
	profile.passive_damage_heal_chance = 0.0
	_assert(player.request_role_skill(1), "Holy Shield should start.")
	_assert(player.mana == 180, "Holy Shield should cost 20 MP.")
	_advance(player, 1)
	player.take_hit(40, Vector2(200, -100), &"physical", enemy)
	_assert(player.health == 100 and player.velocity == Vector2.ZERO, "Holy Shield should block damage and knockback.")
	_advance(player, 3)
	player.take_hit(40, Vector2(200, -100), &"physical", enemy)
	_assert(player.health == 100, "Holy Shield should remain active after its body action finishes.")
	player.role_skill_state.process_persistent(10.1)
	player.take_hit(40, Vector2.ZERO, &"physical", enemy)
	_assert(player.health == 90, "Blade Armor should subtract 30 from physical damage after Holy Shield expires.")

	# 刃甲: damage resolves first, then its source 10% proc heals one attack value.
	profile.passive_damage_heal_chance = 1.0
	player.health = 50
	player.take_hit(40, Vector2.ZERO, &"physical", enemy)
	_assert(player.health == 60, "A forced Blade Armor proc should heal 20 after taking 10 physical damage.")
	profile.passive_damage_heal_chance = 0.1

	# 战争怒吼: global pull plus a one-use 1.3x outgoing damage modifier.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(700, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(2), "War Cry should start.")
	_assert(player.mana == 180, "War Cry should cost 20 MP.")
	_advance(player, 1)
	await create_timer(1.05).timeout
	_assert(enemy.global_position.x < 300.0, "War Cry should pull even distant source-valid enemies to Bajie.")
	_advance(player, 5)
	enemy.health = enemy.max_health
	player.apply_role_skill_hit(enemy, 10, Vector2.ZERO)
	_assert(enemy.health == enemy.max_health - 13, "War Cry should amplify exactly the following attack to 1.3x.")

	# 圣域之墙: charge on tick 5, damaging wall on tick 17.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(500, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(3), "Sanctuary Wall should start.")
	_assert(player.mana == 150, "Sanctuary Wall should cost 50 MP.")
	_advance(player, 16)
	_assert(enemy.health == enemy.max_health, "Sanctuary Wall should not damage before source tick 17.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 40, "Sanctuary Wall should deal source 2x damage on tick 17.")
	_advance(player, 7)

	# 碎石破 and 巨石破 are grounded tick-7 earth attacks.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(410, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(4), "Crushing Stone should start.")
	_assert(player.mana == 185, "Crushing Stone should cost 15 MP.")
	_advance(player, 6)
	_assert(enemy.health == enemy.max_health, "Crushing Stone should wait through tick 6.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 20, "Crushing Stone should deal base damage on tick 7.")
	_advance(player, 19)

	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(400, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(5), "Giant Stone should start.")
	_assert(player.mana == 175, "Giant Stone should cost 25 MP.")
	_advance(player, 7)
	_assert(enemy.health == enemy.max_health - 30, "Giant Stone should deal source 1.5x damage on tick 7.")
	_advance(player, 19)

	# 地滚球 moves only once the third source cell begins on tick 8.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(290, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(6), "Ground Rolling Ball should start.")
	_assert(player.mana == 165, "Ground Rolling Ball should cost 35 MP.")
	_advance(player, 7)
	_assert(is_zero_approx(player.role_skill_state.get_horizontal_velocity(1.0)), "Ground Rolling Ball should not move before tick 8.")
	_advance(player, 1)
	_assert(is_equal_approx(player.role_skill_state.get_horizontal_velocity(1.0), 360.0), "Ground Rolling Ball should map 15 px/source-tick to 360 px/s.")
	_assert(enemy.health == enemy.max_health - 20, "Ground Rolling Ball should begin damage on tick 8.")
	_advance(player, 24)

	# 旋滚球 swaps the actor for its following ball on source tick 3.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(300, 440)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(7), "Spinning Ball should start.")
	_assert(player.mana == 155, "Spinning Ball should cost 45 MP.")
	_advance(player, 2)
	_assert(animator.visible, "Spinning Ball should keep Bajie visible through the opening cell.")
	_advance(player, 1)
	_assert(not animator.visible, "Spinning Ball should hide Bajie when hit11Frame2 begins.")
	_assert(enemy.health == enemy.max_health - 60, "Spinning Ball should deal source 3x damage on tick 3.")
	_advance(player, 27)
	_assert(animator.visible, "Spinning Ball should restore Bajie's layered actor at the end.")

	# 土魔刺: invulnerable guard, reflected damage, then paid second stage after tick 31.
	player.restore_mana(player.max_mana)
	player.health = 100
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(400, 515)
	enemy.health = enemy.max_health
	await physics_frame
	_assert(player.request_role_skill(8), "Earth Demon Thorns guard should start.")
	_assert(player.mana == 170, "Earth Demon Thorns first stage should cost 30 MP.")
	_advance(player, 1)
	player.take_hit(12, Vector2.ZERO, &"physical", enemy)
	_assert(player.health == 100, "Earth Demon Thorns should block incoming damage.")
	_assert(enemy.health == enemy.max_health - 24, "Earth Demon Thorns should reflect double the blocked damage.")
	_advance(player, 10)
	_assert(not animator.visible, "Earth Demon Thorns should hide Bajie on source tick 11.")
	_assert(not player.request_role_skill(8), "Earth Demon Thorns should reject reactivation before source tick 31.")
	_advance(player, 20)
	_assert(player.request_role_skill(8), "Earth Demon Thorns should reactivate from source tick 31.")
	_assert(player.mana == 140, "Earth Demon Thorns second stage should spend its second 30 MP.")
	_assert(animator.get_current_action() == &"skill_tumo_ci_finish", "Earth Demon Thorns should switch to its 20-tick finish.")
	await create_timer(0.45).timeout
	_assert(enemy.health == enemy.max_health - 38, "One focused level-one thorn should add source 14 damage after turning.")
	_advance(player, 20)
	_assert(animator.visible, "Earth Demon Thorns should restore Bajie after the second stage.")

	if _failed:
		quit(1)
	else:
		print("PASS: all Bajie active, passive, movement, defense, reflection, and two-stage skills preserve source behavior.")
		quit(0)


func _advance(player: CharacterBody2D, ticks: int) -> void:
	for _tick in range(ticks):
		player.action_state_machine.physics_process(1.01 / 24.0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
