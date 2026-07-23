class_name EnemyAnimationProfile
extends Resource

## Runtime animation configuration for an enemy whose source frames were
## exported from a Flash timeline.

@export var default_animation: StringName = &"idle"
@export var source_monster_id: StringName = &""
@export var source_package: StringName = &""
@export_file("*.json") var source_event_audit: String = ""
@export var actions: Dictionary = {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if actions.is_empty():
		errors.append("Enemy animation profile has no actions.")
		return errors
	for raw_name: Variant in actions:
		var action := StringName(raw_name)
		var spec: Dictionary = actions[raw_name]
		var frame_count := int(spec.get("frame_count", 0))
		var has_sprite_sheet := not str(spec.get("sprite_sheet", "")).is_empty()
		var pattern := str(spec.get("path_pattern", ""))
		if frame_count <= 0:
			errors.append("Enemy animation '%s' has no frames." % action)
		if not has_sprite_sheet and (pattern.is_empty() or not pattern.contains("%")):
			errors.append("Enemy animation '%s' needs path_pattern or sprite_sheet." % action)
		if float(spec.get("fps", 0.0)) <= 0.0:
			errors.append("Enemy animation '%s' has an invalid fps." % action)
		var source_events: Variant = spec.get("source_events", [])
		if not source_events is Array:
			errors.append("Enemy animation '%s' source_events must be an Array." % action)
			continue
		for raw_event: Variant in source_events:
			if not raw_event is Dictionary:
				errors.append("Enemy animation '%s' has a non-Dictionary source event." % action)
				continue
			var source_event := raw_event as Dictionary
			var event_frame := int(source_event.get("frame", -1))
			if event_frame < 0 or event_frame >= frame_count:
				errors.append(
					"Enemy animation '%s' source event frame %d is outside 0..%d."
					% [action, event_frame, frame_count - 1]
				)
			if str(source_event.get("id", "")).is_empty():
				errors.append("Enemy animation '%s' has a source event without an id." % action)
	return errors


func build_sprite_frames() -> SpriteFrames:
	var result := SpriteFrames.new()
	result.remove_animation(&"default")
	for raw_name: Variant in actions:
		var action := StringName(raw_name)
		var spec: Dictionary = actions[raw_name]
		result.add_animation(action)
		result.set_animation_speed(action, float(spec.get("fps", 24.0)))
		result.set_animation_loop(action, bool(spec.get("loop", false)))
		if not str(spec.get("sprite_sheet", "")).is_empty():
			_build_from_sprite_sheet(result, action, spec)
		else:
			_build_from_frames(result, action, spec)
	return result


func _build_from_sprite_sheet(result: SpriteFrames, action: StringName, spec: Dictionary) -> void:
	var sheet_path := str(spec.get("sprite_sheet", ""))
	var json_path := str(spec.get("sprite_sheet_json", ""))
	if sheet_path.is_empty() or json_path.is_empty():
		push_error("Sprite sheet spec for '%s' missing sprite_sheet or sprite_sheet_json" % action)
		return
	# Use Image.load to bypass Godot .import system for paths with CJK characters
	var image := Image.new()
	var img_error := image.load(sheet_path)
	if img_error != OK:
		push_error("Cannot load sprite sheet image: %s (error %d)" % [sheet_path, img_error])
		return
	var texture := ImageTexture.create_from_image(image)
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open sprite sheet JSON: %s" % json_path)
		return
	var json_text := file.get_as_text()
	var data: Variant = JSON.parse_string(json_text)
	if data == null:
		push_error("Failed to parse sprite sheet JSON: %s" % json_path)
		return
	var frames_data: Dictionary = data.get("frames", {})
	var meta: Dictionary = data.get("meta", {})
	var expected_frame_count := int(spec.get("frame_count", 0))
	if expected_frame_count > 0 and frames_data.size() != expected_frame_count:
		push_error(
			"Sprite sheet frame count mismatch for '%s': profile=%d json=%d"
			% [action, expected_frame_count, frames_data.size()]
		)
	var sorted_names := PackedStringArray(frames_data.keys())
	sorted_names.sort()
	for frame_name: String in sorted_names:
		var frame_info: Dictionary = frames_data[frame_name]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		if bool(meta.get("trimmed", false)) and frame_info.has("ox"):
			# trim_sprites.py stores content at (1, 1) inside every atlas slot.
			# AtlasTexture.margin restores the original frame canvas so existing
			# per-action offsets and frame-to-frame registration remain stable.
			var original_size: Dictionary = meta.get("originalFrameSize", {})
			var content_width := float(frame_info.get("cw", frame_info.get("w", 64)))
			var content_height := float(frame_info.get("ch", frame_info.get("h", 64)))
			var original_width := float(original_size.get("w", content_width))
			var original_height := float(original_size.get("h", content_height))
			atlas.region = Rect2(
				float(frame_info.get("x", 0)) + 1.0,
				float(frame_info.get("y", 0)) + 1.0,
				content_width,
				content_height
			)
			atlas.margin = Rect2(
				-float(frame_info.get("ox", 0)),
				-float(frame_info.get("oy", 0)),
				original_width - content_width,
				original_height - content_height
			)
		else:
			atlas.region = Rect2(
				float(frame_info.get("x", 0)),
				float(frame_info.get("y", 0)),
				float(frame_info.get("w", 64)),
				float(frame_info.get("h", 64))
			)
		result.add_frame(action, atlas)


func _build_from_frames(result: SpriteFrames, action: StringName, spec: Dictionary) -> void:
	var pattern := str(spec.get("path_pattern", ""))
	var frame_count := int(spec.get("frame_count", 0))
	for frame_number in range(1, frame_count + 1):
		var file_path := pattern % frame_number
		var abs_path := ProjectSettings.globalize_path(file_path)
		var image := Image.new()
		var err := image.load(abs_path)
		if err != OK:
			push_error("Missing enemy animation frame: %s (error %d)" % [abs_path, err])
			continue
		var texture := ImageTexture.create_from_image(image)
		result.add_frame(action, texture)


func get_spec(action: StringName) -> Dictionary:
	return actions.get(action, {}) as Dictionary


func get_display_name(action: StringName) -> String:
	return str(get_spec(action).get("display_name", action))


func get_offset(action: StringName) -> Vector2:
	return Vector2(get_spec(action).get("sprite_offset", Vector2.ZERO))


func get_event_frames(action: StringName) -> PackedInt32Array:
	return PackedInt32Array(get_spec(action).get("event_frames", PackedInt32Array()))


func get_source_events(action: StringName) -> Array:
	var value: Variant = get_spec(action).get("source_events", [])
	return value as Array if value is Array else []


func get_source_event_frames(action: StringName) -> PackedInt32Array:
	var frames := PackedInt32Array()
	for raw_event: Variant in get_source_events(action):
		if not raw_event is Dictionary:
			continue
		var event_frame := int((raw_event as Dictionary).get("frame", -1))
		if event_frame >= 0 and event_frame not in frames:
			frames.append(event_frame)
	frames.sort()
	return frames


func get_source_events_at_frame(action: StringName, frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_event: Variant in get_source_events(action):
		if raw_event is Dictionary and int((raw_event as Dictionary).get("frame", -1)) == frame:
			result.append(raw_event as Dictionary)
	return result


func is_source_hitbox_active(action: StringName, frame: int) -> bool:
	var frame_range := Vector2i(get_spec(action).get("hitbox_frame_range", Vector2i(-1, -1)))
	return frame_range.x >= 0 and frame >= frame_range.x and frame <= frame_range.y


func get_next_animation(action: StringName) -> StringName:
	return StringName(get_spec(action).get("next_animation", default_animation))
