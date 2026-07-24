class_name SpriteSheetAtlas
extends RefCounted

## Shared loader for the project's sprite.png + sprite.json contract.
## Keeps trimmed-frame registration stable and exposes per-frame visible bounds
## for Godot collision queries without changing the packed atlas format.


static func load_atlas(sheet_path: String, json_path: String, include_image := false) -> Dictionary:
	if sheet_path.is_empty() or json_path.is_empty():
		return {}
	var texture: Texture2D = null
	# Freshly selected atlases may not have an editor-generated .import entry
	# yet. Avoid a noisy failed load and use ImageTexture until import catches up.
	if ResourceLoader.exists(sheet_path):
		texture = ResourceLoader.load(sheet_path) as Texture2D
	var image: Image = null
	if texture == null or include_image:
		image = Image.new()
		var image_error := image.load(ProjectSettings.globalize_path(sheet_path))
		if image_error != OK:
			push_error("Cannot load sprite sheet image: %s (error %d)" % [sheet_path, image_error])
			return {}
		if texture == null:
			texture = ImageTexture.create_from_image(image)
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open sprite sheet JSON: %s" % json_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Failed to parse sprite sheet JSON: %s" % json_path)
		return {}
	var data := parsed as Dictionary
	var frames_data: Dictionary = data.get("frames", {})
	var frame_names := PackedStringArray(frames_data.keys())
	frame_names.sort()
	return {
		"texture": texture,
		"image": image,
		"frames": frames_data,
		"frame_names": frame_names,
		"meta": Dictionary(data.get("meta", {})),
	}


static func append_animation(
	result: SpriteFrames,
	action: StringName,
	sheet_path: String,
	json_path: String,
	fps: float,
	looping: bool
) -> int:
	var atlas := load_atlas(sheet_path, json_path)
	if atlas.is_empty():
		return 0
	if result.has_animation(action):
		result.remove_animation(action)
	result.add_animation(action)
	result.set_animation_speed(action, fps)
	result.set_animation_loop(action, looping)
	var texture: Texture2D = atlas["texture"]
	var frames_data: Dictionary = atlas["frames"]
	var meta: Dictionary = atlas["meta"]
	for frame_name: String in atlas["frame_names"]:
		result.add_frame(action, make_frame_texture(texture, frames_data[frame_name], meta))
	return frames_data.size()


static func make_frame_texture(texture: Texture2D, frame_info: Dictionary, meta: Dictionary) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = texture
	if bool(meta.get("trimmed", false)) and frame_info.has("ox"):
		var original_size: Dictionary = meta.get("originalFrameSize", {})
		var content_width := float(frame_info.get("cw", frame_info.get("w", 64)))
		var content_height := float(frame_info.get("ch", frame_info.get("h", 64)))
		var original_width := float(original_size.get("w", content_width))
		var original_height := float(original_size.get("h", content_height))
		frame.region = Rect2(
			float(frame_info.get("x", 0)) + 1.0,
			float(frame_info.get("y", 0)) + 1.0,
			content_width,
			content_height
		)
		frame.margin = Rect2(
			-float(frame_info.get("ox", 0)),
			-float(frame_info.get("oy", 0)),
			original_width - content_width,
			original_height - content_height
		)
	else:
		frame.region = Rect2(
			float(frame_info.get("x", 0)),
			float(frame_info.get("y", 0)),
			float(frame_info.get("w", 64)),
			float(frame_info.get("h", 64))
		)
	return frame


static func build_visible_bounds(sheet_path: String, json_path: String, alpha_threshold := 0.05) -> Array[Rect2]:
	var atlas := load_atlas(sheet_path, json_path, true)
	var result: Array[Rect2] = []
	if atlas.is_empty():
		return result
	var image: Image = atlas["image"]
	var frames_data: Dictionary = atlas["frames"]
	var meta: Dictionary = atlas["meta"]
	for frame_name: String in atlas["frame_names"]:
		var frame_info: Dictionary = frames_data[frame_name]
		result.append(_visible_bounds_for_frame(image, frame_info, meta, alpha_threshold))
	return result


static func _visible_bounds_for_frame(
	image: Image, frame_info: Dictionary, meta: Dictionary, alpha_threshold: float
) -> Rect2:
	var trimmed := bool(meta.get("trimmed", false)) and frame_info.has("ox")
	var region := Rect2i(
		int(frame_info.get("x", 0)) + (1 if trimmed else 0),
		int(frame_info.get("y", 0)) + (1 if trimmed else 0),
		int(frame_info.get("cw", frame_info.get("w", 64))) if trimmed else int(frame_info.get("w", 64)),
		int(frame_info.get("ch", frame_info.get("h", 64))) if trimmed else int(frame_info.get("h", 64))
	)
	var frame_image := image.get_region(region)
	var used := _get_used_rect(frame_image, alpha_threshold)
	var original_size := Vector2(region.size)
	var source_origin := Vector2.ZERO
	if trimmed:
		var original: Dictionary = meta.get("originalFrameSize", {})
		original_size = Vector2(
			float(original.get("w", region.size.x)),
			float(original.get("h", region.size.y))
		)
		source_origin = Vector2(float(frame_info.get("ox", 0)), float(frame_info.get("oy", 0)))
	if used.size == Vector2i.ZERO:
		return Rect2()
	return Rect2(source_origin + Vector2(used.position) - original_size * 0.5, Vector2(used.size))


static func _get_used_rect(image: Image, alpha_threshold: float) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= alpha_threshold:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
