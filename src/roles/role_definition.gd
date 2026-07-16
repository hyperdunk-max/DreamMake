class_name RoleDefinition
extends Resource

@export var role_id := 0
@export var display_name := ""
@export var animation_profile: RoleAnimationProfile
@export var combo_attack_profile: ComboAttackProfile
@export var combo_attack_profiles_by_mode: Dictionary = {}
@export var air_attack_step_index := -1
@export var air_attack_overrides: Dictionary = {}
@export var skill_profile: RoleSkillProfile
@export var skill_state_script: Script
@export var default_body_showid := -1
@export var default_weapon_showid := -1


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if role_id <= 0:
		errors.append("Role definition id must be positive.")
	if animation_profile == null:
		errors.append("Role %d has no animation profile." % role_id)
	else:
		errors.append_array(animation_profile.validate_for_role(role_id))
	if combo_attack_profile == null:
		errors.append("Role %d has no combo profile." % role_id)
	else:
		errors.append_array(combo_attack_profile.validate_for_role(role_id))
	for mode in combo_attack_profiles_by_mode:
		var mode_profile := combo_attack_profiles_by_mode[mode] as ComboAttackProfile
		if mode_profile == null:
			errors.append("Role %d mode '%s' has no combo profile." % [role_id, mode])
		else:
			errors.append_array(mode_profile.validate_for_role(role_id))
	if air_attack_step_index >= 0:
		if combo_attack_profile == null or air_attack_step_index >= combo_attack_profile.get_step_count():
			errors.append("Role %d has an invalid air attack source step %d." % [role_id, air_attack_step_index])
		else:
			var air_step := get_air_attack_step()
			if int(air_step.get("duration_ticks", 0)) <= 0:
				errors.append("Role %d air attack has an invalid duration." % role_id)
	if skill_profile != null:
		errors.append_array(skill_profile.validate_for_role(role_id, animation_profile))
		if skill_state_script == null:
			errors.append("Role %d has a skill profile but no skill state script." % role_id)
	return errors


func get_combo_profile_for_weapon(weapon_showid: int) -> ComboAttackProfile:
	if animation_profile == null:
		return combo_attack_profile
	var mode := animation_profile.get_weapon_mode(weapon_showid)
	return combo_attack_profiles_by_mode.get(mode, combo_attack_profile) as ComboAttackProfile


func get_air_attack_step() -> Dictionary:
	if combo_attack_profile == null or air_attack_step_index < 0 or air_attack_step_index >= combo_attack_profile.get_step_count():
		return {}
	var step := combo_attack_profile.get_step(air_attack_step_index).duplicate(true)
	step.merge(air_attack_overrides, true)
	return step
