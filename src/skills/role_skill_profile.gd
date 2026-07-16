class_name RoleSkillProfile
extends Resource

@export var role_id := 0
@export var logical_fps := 24.0
@export var passive_lifesteal_ratio := 0.0
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
		if action.is_empty():
			errors.append("Role %d skill '%s' has no action." % [role_id, skill_id])
		elif animation_profile != null and not animation_profile.actions.has(action):
			errors.append("Role %d skill '%s' action '%s' is missing." % [role_id, skill_id, action])
		if int(skill.get("mana_cost", -1)) < 0:
			errors.append("Role %d skill '%s' has an invalid mana cost." % [role_id, skill_id])
		if int(skill.get("duration_ticks", 0)) <= 0:
			errors.append("Role %d skill '%s' has an invalid duration." % [role_id, skill_id])
	return errors


func get_skill(slot: int) -> Dictionary:
	if slot < 0 or slot >= active_skills.size():
		return {}
	return active_skills[slot]


func get_skill_count() -> int:
	return active_skills.size()
