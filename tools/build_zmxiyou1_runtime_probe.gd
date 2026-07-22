extends SceneTree

const FRAME_SIZE := Vector2i(200, 200)
const PADDING := 8
const SOURCE_ROOT := "res://.tools/zmx1_runtime_probe"
const OUTPUT_ROOT := "res://assets/selected/zmxiyou1/wukong/runtime_probe"
const ACTIONS := [
	{"name": "idle", "sprite_id": 529, "loop": true},
	{"name": "walk", "sprite_id": 440, "loop": true},
	{"name": "run", "sprite_id": 452, "loop": true},
	{"name": "hit1", "sprite_id": 211, "loop": false},
	{"name": "jump_up", "sprite_id": 533, "loop": false},
	{"name": "jump_double", "sprite_id": 539, "loop": false},
	{"name": "jump_fall", "sprite_id": 543, "loop": false},
	{"name": "hurt", "sprite_id": 553, "loop": false},
]
const SOURCES := {
	"body_1": {"export": "export_body_only_full", "svg": "svg_body_only_full"},
	"body_2": {"export": "export_body_only_2_full", "svg": "svg_body_only_2_full"},
	"weapon_1": {"export": "export_weapon_full_1", "svg": "svg_weapon_full_1"},
	"weapon_2": {"export": "export_weapon_full_2", "svg": "svg_weapon_full_2"},
}


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var action_sets: Array[Dictionary] = []
	var largest := Vector2i.ONE
	var total_frames := 0
	for action: Dictionary in ACTIONS:
		var sprite_id := int(action["sprite_id"])
		var frame_count := _source_frame_count(&"body_1", sprite_id)
		var expected_counts := {
			&"body_2": _source_frame_count(&"body_2", sprite_id),
			&"weapon_1": _source_frame_count(&"weapon_1", sprite_id),
			&"weapon_2": _source_frame_count(&"weapon_2", sprite_id),
		}
		for variant: StringName in expected_counts:
			if int(expected_counts[variant]) != frame_count:
				push_error(
					"Frame count mismatch for %s: body_1=%d %s=%d" %
					[action["name"], frame_count, variant, expected_counts[variant]]
				)
				quit(1)
				return
		var frames: Array[Dictionary] = []
		for frame_index in range(frame_count):
			var body_1 := _load_source(&"body_1", sprite_id, frame_index + 1)
			var body_2 := _load_source(&"body_2", sprite_id, frame_index + 1)
			var weapon_1 := _load_source(&"weapon_1", sprite_id, frame_index + 1)
			var weapon_2 := _load_source(&"weapon_2", sprite_id, frame_index + 1)
			var aligned := _align_sources(
				body_1,
				body_2,
				weapon_1,
				weapon_2,
				_load_flash_origin(&"body_1", sprite_id, frame_index + 1),
				_load_flash_origin(&"body_2", sprite_id, frame_index + 1),
				_load_flash_origin(&"weapon_1", sprite_id, frame_index + 1),
				_load_flash_origin(&"weapon_2", sprite_id, frame_index + 1)
			)
			var used := _combined_used_rect([
				aligned["body_1"], aligned["body_2"],
				aligned["weapon_1"], aligned["weapon_2"],
			])
			largest.x = maxi(largest.x, used.size.x)
			largest.y = maxi(largest.y, used.size.y)
			frames.append({
				"body_1": aligned["body_1"],
				"body_2": aligned["body_2"],
				"weapon_1": aligned["weapon_1"],
				"weapon_2": aligned["weapon_2"],
				"used": used,
			})
		action_sets.append({"action": action, "frames": frames})
		total_frames += frame_count

	var available := FRAME_SIZE - Vector2i(PADDING * 2, PADDING * 2)
	var shared_scale := minf(
		float(available.x) / float(largest.x),
		float(available.y) / float(largest.y)
	)
	var atlas_size := Vector2i(FRAME_SIZE.x, FRAME_SIZE.y * total_frames)
	var body_1_atlas := _transparent_image(atlas_size)
	var body_2_atlas := _transparent_image(atlas_size)
	var weapon_1_atlas := _transparent_image(atlas_size)
	var weapon_2_atlas := _transparent_image(atlas_size)
	var action_manifest: Array[Dictionary] = []
	var row := 0
	for action_set: Dictionary in action_sets:
		var action: Dictionary = action_set["action"]
		var frames: Array = action_set["frames"]
		var start_row := row
		for source: Dictionary in frames:
			var used: Rect2i = source["used"]
			var target_size := Vector2i(
				maxi(1, roundi(float(used.size.x) * shared_scale)),
				maxi(1, roundi(float(used.size.y) * shared_scale))
			)
			var target_position := Vector2i(
				(FRAME_SIZE.x - target_size.x) / 2,
				row * FRAME_SIZE.y + FRAME_SIZE.y - PADDING - target_size.y
			)
			_blit_normalized(body_1_atlas, source["body_1"], used, target_size, target_position)
			_blit_normalized(body_2_atlas, source["body_2"], used, target_size, target_position)
			_blit_normalized(weapon_1_atlas, source["weapon_1"], used, target_size, target_position)
			_blit_normalized(weapon_2_atlas, source["weapon_2"], used, target_size, target_position)
			row += 1
		action_manifest.append({
			"name": action["name"],
			"row": start_row,
			"frame_count": frames.size(),
			"loop": action["loop"],
		})

	var paths := {
		"body_1": OUTPUT_ROOT + "/body_candidates/showid_1/source_atlas.png",
		"body_2": OUTPUT_ROOT + "/body_candidates/showid_2/source_atlas.png",
		"weapon_1": OUTPUT_ROOT + "/weapon_candidates/showid_1/source_atlas.png",
		"weapon_2": OUTPUT_ROOT + "/weapon_candidates/showid_2/source_atlas.png",
	}
	if not _save(body_1_atlas, paths["body_1"]) \
		or not _save(body_2_atlas, paths["body_2"]) \
		or not _save(weapon_1_atlas, paths["weapon_1"]) \
		or not _save(weapon_2_atlas, paths["weapon_2"]):
		quit(1)
		return
	_write_manifest(action_manifest, total_frames, shared_scale, largest)
	print("ZMX1_RUNTIME_FULL actions=%d frames=%d shared_scale=%.4f largest=%s" % [
		ACTIONS.size(), total_frames, shared_scale, largest,
	])
	quit(0)


