extends SceneTree

const FRAME_SIZE := Vector2i(200, 200)
const PADDING := 8
const SOURCE_ROOT := "res://.tools/zmx1_runtime_probe"
const OUTPUT_ROOT := "res://assets/selected/zmxiyou1/wukong/runtime_probe"
const ACTIONS := [
	{"name": "idle", "sprite_id": 529},
	{"name": "walk", "sprite_id": 440},
	{"name": "run", "sprite_id": 452},
	{"name": "hit1", "sprite_id": 211},
	{"name": "jump_up", "sprite_id": 533},
	{"name": "jump_double", "sprite_id": 539},
	{"name": "jump_fall", "sprite_id": 543},
	{"name": "hurt", "sprite_id": 553},
]


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var source_sets: Array[Dictionary] = []
	var largest := Vector2i.ONE
	for action: Dictionary in ACTIONS:
		var sprite_id := int(action["sprite_id"])
		var body_1 := _load_source(&"body_only", sprite_id)
		var body_2 := _load_source(&"body_only_2", sprite_id)
		var weapon_1 := _load_source(&"weapon_only_1", sprite_id)
		var weapon_2 := _load_source(&"weapon_only_2", sprite_id)
		if body_1 == null or body_2 == null or weapon_1 == null or weapon_2 == null:
			quit(1)
			return
		var aligned := _align_sources(
			body_1,
			body_2,
			weapon_1,
			weapon_2,
			_load_flash_origin(&"body_only", sprite_id),
			_load_flash_origin(&"body_only_2", sprite_id),
			_load_flash_origin(&"weapon_only_1", sprite_id),
			_load_flash_origin(&"weapon_only_2", sprite_id)
		)
		body_1 = aligned["body_1"]
		body_2 = aligned["body_2"]
		weapon_1 = aligned["weapon_1"]
		weapon_2 = aligned["weapon_2"]
		var used := _combined_used_rect([body_1, body_2, weapon_1, weapon_2])
		largest.x = maxi(largest.x, used.size.x)
		largest.y = maxi(largest.y, used.size.y)
		source_sets.append({
			"body_1": body_1,
			"body_2": body_2,
			"weapon_1": weapon_1,
			"weapon_2": weapon_2,
			"used": used,
		})

	var available := FRAME_SIZE - Vector2i(PADDING * 2, PADDING * 2)
	var shared_scale := minf(
		float(available.x) / float(largest.x),
		float(available.y) / float(largest.y)
	)
	var atlas_size := Vector2i(FRAME_SIZE.x, FRAME_SIZE.y * ACTIONS.size())
	var body_1_atlas := _transparent_image(atlas_size)
	var body_2_atlas := _transparent_image(atlas_size)
	var weapon_1_atlas := _transparent_image(atlas_size)
	var weapon_2_atlas := _transparent_image(atlas_size)

	for row in range(source_sets.size()):
		var source: Dictionary = source_sets[row]
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

	var body_1_path := OUTPUT_ROOT + "/body_candidates/showid_1/source_atlas.png"
	var body_2_path := OUTPUT_ROOT + "/body_candidates/showid_2/source_atlas.png"
	var weapon_1_path := OUTPUT_ROOT + "/weapon_candidates/showid_1/source_atlas.png"
	var weapon_2_path := OUTPUT_ROOT + "/weapon_candidates/showid_2/source_atlas.png"
	if not _save(body_1_atlas, body_1_path) \
		or not _save(body_2_atlas, body_2_path) \
		or not _save(weapon_1_atlas, weapon_1_path) \
		or not _save(weapon_2_atlas, weapon_2_path):
		quit(1)
		return

	var preview := _transparent_image(Vector2i(FRAME_SIZE.x * 4, FRAME_SIZE.y * ACTIONS.size()))
	for row in range(ACTIONS.size()):
		var cell_rect := Rect2i(0, row * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y)
		var bodies := [body_1_atlas, body_2_atlas]
		var weapons := [weapon_1_atlas, weapon_2_atlas]
		for body_index in range(bodies.size()):
			for weapon_index in range(weapons.size()):
				var composite: Image = bodies[body_index].get_region(cell_rect)
				composite.blend_rect(weapons[weapon_index], cell_rect, Vector2i.ZERO)
				var column := body_index * weapons.size() + weapon_index
				preview.blit_rect(
					composite,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					Vector2i(column * FRAME_SIZE.x, row * FRAME_SIZE.y)
				)
	_save(preview, OUTPUT_ROOT + "/preview.png")
	print("ZMX1_RUNTIME_PROBE actions=%d shared_scale=%.4f largest=%s" % [ACTIONS.size(), shared_scale, largest])
	quit(0)


func _load_source(variant: StringName, sprite_id: int) -> Image:
	var export_root := SOURCE_ROOT + "/export_" + String(variant)
	var directory := DirAccess.open(export_root)
	if directory == null:
		push_error("Cannot open FFDec export: %s" % export_root)
		return null
	for entry in directory.get_directories():
		if entry.begins_with("DefineSprite_%d" % sprite_id):
			var nested_path := export_root + "/" + entry + "/1/1.png"
			var direct_path := export_root + "/" + entry + "/1.png"
			var path := nested_path if FileAccess.file_exists(nested_path) else direct_path
			var image := Image.load_from_file(path)
			if image == null or image.is_empty():
				push_error("Cannot load source frame: %s" % path)
				return null
			image.convert(Image.FORMAT_RGBA8)
			return image
	push_error("Cannot find sprite %d in %s" % [sprite_id, export_root])
	return null


func _load_flash_origin(variant: StringName, sprite_id: int) -> Vector2:
	var export_root := SOURCE_ROOT + "/svg_" + String(variant)
	var directory := DirAccess.open(export_root)
	if directory == null:
		push_error("Cannot open FFDec SVG export: %s" % export_root)
		return Vector2.ZERO
	for entry in directory.get_directories():
		if not entry.begins_with("DefineSprite_%d" % sprite_id):
			continue
		var path := export_root + "/" + entry + "/1.svg"
		var text := FileAccess.get_file_as_string(path)
		var expression := RegEx.new()
		expression.compile('<g transform="matrix\\([^,]+, [^,]+, [^,]+, [^,]+, ([^,]+), ([^)]+)\\)">')
		var result := expression.search(text)
		if result == null:
			push_error("Cannot parse Flash origin from %s" % path)
			return Vector2.ZERO
		return Vector2(float(result.get_string(1)), float(result.get_string(2)))
	push_error("Cannot find SVG sprite %d in %s" % [sprite_id, export_root])
	return Vector2.ZERO


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
	# SVG's outer transform records the Flash registration point in each
	# independently cropped export.  Align those registration points exactly.
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
	return {
		"body_1": body_1_canvas,
		"body_2": body_2_canvas,
		"weapon_1": weapon_1_canvas,
		"weapon_2": weapon_2_canvas,
	}


func _combined_used_rect(images: Array) -> Rect2i:
	var result := Rect2i()
	for image: Image in images:
		var used := image.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		result = used if result.size == Vector2i.ZERO else result.merge(used)
	return result


func _blit_normalized(
	destination: Image,
	source: Image,
	used: Rect2i,
	target_size: Vector2i,
	target_position: Vector2i
) -> void:
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
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		return false
	return true
