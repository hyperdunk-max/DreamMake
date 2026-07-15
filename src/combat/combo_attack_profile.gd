class_name ComboAttackProfile
extends Resource

@export var role_id := 0
@export var logical_fps := 24.0
@export var combo_window_seconds := 1.5
@export var steps: Array = []


func validate_for_role(expected_role_id: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if role_id != expected_role_id:
		errors.append("Combo profile role_id %d does not match role_id %d." % [role_id, expected_role_id])
	if logical_fps <= 0.0:
		errors.append("Combo profile logical_fps must be positive.")
	if combo_window_seconds <= 0.0:
		errors.append("Combo window must be positive.")
	if steps.is_empty():
		errors.append("Combo profile must contain at least one step.")
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		if StringName(step.get("action", &"")).is_empty():
			errors.append("Combo step %d has no animation action." % index)
		if int(step.get("duration_ticks", 0)) <= 0:
			errors.append("Combo step %d has an invalid duration." % index)
		if StringName(step.get("delivery", &"melee")) == &"projectile":
			var frame_hitboxes: Array = Array(step.get("projectile_frame_hitboxes", []))
			var effect_frame_count := int(step.get("effect_frame_count", 0))
			if frame_hitboxes.size() != effect_frame_count:
				errors.append(
					"Projectile combo step %d has %d hitbox frames for %d effect frames."
					% [index, frame_hitboxes.size(), effect_frame_count]
				)
	return errors


func get_step(index: int) -> Dictionary:
	return steps[posmod(index, steps.size())]


func get_step_count() -> int:
	return steps.size()
