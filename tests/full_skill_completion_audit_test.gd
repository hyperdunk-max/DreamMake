extends SceneTree

var _failed := false

const SOURCE_SKILL_MAPS := {
	1: {
		&"slz": &"shenglong_zhan", &"zz": &"zhongzhan", &"qsez": &"qishier_zhan",
		&"hmz": &"huomo_zhan", &"lys": &"lieyan_shan", &"hytj": &"huoyan_tuji",
		&"lyfb": &"lieyan_fengbao", &"jdy": &"jindou_yun", &"hyjj": &"huoyan_jinjing",
	},
	2: {
		&"sgq": &"shengguang_qiu", &"myhc": &"muyu_huichun", &"jgz": &"jingu_zhou",
		&"tjgl": &"tianjiang_ganlu", &"jhsj": &"jiuhuan_shengjing", &"blb": &"binglong_bo",
		&"xbz": &"xuanbing_zhen", &"shy": &"shuihuanying", &"smb": &"shuimo_bao",
	},
	3: {
		&"dj": &"dunji", &"sd": &"shengdun", &"zznh": &"zhanzheng_nuhou",
		&"syzq": &"shengyu_zhiqiang", &"ssp": &"suishi_po", &"jsp": &"jushi_po",
		&"dgq": &"digun_qiu", &"xgq": &"xuangun_qiu", &"tmc": &"tumo_ci",
	},
	4: {
		&"zq": &"zhang_qi", &"mbyj": &"mabi_yaoji", &"wdww": &"wudu_wawa",
		&"jdz": &"judu_zhen", &"mds": &"mengdu_su", &"qlj": &"qiangli_ji",
		&"tkj": &"tengkong_ji", &"dzj": &"duozhong_ji", &"lybj": &"lvye_biaoji",
		&"mmw": &"mumo_wu",
	},
}

