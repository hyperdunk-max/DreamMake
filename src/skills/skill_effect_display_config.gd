class_name SkillEffectDisplayConfig
extends RefCounted

const CONFIG_PATH := "res://resources/skill_effect_display_overrides.json"

static var _loaded := false
static var _offsets: Dictionary = {}


static func make_key(role_id: int, skill_id: StringName, effect_id: StringName) -> String:
	return "%d/%s/%s" % [role_id, str(skill_id), str(effect_id)]


static func get_offset(
	role_id: int, skill_id: StringName, effect_id: StringName, fallback: Vector2
) -> Vector2:
	return get_offset_by_key(make_key(role_id, skill_id, effect_id), fallback)


static func get_offset_by_key(key: String, fallback: Vector2) -> Vector2:
	_ensure_loaded()
	var raw_value: Variant = _offsets.get(key)
	if raw_value is Array and raw_value.size() >= 2:
		return Vector2(float(raw_value[0]), float(raw_value[1]))
	return fallback


static func save_offset_by_key(key: String, offset: Vector2) -> Error:
	_ensure_loaded()
	_offsets[key] = [offset.x, offset.y]
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 1, "offsets": _offsets}, "\t") + "\n")
	file.close()
	return OK


static func reload() -> void:
	_loaded = false
	_offsets.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_offsets.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		var parsed_offsets: Variant = parsed.get("offsets", {})
		if parsed_offsets is Dictionary:
			_offsets = parsed_offsets.duplicate(true)
