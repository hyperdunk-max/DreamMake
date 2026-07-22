class_name RoleAnimationProfile
extends Resource

@export var role_id := 0
@export var role_key: StringName = &""
@export var display_name := ""
@export var logical_fps := 24.0
@export var frame_size := Vector2i(200, 200)
@export_enum("Left:-1", "Right:1") var source_facing := -1
@export var visual_offset := Vector2.ZERO
@export var visual_nudge := Vector2.ZERO
@export var weapon_z_index := 1
@export var default_action: StringName = &"idle"
@export var default_body_showid := 0
@export var default_weapon_showid := 0
@export var body_atlases: Dictionary = {}
@export var body_atlas_paths: Dictionary = {}
@export var body_names: Dictionary = {}
@export var weapon_atlases: Dictionary = {}
@export var weapon_atlas_paths: Dictionary = {}
@export var weapon_names: Dictionary = {}
@export var actions: Dictionary = {}
@export var weapon_modes: Dictionary = {}
@export var body_atlas_paths_by_mode: Dictionary = {}
@export var actions_by_mode: Dictionary = {}

var _texture_cache: Dictionary = {}


func get_runtime_visual_offset() -> Vector2:
	return visual_offset + visual_nudge


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
	if get_body_atlas(default_body_showid, default_weapon_showid) == null:
		errors.append("Default body showid %d is missing." % default_body_showid)
	if get_weapon_atlas(default_weapon_showid) == null:
		errors.append("Default weapon showid %d is missing." % default_weapon_showid)
	if not actions.has(default_action):
		errors.append("Default action '%s' is missing." % default_action)
	return errors


func compile_animations(weapon_showid := -1) -> Dictionary:
	var compiled := {}
	var selected_actions := actions
	var mode := get_weapon_mode(default_weapon_showid if weapon_showid < 0 else weapon_showid)
	if actions_by_mode.has(mode):
		selected_actions = actions_by_mode[mode]
	for raw_action_id: Variant in selected_actions:
		var action_id := StringName(raw_action_id)
		var config: Dictionary = selected_actions[raw_action_id]
		var frames: Array[Vector3i] = []
		if config.has("frame_count"):
			var frame_count := maxi(1, int(config.get("frame_count", 1)))
			var row := int(config.get("row", 0))
			var start_column := int(config.get("start_column", 0))
			var grid_columns := int(config.get("grid_columns", 0))
			for column_offset in range(frame_count):
				var atlas_column := start_column + column_offset
				var frame_row := row
				if grid_columns > 0:
					frame_row += atlas_column / grid_columns
					atlas_column = posmod(atlas_column, grid_columns)
				frames.append(Vector3i(atlas_column, frame_row, 1))
			compiled[StringName(raw_action_id)] = {
				"frames": frames,
				"loop": bool(config.get("loop", false)),
			}
			continue
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


func get_body_atlas(showid: int, weapon_showid := -1) -> Texture2D:
	var selected_weapon := default_weapon_showid if weapon_showid < 0 else weapon_showid
	var mode := get_weapon_mode(selected_weapon)
	if body_atlas_paths_by_mode.has(mode):
		var mode_paths: Dictionary = body_atlas_paths_by_mode[mode]
		var mode_texture := _load_texture(mode_paths.get(showid))
		if mode_texture != null:
			return mode_texture
	var atlas := body_atlases.get(showid) as Texture2D
	if atlas != null:
		return atlas
	return _load_texture(body_atlas_paths.get(showid))


func get_weapon_atlas(showid: int) -> Texture2D:
	var atlas := weapon_atlases.get(showid) as Texture2D
	if atlas != null:
		return atlas
	return _load_texture(weapon_atlas_paths.get(showid))


func get_body_name(showid: int) -> String:
	return str(body_names.get(showid, "未知防具"))


func get_weapon_name(showid: int) -> String:
	return str(weapon_names.get(showid, "未知武器"))


func get_next_weapon_showid(current_showid: int, step := 1) -> int:
	var ids: Array = get_weapon_showids()
	ids.sort()
	if ids.is_empty():
		return current_showid
	var current_index := ids.find(current_showid)
	if current_index < 0:
		return int(ids[0])
	return int(ids[posmod(current_index + step, ids.size())])


func get_next_body_showid(current_showid: int, step := 1) -> int:
	var ids: Array = get_body_showids()
	ids.sort()
	if ids.is_empty():
		return current_showid
	var current_index := ids.find(current_showid)
	if current_index < 0:
		return int(ids[0])
	return int(ids[posmod(current_index + step, ids.size())])


func get_body_showids() -> Array:
	var ids: Array = body_atlases.keys()
	for showid in body_atlas_paths:
		if not ids.has(showid):
			ids.append(showid)
	return ids


func get_weapon_showids() -> Array:
	var ids: Array = weapon_atlases.keys()
	for showid in weapon_atlas_paths:
		if not ids.has(showid):
			ids.append(showid)
	return ids


func get_weapon_mode(showid: int) -> StringName:
	return StringName(weapon_modes.get(showid, &"default"))


func _load_texture(raw_path: Variant) -> Texture2D:
	var path := str(raw_path)
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	if texture != null:
		_texture_cache[path] = texture
	return texture
