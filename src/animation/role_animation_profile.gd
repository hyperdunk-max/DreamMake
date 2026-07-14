class_name RoleAnimationProfile
extends Resource

@export var role_id := 0
@export var role_key: StringName = &""
@export var display_name := ""
@export var logical_fps := 24.0
@export var frame_size := Vector2i(200, 200)
@export_enum("Left:-1", "Right:1") var source_facing := -1
@export var default_action: StringName = &"idle"
@export var default_body_showid := 0
@export var default_weapon_showid := 0
@export var body_atlases: Dictionary = {}
@export var body_names: Dictionary = {}
@export var weapon_atlases: Dictionary = {}
@export var weapon_names: Dictionary = {}
@export var actions: Dictionary = {}


func validate_for_role(expected_role_id: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if expected_role_id <= 0:
		errors.append("Role id must be positive.")
	if role_id != expected_role_id:
		errors.append("Profile role_id %d does not match requested role_id %d." % [role_id, expected_role_id])
	if logical_fps <= 0.0:
		errors.append("logical_fps must be greater than zero.")
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("frame_size must be positive.")
	if get_body_atlas(default_body_showid) == null:
		errors.append("Default body showid %d is missing." % default_body_showid)
	if get_weapon_atlas(default_weapon_showid) == null:
		errors.append("Default weapon showid %d is missing." % default_weapon_showid)
	if not actions.has(default_action):
		errors.append("Default action '%s' is missing." % default_action)
	return errors


func compile_animations() -> Dictionary:
	var compiled := {}
	for raw_action_id: Variant in actions:
		var action_id := StringName(raw_action_id)
		var config: Dictionary = actions[raw_action_id]
		var frames: Array[Vector3i] = []
		for raw_segment: Variant in config.get("segments", []):
			var segment: Dictionary = raw_segment
			var row := int(segment.get("row", 0))
			var start_column := int(segment.get("start_column", 0))
			var cycles := maxi(1, int(segment.get("cycles", 1)))
			var holds: PackedInt32Array = segment.get("holds", PackedInt32Array([1]))
			for _cycle in range(cycles):
				for column_offset in range(holds.size()):
					frames.append(
						Vector3i(
							start_column + column_offset,
							row,
							maxi(1, holds[column_offset])
						)
					)
		if not frames.is_empty():
			compiled[action_id] = {
				"frames": frames,
				"loop": bool(config.get("loop", false)),
			}
	return compiled


func get_body_atlas(showid: int) -> Texture2D:
	return body_atlases.get(showid) as Texture2D


func get_weapon_atlas(showid: int) -> Texture2D:
	return weapon_atlases.get(showid) as Texture2D


func get_body_name(showid: int) -> String:
	return str(body_names.get(showid, "未知防具"))


func get_weapon_name(showid: int) -> String:
	return str(weapon_names.get(showid, "未知武器"))


func get_next_weapon_showid(current_showid: int, step := 1) -> int:
	var ids: Array = weapon_atlases.keys()
	ids.sort()
	if ids.is_empty():
		return current_showid
	var current_index := ids.find(current_showid)
	if current_index < 0:
		return int(ids[0])
	return int(ids[posmod(current_index + step, ids.size())])