const PASSIVE_SOURCE_IDS := {1: &"sx", 2: &"sjt", 3: &"rj"}
const EXPECTED_ACTIVE_COUNTS := {1: 9, 2: 8, 3: 9, 4: 10}
const EXPECTED_CALIBRATION_COUNTS := {1: 9, 2: 9, 3: 10, 4: 10}
const EXPECTED_EFFECT_COUNTS := {1: 15, 2: 10, 3: 13, 4: 23}
const MANIFEST_PATHS := {
	1: "res://assets/selected/zmxiyou3/wukong/effects/skills/manifest.json",
	2: "res://assets/selected/zmxiyou3/tangseng/effects/skills/manifest.json",
	3: "res://assets/selected/zmxiyou3/bajie/effects/skills/manifest.json",
	4: "res://assets/selected/zmxiyou3/shaseng/effects/skills/manifest.json",
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(change_scene_to_file("res://scenes/main.tscn") == OK, "Main scene should load.")
	await process_frame
	await physics_frame
	var definitions: Array = current_scene.playable_roles
	_assert(definitions.size() == 4, "The completion audit requires all four source roles.")

	for raw_definition in definitions:
		var definition := raw_definition as RoleDefinition
		var role_id := definition.role_id
		var profile := definition.skill_profile
		_assert(profile != null, "Role %d should have a skill profile." % role_id)
		if profile == null:
			continue
		_assert(profile.validate_for_role(role_id, definition.animation_profile).is_empty(), "Role %d skill profile should validate." % role_id)
		_assert(profile.get_skill_count() == int(EXPECTED_ACTIVE_COUNTS[role_id]), "Role %d active-skill count should match Config.as." % role_id)
		_assert(definition.skill_state_script != null, "Role %d should own a non-singleton skill state script." % role_id)

		var runtime_ids: Array[StringName] = []
		for skill in profile.active_skills:
			runtime_ids.append(StringName(skill.get("id", &"")))
		if not profile.charged_attack_skill.is_empty():
			runtime_ids.append(StringName(profile.charged_attack_skill.get("id", &"")))
		var source_map: Dictionary = SOURCE_SKILL_MAPS[role_id]
		for source_id in source_map:
			var runtime_id := StringName(source_map[source_id])
			_assert(runtime_ids.has(runtime_id), "Role %d source skill '%s' should map to runtime skill '%s'." % [role_id, source_id, runtime_id])
		var source_concept_count := source_map.size() + (1 if PASSIVE_SOURCE_IDS.has(role_id) else 0)
		_assert(source_concept_count == 10, "Role %d should account for both five-skill disciplines." % role_id)
		_audit_passive(role_id, profile)
		_audit_actions(role_id, definition, profile)
		_audit_effect_manifest(role_id, profile)

	if _failed:
		quit(1)
	else:
		print("PASS: all 40 source skill concepts, actions, effects, registrations, and role-specific state profiles are accounted for.")
		quit(0)


func _audit_passive(role_id: int, profile: RoleSkillProfile) -> void:
	match role_id:
		1:
			_assert(is_equal_approx(profile.passive_lifesteal_ratio, 0.05), "Wukong source passive sx should retain 5% lifesteal.")
		2:
			_assert(is_equal_approx(profile.passive_damage_multiplier, 1.3), "Tangseng source passive sjt should retain 1.3x damage.")
		3:
			_assert(profile.passive_physical_defense == 30, "Bajie source passive rj should retain +30 defense.")
			_assert(is_equal_approx(profile.passive_damage_heal_chance, 0.1), "Bajie source passive rj should retain its 10% proc.")
		4:
			_assert(not PASSIVE_SOURCE_IDS.has(role_id), "Shaseng should have ten direct source skills and no omitted passive.")


func _audit_actions(role_id: int, definition: RoleDefinition, profile: RoleSkillProfile) -> void:
	var skills: Array[Dictionary] = []
	for skill in profile.active_skills:
		skills.append(skill)
	if not profile.charged_attack_skill.is_empty():
		skills.append(profile.charged_attack_skill)
	for skill in skills:
		var skill_id := StringName(skill.get("id", &""))
		_assert(not StringName(skill.get("source_action", &"")).is_empty(), "Role %d skill '%s' should record its Flash action." % [role_id, skill_id])
		if bool(skill.get("play_action", true)):
			var action := StringName(skill.get("action", &""))
			_assert(definition.animation_profile.actions.has(action), "Role %d skill '%s' action '%s' should be calibrated." % [role_id, skill_id, action])
		if skill.has("release_action"):
			_assert(definition.animation_profile.actions.has(StringName(skill["release_action"])), "Role %d charged release action should be calibrated." % role_id)


func _audit_effect_manifest(role_id: int, profile: RoleSkillProfile) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATHS[role_id]))
	_assert(not manifest.is_empty(), "Role %d effect manifest should load." % role_id)
	var records_by_id := {}
	var records: Array = manifest.get("effects", [])
	_assert(records.size() == int(EXPECTED_EFFECT_COUNTS[role_id]), "Role %d manifest should list every extracted skill effect." % role_id)
	for raw_record in records:
		var record: Dictionary = raw_record
		var effect_id := StringName(record.get("effect_id", &""))
		records_by_id[effect_id] = record
		_assert(record.has("source_registration"), "Role %d effect '%s' should retain its SVG-derived SWF registration." % [role_id, effect_id])
		_assert(record.has("source_canvas"), "Role %d effect '%s' should retain its source canvas." % [role_id, effect_id])
	var calibration: Dictionary = manifest.get("source_calibration", {})
	_assert(calibration.size() == int(EXPECTED_CALIBRATION_COUNTS[role_id]), "Role %d should retain source coordinate calibration for every active/passive branch." % role_id)

	var used_effect_ids := {}
	var skills: Array[Dictionary] = []
	for skill in profile.active_skills:
		skills.append(skill)
	if not profile.charged_attack_skill.is_empty():
		skills.append(profile.charged_attack_skill)
	for skill in skills:
		var effects: Dictionary = skill.get("effects", {})
		for raw_spec in effects.values():
			var spec: Dictionary = raw_spec
			if bool(spec.get("derived_actor_visual", false)):
				_assert(role_id == 2, "Only Tangseng's source body-derived Water Illusion may bypass the bullet manifest.")
				continue
			var pattern := str(spec.get("effect_path_pattern", ""))
			var effect_id := StringName(pattern.get_base_dir().get_file())
			used_effect_ids[effect_id] = true
			_assert(records_by_id.has(effect_id), "Role %d runtime effect '%s' should exist in its extraction manifest." % [role_id, effect_id])
			if not records_by_id.has(effect_id):
				continue
			var record: Dictionary = records_by_id[effect_id]
			_assert(spec.has("effect_registration_point"), "Role %d runtime effect '%s' should expose its SWF registration." % [role_id, effect_id])
			_assert(spec.has("effect_source_canvas"), "Role %d runtime effect '%s' should expose its source canvas." % [role_id, effect_id])
			_assert(_array_vector(record["source_registration"]).is_equal_approx(Vector2(spec.get("effect_registration_point", Vector2.ZERO))), "Role %d effect '%s' registration should match its SVG manifest." % [role_id, effect_id])
			_assert(_array_vector(record["source_canvas"]).is_equal_approx(Vector2(spec.get("effect_source_canvas", Vector2.ZERO))), "Role %d effect '%s' canvas should match its manifest." % [role_id, effect_id])
			_assert(_array_vector(record["sprite_offset"]).is_equal_approx(Vector2(spec.get("effect_sprite_offset", Vector2.ZERO))), "Role %d effect '%s' crop offset should preserve the SWF registration." % [role_id, effect_id])
	_assert(used_effect_ids.size() == records.size(), "Role %d should use every extracted effect and no unreferenced calibration asset." % role_id)


func _array_vector(raw_value: Variant) -> Vector2:
	var values: Array = raw_value
	return Vector2(float(values[0]), float(values[1]))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
