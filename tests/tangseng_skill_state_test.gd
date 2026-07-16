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
	var tangseng: RoleDefinition = main.playable_roles[1]
	var profile: RoleSkillProfile = tangseng.skill_profile
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/selected/zmxiyou3/tangseng/effects/skills/manifest.json")
	)

	_assert(profile != null, "Tangseng should provide a skill profile.")
	_assert(profile.validate_for_role(2, tangseng.animation_profile).is_empty(), "Tangseng skill profile should validate.")
	_assert(profile.get_skill_count() == 8, "Tangseng should expose eight direct active skills.")
	_assert(not profile.charged_attack_skill.is_empty(), "Ice Dragon Wave should be represented as the charged normal attack branch.")
	_assert(is_equal_approx(profile.passive_damage_multiplier, 1.3), "Water Mastery should preserve the source 1.3x multiplier.")
	_assert((manifest.get("source_calibration", {}) as Dictionary).size() == 9, "Every active or conditional Tangseng skill should have placement calibration.")
	var manifest_effects: Array = manifest.get("effects", [])
	_assert(manifest_effects.size() == 10, "Every extracted Tangseng effect should retain registration metadata.")
	for effect_record in manifest_effects:
		_assert((effect_record as Dictionary).has("source_registration"), "Every Tangseng effect should record its SWF registration point.")
	_assert(int(profile.active_skills[0].get("repeat_count", 0)) == 4, "Holy Light Orb should retain four source hit opportunities.")
	_assert(int(profile.active_skills[1].get("heal_repeat_count", 0)) == 10, "Bathing Rejuvenation should retain ten source healing ticks.")
	var rain_effect: Dictionary = (profile.active_skills[3].get("effects", {}) as Dictionary).get(&"rain", {})
	_assert(int(rain_effect.get("blend_mode", -1)) == CanvasItemMaterial.BLEND_MODE_SUB, "Heavenly Nectar should preserve the source subtract blend mode.")
	# Keep this focused test short after proving the source schedules above.
	profile.active_skills[0]["repeat_count"] = 1
	profile.active_skills[1]["heal_repeat_count"] = 1
	for action in [
		&"skill_shengguang_qiu", &"skill_muyu_huichun", &"skill_jingu_zhou",
		&"skill_tianjiang_ganlu", &"skill_jiuhuan_shengjing", &"skill_xuanbing_zhen",
		&"skill_shuimo_bao_marker", &"skill_shuimo_bao_blast",
		&"skill_binglong_charge", &"skill_binglong_release"
	]:
		_assert(tangseng.animation_profile.actions.has(action), "Tangseng should provide action '%s'." % action)

	_assert(player.configure_role(tangseng), "Tangseng should configure.")
	_assert(player.role_skill_state is TangsengSkillState, "Tangseng should own an isolated TangsengSkillState.")
	player.facing = 1.0
	player.global_position = Vector2(250, 515)
	player.velocity = Vector2.ZERO
	enemy.global_position = Vector2(425, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame
	var beam_spec: Dictionary = (profile.charged_attack_skill.get("effects", {}) as Dictionary).get(&"beam", {})
	var beam_origin: Vector2 = player.flash_actor_point(Vector2(50, 10))
	var beam_center: Vector2 = player.role_skill_effect_bounds_center(beam_spec, beam_origin)
	_assert(beam_center.is_equal_approx(player.global_position + Vector2(499.975, -35)), "Ice Dragon Wave should restore the source registration point when facing right.")
	player.facing = -1.0
	beam_origin = player.flash_actor_point(Vector2(50, 10))
	beam_center = player.role_skill_effect_bounds_center(beam_spec, beam_origin)
	_assert(beam_center.is_equal_approx(player.global_position + Vector2(-499.975, -35)), "Ice Dragon Wave registration should mirror around the actor when facing left.")
	player.facing = 1.0

	# 圣光球: 20 MP, long source charge, then a persistent four-hit orb.
	_assert(player.request_role_skill(0), "Holy Light Orb should start.")
	_assert(player.mana == 180, "Holy Light Orb should cost 20 MP.")
	_advance(player, 50)
	_assert(enemy.health == enemy.max_health, "Holy Light Orb should wait through source tick 50.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 40, "Holy Light Orb should deal source 2x base damage on tick 51.")
	_advance(player, 14)
	_assert(not player.action_state_machine.has_active_state(), "Holy Light Orb body action should finish after 65 ticks.")

	# 紧箍咒: pull nearby enemies and grant one 1.3x outgoing hit.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(430, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame
	_assert(player.request_role_skill(2), "Tightening Spell should start.")
	_assert(player.mana == 150, "Tightening Spell should cost 50 MP.")
	_advance(player, 5)
	await create_timer(0.7).timeout
	_assert(enemy.global_position.x > 440.0, "Tightening Spell should pull the target toward the source destination.")
	_advance(player, 9)
	enemy.health = enemy.max_health
	player.apply_role_skill_hit(enemy, 10, Vector2.ZERO)
	_assert(enemy.health == enemy.max_health - 13, "Tightening Spell should amplify exactly one following hit by 1.3x.")

	# 九环圣经: opening aura and nine interval strikes from source hit9.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(400, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame
	_assert(player.request_role_skill(4), "Nine-ring Sutra should start.")
	_assert(player.mana == 100, "Nine-ring Sutra should cost 100 MP.")
	_advance(player, 11)
	_assert(enemy.health == enemy.max_health - 20, "Nine-ring Sutra strike should begin on tick 11.")
	_advance(player, 44)
	_assert(enemy.health == enemy.max_health - 180, "Nine-ring Sutra should apply nine source interval hits.")

	# 玄冰阵: water-mastery-adjusted 0.8x damage at source tick 13.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	enemy.global_position = Vector2(250, 515)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame
	_assert(player.request_role_skill(5), "Mystic Ice Formation should start.")
	_assert(player.mana == 180, "Mystic Ice Formation should cost 20 MP.")
	_advance(player, 12)
	_assert(enemy.health == enemy.max_health, "Mystic Ice Formation should wait for source tick 13.")
	_advance(player, 1)
	_assert(enemy.health == enemy.max_health - 20, "Water Mastery should floor 0.8x * 1.3x base damage to 20.")
	_advance(player, 41)

	# 水幻影: first press leaves the exact shadow atlas; second press teleports.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	await physics_frame
	_assert(player.request_role_skill(6), "Water Illusion should create a shadow.")
	_advance(player, 1)
	_assert(player.mana == 160, "Water Illusion should cost 40 MP on creation.")
	player.global_position = Vector2(520, 515)
	await physics_frame
	_assert(player.request_role_skill(6), "Water Illusion should reactivate from idle.")
	_advance(player, 1)
	_assert(player.global_position.is_equal_approx(Vector2(250, 515)), "Second Water Illusion should teleport to the stored source point.")
	_assert(player.mana == 120, "Water Illusion teleport should preserve the source second 40 MP cost.")

	# 水魔爆: moving marker costs MP once; second press detonates without another spend.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	await physics_frame
	_assert(player.request_role_skill(7), "Water Demon Burst marker should start.")
	_assert(player.mana == 100, "Water Demon Burst should cost 100 MP once.")
	_advance(player, 4)
	_assert(not player.action_state_machine.has_active_state(), "Water Demon Burst marker action should release the actor.")
	player.spend_mana(100)
	enemy.global_position = Vector2(410, 300)
	enemy.velocity = Vector2.ZERO
	enemy.health = enemy.max_health
	await physics_frame
	await process_frame
	_assert(player.request_role_skill(7), "Water Demon Burst should detonate its existing marker even at zero MP.")
	_assert(player.mana == 0, "Water Demon Burst detonation must not spend MP twice.")
	_assert(animator.get_current_action() == &"skill_shuimo_bao_blast", "Water Demon Burst should play source hit4_2.")
	_advance(player, 5)
	_assert(enemy.health == enemy.max_health - 208, "Water Mastery should produce source level-one Water Demon Burst damage.")
	_advance(player, 5)

	# 冰龙波: tap falls back to normal attack; 48-tick hold spends 20 MP.
	player.restore_mana(player.max_mana)
	player.global_position = Vector2(250, 515)
	player.velocity = Vector2.ZERO
	await physics_frame
	_assert(player.request_normal_attack(), "Tangseng normal attack should enter the charge-aware source branch.")
	_advance(player, 47)
	_assert(player.role_skill_state.release_normal_attack(), "Releasing a short charge should be accepted.")
	_advance(player, 1)
	_assert(player.mana == 200, "A short Ice Dragon Wave charge should fall back without spending MP.")
	_assert(player.request_normal_attack(), "Tangseng should be able to charge again.")
	_advance(player, 48)
	_assert(player.role_skill_state.release_normal_attack(), "A complete Ice Dragon Wave charge should release.")
	_assert(player.mana == 180, "Ice Dragon Wave should cost 20 MP after 48 held ticks.")
	_advance(player, 1)

	# 天降甘露 and 沐浴回春 preserve their delayed healing schedules.
	player.restore_mana(player.max_mana)
	player.health = 40
	player.global_position = Vector2(250, 515)
	await physics_frame
	_assert(player.request_role_skill(3), "Heavenly Nectar should start.")
	_advance(player, 30)
	await create_timer(1.25).timeout
	_assert(player.health == 70, "Heavenly Nectar should restore 30% max HP after 1.2 seconds.")
	player.restore_mana(player.max_mana)
	player.health = 40
	_assert(player.request_role_skill(1), "Bathing Rejuvenation should start.")
	_advance(player, 24)
	await create_timer(0.95).timeout
	_assert(player.health == 45, "Bathing Rejuvenation should begin its ten-second 5 HP-per-second heal after 0.9 seconds.")

	if _failed:
		quit(1)
	else:
		print("PASS: all Tangseng active, charged, passive, healing, shadow, and two-stage skills preserve source behavior.")
		quit(0)


func _advance(player: CharacterBody2D, ticks: int) -> void:
	for _tick in range(ticks):
		player.action_state_machine.physics_process(1.01 / 24.0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
