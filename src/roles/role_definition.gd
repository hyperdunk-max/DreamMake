class_name RoleDefinition
extends Resource

@export var role_id := 0
@export var display_name := ""
@export var animation_profile: RoleAnimationProfile
@export var combo_attack_profile: ComboAttackProfile
@export var combo_attack_profiles_by_mode: Dictionary = {}
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
	return errors


func get_combo_profile_for_weapon(weapon_showid: int) -> ComboAttackProfile:
	if animation_profile == null:
		return combo_attack_profile
	var mode := animation_profile.get_weapon_mode(weapon_showid)
	return combo_attack_profiles_by_mode.get(mode, combo_attack_profile) as ComboAttackProfile
