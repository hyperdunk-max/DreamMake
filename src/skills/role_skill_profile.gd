class_name RoleSkillProfile
extends Resource

@export var role_id := 0
@export var logical_fps := 24.0
@export var passive_lifesteal_ratio := 0.0
@export var passive_damage_multiplier := 1.0
@export var passive_physical_defense := 0
@export var passive_damage_heal_chance := 0.0
@export var passive_damage_heal_amount := 0
@export var charged_attack_skill: Dictionary = {}
@export var active_skills: Array[Dictionary] = []


func validate_for_role(expected_role_id: int, animation_profile: RoleAnimationProfile = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if role_id != expected_role_id:
		errors.append("Skill profile role_id %d does not match role %d." % [role_id, expected_role_id])
	if logical_fps <= 0.0:
		errors.append("Role %d skill logical_fps must be positive." % role_id)
	for index in range(active_skills.size()):
		var skill := active_skills[index]
		var skill_id := StringName(skill.get("id", &""))
		var action := StringName(skill.get("action", &""))
		if skill_id.is_empty():
			errors.append("Role %d skill slot %d has no id." % [role_id, index])
		if action.is_empty() and bool(skill.get("play_action", true)):
			errors.append("Role %d skill '%s' has no action." % [role_id, skill_id])
		elif not action.is_empty() and animation_profile != null and not animation_profile.actions.has(action):
			errors.append("Role %d skill '%s' action '%s' is missing." % [role_id, skill_id, action])
		if int(skill.get("mana_cost", -1)) < 0:
			errors.append("Role %d skill '%s' has an invalid mana cost." % [role_id, skill_id])
		if int(skill.get("duration_ticks", 0)) <= 0:
			errors.append("Role %d skill '%s' has an invalid duration." % [role_id, skill_id])
	if passive_damage_multiplier <= 0.0:
		errors.append("Role %d passive damage multiplier must be positive." % role_id)
	if passive_physical_defense < 0:
		errors.append("Role %d passive physical defense cannot be negative." % role_id)
	if passive_damage_heal_chance < 0.0 or passive_damage_heal_chance > 1.0:
		errors.append("Role %d passive heal chance must be between zero and one." % role_id)
	if passive_damage_heal_amount < 0:
		errors.append("Role %d passive heal amount cannot be negative." % role_id)
	if not charged_attack_skill.is_empty():
		var charged_id := StringName(charged_attack_skill.get("id", &""))
		var charged_action := StringName(charged_attack_skill.get("action", &""))
		var release_action := StringName(charged_attack_skill.get("release_action", &""))
		if charged_id.is_empty() or charged_action.is_empty():
			errors.append("Role %d charged attack is missing its id or action." % role_id)
		if int(charged_attack_skill.get("charge_ticks", 0)) <= 0:
			errors.append("Role %d charged attack has an invalid charge duration." % role_id)
		if int(charged_attack_skill.get("mana_cost", -1)) < 0:
			errors.append("Role %d charged attack has an invalid mana cost." % role_id)
		if animation_profile != null:
			if not charged_action.is_empty() and not animation_profile.actions.has(charged_action):
				errors.append("Role %d charged attack action '%s' is missing." % [role_id, charged_action])
			if not release_action.is_empty() and not animation_profile.actions.has(release_action):
				errors.append("Role %d charged release action '%s' is missing." % [role_id, release_action])
	return errors


func get_skill(slot: int) -> Dictionary:
	if slot < 0 or slot >= active_skills.size():
		return {}
	return active_skills[slot]


func get_skill_count() -> int:
	return active_skills.size()


func find_skill_index(skill_id: StringName) -> int:
	for index in range(active_skills.size()):
		if StringName(active_skills[index].get("id", &"")) == skill_id:
			return index
	return -1