func _source_frame_count(variant: StringName, sprite_id: int) -> int:
	var directory := _sprite_directory(variant, sprite_id, "png")
	if directory.is_empty():
		return 0
	var count := 0
	var files := DirAccess.get_files_at(directory)
	for file_name in files:
		if file_name.get_extension().to_lower() == "png" and file_name.get_basename().is_valid_int():
			count = maxi(count, int(file_name.get_basename()))
	var frame_directories := DirAccess.get_directories_at(directory)
	for frame_directory in frame_directories:
		if frame_directory.is_valid_int():
			count = maxi(count, int(frame_directory))
	return count


func _load_source(variant: StringName, sprite_id: int, frame_index: int) -> Image:
	var path := _frame_path(variant, sprite_id, frame_index, "png")
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Cannot load source frame: %s" % path)
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	return image


func _load_flash_origin(variant: StringName, sprite_id: int, frame_index: int) -> Vector2:
	var path := _frame_path(variant, sprite_id, frame_index, "svg")
	var text := FileAccess.get_file_as_string(path)
	var expression := RegEx.new()
	expression.compile('<g transform="matrix\\([^,]+, [^,]+, [^,]+, [^,]+, ([^,]+), ([^)]+)\\)">')
	var result := expression.search(text)
	if result == null:
		push_error("Cannot parse Flash origin from %s" % path)
		return Vector2.ZERO
	return Vector2(float(result.get_string(1)), float(result.get_string(2)))


func _frame_path(variant: StringName, sprite_id: int, frame_index: int, extension: String) -> String:
	var directory := _sprite_directory(variant, sprite_id, extension)
	var direct := directory + "/%d.%s" % [frame_index, extension]
	if FileAccess.file_exists(direct):
		return direct
	var nested := directory + "/%d/1.%s" % [frame_index, extension]
	if FileAccess.file_exists(nested):
		return nested
	push_error("Cannot find frame %d in %s" % [frame_index, directory])
	return direct


func _sprite_directory(variant: StringName, sprite_id: int, extension: String) -> String:
	var root_key := str(SOURCES[variant]["export"] if extension == "png" else SOURCES[variant]["svg"])
	var root := SOURCE_ROOT + "/" + root_key
	var directory := DirAccess.open(root)
	if directory == null:
		push_error("Cannot open source directory: %s" % root)
		return root
	for entry in directory.get_directories():
		if entry.begins_with("DefineSprite_%d" % sprite_id):
			return root + "/" + entry
	push_error("Cannot find sprite %d in %s" % [sprite_id, root])
	return root


