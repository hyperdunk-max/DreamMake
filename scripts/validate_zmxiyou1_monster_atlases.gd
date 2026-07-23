extends SceneTree

const PROFILE_DIR := "res://resources/enemies/animations"


func _initialize() -> void:
	var failures := PackedStringArray()
	var profile_count := 0
	var action_count := 0
	var directory := DirAccess.open(PROFILE_DIR)
	if directory == null:
		push_error("Cannot open enemy animation profile directory")
		quit(1)
		return

	for file_name in directory.get_files():
		if not file_name.begins_with("zmxiyou1_") or not file_name.ends_with("_profile.tres"):
			continue
		var profile_path := PROFILE_DIR.path_join(file_name)
		var profile: EnemyAnimationProfile = load(profile_path) as EnemyAnimationProfile
		if profile == null:
			failures.append("Cannot load %s" % profile_path)
			continue
		profile_count += 1
		for error in profile.validate():
			failures.append("%s: %s" % [file_name, error])
		var sprite_frames := profile.build_sprite_frames()
		for raw_action: Variant in profile.actions:
			var action := StringName(raw_action)
			var expected := int(profile.get_spec(action).get("frame_count", 0))
			var actual := sprite_frames.get_frame_count(action)
			action_count += 1
			if actual != expected:
				failures.append(
					"%s/%s: expected %d frames, built %d"
					% [file_name, action, expected, actual]
				)

	if failures.is_empty():
		print("validated zmxiyou1 atlas profiles=%d actions=%d" % [profile_count, action_count])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
