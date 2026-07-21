extends SceneTree

const SOURCE_ROOT := "res://assets/extracted/classified/zmxiyou1"
const CACHE_ROOT := "res://.tools/zmxiyou1_format_audit/svg"
const INDEX_PATH := "res://.tools/zmxiyou1_format_audit/svg_index.tsv"
const CANVAS_SIZE := 64


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var svg_paths: Array[String] = []
	_collect_svg_files(SOURCE_ROOT, svg_paths)
	svg_paths.sort()

	var cache_absolute := ProjectSettings.globalize_path(CACHE_ROOT)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(cache_absolute)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("Cannot create SVG audit cache: %s" % error_string(mkdir_error))
		quit(1)
		return

	var index := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if index == null:
		push_error("Cannot write SVG audit index: %s" % INDEX_PATH)
		quit(1)
		return

	var rendered := 0
	var failed := 0
	for source_path in svg_paths:
		var data := FileAccess.get_file_as_bytes(source_path)
		var image := Image.new()
		var load_error := image.load_svg_from_buffer(data, 1.0)
		if load_error != OK:
			failed += 1
			push_warning("Cannot render SVG %s: %s" % [source_path, error_string(load_error)])
			continue

		var normalized := _normalize_image(image)
		var relative_path := source_path.trim_prefix(SOURCE_ROOT + "/")
		var cache_name := relative_path.sha256_text() + ".png"
		var cache_path := CACHE_ROOT + "/" + cache_name
		var save_error := normalized.save_png(cache_path)
		if save_error != OK:
			failed += 1
			push_warning("Cannot save SVG cache %s: %s" % [cache_path, error_string(save_error)])
			continue

		index.store_line(relative_path + "\t" + cache_name)
		rendered += 1

	index.close()
	print("SVG_RENDER_AUDIT rendered=%d failed=%d" % [rendered, failed])
	quit(0 if failed == 0 else 1)


func _collect_svg_files(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("Cannot open directory: %s" % directory_path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := directory_path + "/" + entry
			if directory.current_is_dir():
				_collect_svg_files(path, output)
			elif entry.get_extension().to_lower() == "svg":
				output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _normalize_image(source: Image) -> Image:
	var canvas := Image.create_empty(CANVAS_SIZE, CANVAS_SIZE, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	var used_rect := source.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return canvas

	var cropped := source.get_region(used_rect)
	cropped.convert(Image.FORMAT_RGBA8)
	var scale_factor: float = min(
		float(CANVAS_SIZE) / float(cropped.get_width()),
		float(CANVAS_SIZE) / float(cropped.get_height())
	)
	var target_width := maxi(1, roundi(float(cropped.get_width()) * scale_factor))
	var target_height := maxi(1, roundi(float(cropped.get_height()) * scale_factor))
	cropped.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	var offset := Vector2i(
		(CANVAS_SIZE - target_width) / 2,
		(CANVAS_SIZE - target_height) / 2
	)
	canvas.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), offset)
	return canvas
