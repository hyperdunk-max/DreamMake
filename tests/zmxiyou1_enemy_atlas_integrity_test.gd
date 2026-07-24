extends SceneTree

const PROFILE_ROOT := "res://resources/enemies/animations"

var _failed := false
var _profile_count := 0
var _action_count := 0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var files := DirAccess.get_files_at(PROFILE_ROOT)
	files.sort()
	for filename: String in files:
		if not filename.begins_with("zmxiyou1_") or not filename.ends_with("_profile.tres"):
			continue
		var profile := load(PROFILE_ROOT + "/" + filename) as EnemyAnimationProfile
		_assert(profile != null, "Animation profile must load: %s" % filename)
		if profile == null:
			continue
		_profile_count += 1
		for raw_action: Variant in profile.actions:
			_validate_action(filename, StringName(raw_action), profile.actions[raw_action] as Dictionary)
	_assert(_profile_count == 27, "Atlas audit must cover all 27 ZMX1 animation profiles.")
	_assert(_action_count == 165, "Atlas audit must cover all 165 ZMX1 runtime actions.")
	print("ZMX1 enemy atlas integrity test: %s (%d profiles, %d actions)" % [
		"FAILED" if _failed else "PASS", _profile_count, _action_count
	])
	quit(1 if _failed else 0)


func _validate_action(profile_name: String, action: StringName, spec: Dictionary) -> void:
	_action_count += 1
	var json_path := str(spec.get("sprite_sheet_json", ""))
	var sheet_path := str(spec.get("sprite_sheet", ""))
	_assert(not json_path.is_empty(), "%s/%s must keep a sprite-pack JSON path." % [profile_name, action])
	_assert(not sheet_path.is_empty(), "%s/%s must keep a sprite-pack PNG path." % [profile_name, action])
	if json_path.is_empty() or not FileAccess.file_exists(json_path):
		_assert(false, "%s/%s atlas JSON must exist: %s" % [profile_name, action, json_path])
		return
	_assert(FileAccess.file_exists(sheet_path), "%s/%s atlas PNG must exist: %s" % [profile_name, action, sheet_path])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	_assert(parsed is Dictionary, "%s/%s atlas JSON must parse." % [profile_name, action])
	if not parsed is Dictionary:
		return
	var atlas := parsed as Dictionary
	var frames := Dictionary(atlas.get("frames", {}))
	var meta := Dictionary(atlas.get("meta", {}))
	var expected := int(spec.get("frame_count", 0))
	_assert(expected > 0, "%s/%s profile frame_count must be positive." % [profile_name, action])
	_assert(
		int(meta.get("frameCount", -1)) == expected,
		"%s/%s sprite-pack meta frameCount=%d, profile=%d." % [
			profile_name, action, int(meta.get("frameCount", -1)), expected
		]
	)
	_assert(
		frames.size() == expected,
		"%s/%s sprite-pack frames=%d, profile=%d." % [profile_name, action, frames.size(), expected]
	)
	_assert(not frames.has("sprite"), "%s/%s must not contain a self-packed sprite frame." % [profile_name, action])


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