func _align_sources(
	body_1: Image,
	body_2: Image,
	weapon_1: Image,
	weapon_2: Image,
	body_1_origin: Vector2,
	body_2_origin: Vector2,
	weapon_1_origin: Vector2,
	weapon_2_origin: Vector2
) -> Dictionary:
	var body_2_position := Vector2i(roundi(body_1_origin.x - body_2_origin.x), roundi(body_1_origin.y - body_2_origin.y))
	var weapon_1_position := Vector2i(roundi(body_1_origin.x - weapon_1_origin.x), roundi(body_1_origin.y - weapon_1_origin.y))
	var weapon_2_position := Vector2i(roundi(body_1_origin.x - weapon_2_origin.x), roundi(body_1_origin.y - weapon_2_origin.y))
	var minimum := Vector2i(
		mini(0, mini(body_2_position.x, mini(weapon_1_position.x, weapon_2_position.x))),
		mini(0, mini(body_2_position.y, mini(weapon_1_position.y, weapon_2_position.y)))
	)
	var maximum := Vector2i(
		maxi(body_1.get_width(), maxi(body_2_position.x + body_2.get_width(), maxi(weapon_1_position.x + weapon_1.get_width(), weapon_2_position.x + weapon_2.get_width()))),
		maxi(body_1.get_height(), maxi(body_2_position.y + body_2.get_height(), maxi(weapon_1_position.y + weapon_1.get_height(), weapon_2_position.y + weapon_2.get_height())))
	)
	var common_size := maximum - minimum
	var body_1_canvas := _transparent_image(common_size)
	var body_2_canvas := _transparent_image(common_size)
	var weapon_1_canvas := _transparent_image(common_size)
	var weapon_2_canvas := _transparent_image(common_size)
	body_1_canvas.blit_rect(body_1, Rect2i(Vector2i.ZERO, body_1.get_size()), -minimum)
	body_2_canvas.blit_rect(body_2, Rect2i(Vector2i.ZERO, body_2.get_size()), body_2_position - minimum)
	weapon_1_canvas.blit_rect(weapon_1, Rect2i(Vector2i.ZERO, weapon_1.get_size()), weapon_1_position - minimum)
	weapon_2_canvas.blit_rect(weapon_2, Rect2i(Vector2i.ZERO, weapon_2.get_size()), weapon_2_position - minimum)
	return {"body_1": body_1_canvas, "body_2": body_2_canvas, "weapon_1": weapon_1_canvas, "weapon_2": weapon_2_canvas}


func _combined_used_rect(images: Array) -> Rect2i:
	var result := Rect2i()
	for image: Image in images:
		var used := image.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		result = used if result.size == Vector2i.ZERO else result.merge(used)
	return result


func _blit_normalized(destination: Image, source: Image, used: Rect2i, target_size: Vector2i, target_position: Vector2i) -> void:
	var cropped := source.get_region(used)
	if cropped.get_size() != target_size:
		cropped.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	destination.blit_rect(cropped, Rect2i(Vector2i.ZERO, target_size), target_position)


func _transparent_image(size: Vector2i) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _save(image: Image, path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Cannot create output directory for %s: %s" % [path, error_string(error)])
		return false
	error = image.save_png(path)
	return error == OK


func _write_manifest(action_manifest: Array[Dictionary], total_frames: int, shared_scale: float, largest: Vector2i) -> void:
	var manifest := {
		"status": "runtime_full",
		"game": "zmxiyou1",
		"role": "wukong",
		"frame_size": [FRAME_SIZE.x, FRAME_SIZE.y],
		"total_frames": total_frames,
		"shared_scale": shared_scale,
		"largest_source_size": [largest.x, largest.y],
		"body_showids": [1, 2],
		"weapon_showids": [1, 2],
		"actions": action_manifest,
		"armor_selectors_frozen": [143, 152, 160, 186],
		"weapon_selector": 177,
		"source_symbols": ACTIONS,
		"limitation": "All frames exported from the selected Flash action symbols; nested non-player effects remain outside this candidate set.",
	}
	var file := FileAccess.open(OUTPUT_ROOT + "/manifest.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "  "))
