extends SceneTree

# Produces the same selected-asset shape used by zmxiyou3: one atlas and a
# separately inspectable PNG for every source frame.  The Flash exports remain
# in .tools; this script only writes the derived development candidate library.

const SOURCE_ROOT := "res://.tools/zmx1_runtime_probe"
const OUTPUT_ROOT := "res://assets/selected/zmxiyou1/wukong"
const FRAME_SIZE := Vector2i(200, 200)
const GRID_COLUMNS := 6
const PADDING := 8
const ACTIONS: Array[Dictionary] = [
	{"name": "idle", "sprite_id": 529, "loop": true},
	{"name": "walk", "sprite_id": 440, "loop": true},
	{"name": "run", "sprite_id": 452, "loop": true},
	{"name": "hit1", "sprite_id": 211, "loop": false},
	{"name": "jump_up", "sprite_id": 533, "loop": false},
	{"name": "jump_double", "sprite_id": 539, "loop": false},
	{"name": "jump_fall", "sprite_id": 543, "loop": false},
	{"name": "hurt", "sprite_id": 553, "loop": false},
]

var _variants: Array[Dictionary] = []
var _layout: Array[Dictionary] = []
var _global_bounds := Rect2i()
var _shared_scale := 1.0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	for showid in range(1, 7):
		_variants.append({"kind": "body", "showid": showid, "export": "export_body_full_%d" % showid, "svg": "svg_body_full_%d" % showid})
	for showid in range(1, 9):
		_variants.append({"kind": "weapon", "showid": showid, "export": "export_weapon_full_%d" % showid, "svg": "svg_weapon_full_%d" % showid})

	if not _prepare_layout_and_bounds():
		quit(1)
		return
	var available := FRAME_SIZE - Vector2i(PADDING * 2, PADDING * 2)
	_shared_scale = minf(float(available.x) / float(_global_bounds.size.x), float(available.y) / float(_global_bounds.size.y))
	for variant in _variants:
		if not _build_variant(variant):
			quit(1)
			return
	print("ZMX1_WUKONG_CANDIDATES variants=%d frames=159 atlas=%s scale=%.5f bounds=%s" % [_variants.size(), _atlas_size(), _shared_scale, _global_bounds])
	quit(0)


func _prepare_layout_and_bounds() -> bool:
	var expected_total := 0
	var atlas_row := 0
	for action in ACTIONS:
		var sprite_id := int(action["sprite_id"])
		var count := _frame_count(_variants[0], sprite_id)
		if count <= 0:
			push_error("No frames for action %s." % action["name"])
			return false
		for variant in _variants:
			if _frame_count(variant, sprite_id) != count:
				push_error("Frame count mismatch: %s showid %d action %s." % [variant["kind"], variant["showid"], action["name"]])
				return false
		_layout.append({"action": action, "row": atlas_row, "frame_count": count})
		atlas_row += ceili(float(count) / float(GRID_COLUMNS))
		expected_total += count
	if expected_total != 159:
		push_error("Expected 159 selected action frames, got %d." % expected_total)
		return false

	for layout in _layout:
		var sprite_id := int(layout["action"]["sprite_id"])
		for frame in range(1, int(layout["frame_count"]) + 1):
			for variant in _variants:
				var image := _load_image(variant, sprite_id, frame)
				var used := image.get_used_rect()
				if used.size == Vector2i.ZERO:
					push_error("Blank source frame: %s showid %d / %s / %d." % [variant["kind"], variant["showid"], layout["action"]["name"], frame])
					return false
				var placed := Rect2i(_load_flash_origin(variant, sprite_id, frame) + used.position, used.size)
				_global_bounds = placed if _global_bounds.size == Vector2i.ZERO else _global_bounds.merge(placed)
	return _global_bounds.size != Vector2i.ZERO


func _build_variant(variant: Dictionary) -> bool:
	var atlas := _transparent_image(_atlas_size())
	for layout in _layout:
		var action: Dictionary = layout["action"]
		for frame_offset in range(int(layout["frame_count"])):
			var image := _load_image(variant, int(action["sprite_id"]), frame_offset + 1)
			var used := image.get_used_rect()
			var frame_image := _transparent_image(FRAME_SIZE)
			_blit_to_cell(frame_image, image, used, _load_flash_origin(variant, int(action["sprite_id"]), frame_offset + 1))
			var atlas_position := Vector2i(
				(frame_offset % GRID_COLUMNS) * FRAME_SIZE.x,
				(int(layout["row"]) + frame_offset / GRID_COLUMNS) * FRAME_SIZE.y
			)
			atlas.blit_rect(frame_image, Rect2i(Vector2i.ZERO, FRAME_SIZE), atlas_position)
			var frame_path := _variant_root(variant) + "/frames/%s/frame_%02d.png" % [action["name"], frame_offset]
			if not _save(frame_image, frame_path):
				return false
	if not _save(atlas, _variant_root(variant) + "/source_atlas.png"):
		return false
	return _write_variant_manifest(variant)


func _blit_to_cell(destination: Image, source: Image, used: Rect2i, origin: Vector2i) -> void:
	var source_rect := Rect2i(origin + used.position, used.size)
	var target_position := Vector2i(
		PADDING + roundi(float(source_rect.position.x - _global_bounds.position.x) * _shared_scale),
		PADDING + roundi(float(source_rect.position.y - _global_bounds.position.y) * _shared_scale)
	)
	var target_size := Vector2i(
		maxi(1, roundi(float(used.size.x) * _shared_scale)),
		maxi(1, roundi(float(used.size.y) * _shared_scale))
	)
	var cropped := source.get_region(used)
	if cropped.get_size() != target_size:
		cropped.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	destination.blit_rect(cropped, Rect2i(Vector2i.ZERO, target_size), target_position)


func _atlas_size() -> Vector2i:
	var rows := int(_layout.back()["row"]) + ceili(float(int(_layout.back()["frame_count"])) / float(GRID_COLUMNS))
	return Vector2i(FRAME_SIZE.x * GRID_COLUMNS, FRAME_SIZE.y * rows)


func _frame_count(variant: Dictionary, sprite_id: int) -> int:
	var directory := _sprite_directory(variant, sprite_id, "png")
	var count := 0
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension().to_lower() == "png" and file_name.get_basename().is_valid_int():
			count = maxi(count, int(file_name.get_basename()))
	return count


func _load_image(variant: Dictionary, sprite_id: int, frame: int) -> Image:
	var path := _sprite_directory(variant, sprite_id, "png") + "/%d.png" % frame
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Cannot load %s." % path)
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	return image


func _load_flash_origin(variant: Dictionary, sprite_id: int, frame: int) -> Vector2i:
	var path := _sprite_directory(variant, sprite_id, "svg") + "/%d.svg" % frame
	var content := FileAccess.get_file_as_string(path)
	var expression := RegEx.new()
	expression.compile('<g transform="matrix\\([^,]+, [^,]+, [^,]+, [^,]+, ([^,]+), ([^)]+)\\)">')
	var match := expression.search(content)
	if match == null:
		push_error("Cannot parse Flash matrix in %s." % path)
		return Vector2i.ZERO
	return Vector2i(roundi(float(match.get_string(1))), roundi(float(match.get_string(2))))


func _sprite_directory(variant: Dictionary, sprite_id: int, extension: String) -> String:
	var root := SOURCE_ROOT + "/" + str(variant["export"] if extension == "png" else variant["svg"])
	for directory in DirAccess.get_directories_at(root):
		if directory.begins_with("DefineSprite_%d" % sprite_id):
			return root + "/" + directory
	push_error("Missing sprite %d in %s." % [sprite_id, root])
	return root


func _variant_root(variant: Dictionary) -> String:
	return OUTPUT_ROOT + "/%s_candidates/showid_%d" % [variant["kind"], variant["showid"]]


func _transparent_image(size: Vector2i) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _save(image: Image, path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Cannot create %s." % absolute.get_base_dir())
		return false
	return image.save_png(path) == OK


func _write_variant_manifest(variant: Dictionary) -> bool:
	var actions: Array[Dictionary] = []
	for layout in _layout:
		actions.append({
			"name": layout["action"]["name"], "source_symbol": layout["action"]["sprite_id"],
			"row": layout["row"], "column": 0, "frame_count": layout["frame_count"], "loop": layout["action"]["loop"],
		})
	var selector := {"armor_selectors": {"143": "showid", "152": "showid", "160": "showid", "186": "showid"}} if variant["kind"] == "body" else {"weapon_selector": {"177": "showid"}, "jump_double_direct_child": 538}
	var manifest := {
		"game": "zmxiyou1", "role": "wukong", "kind": variant["kind"], "showid": variant["showid"],
		"source_swf": "sources/decoded/zmxiyou1/Role_v7.swf", "source_xml": ".tools/zmxiyou1_xml/Role_v7.xml",
		"derived_export": ".tools/zmx1_runtime_probe/%s" % variant["export"], "selectors": selector,
		"frame_size": [FRAME_SIZE.x, FRAME_SIZE.y], "atlas_columns": GRID_COLUMNS,
		"atlas_size": [_atlas_size().x, _atlas_size().y], "shared_scale": _shared_scale,
		"flash_global_bounds": [_global_bounds.position.x, _global_bounds.position.y, _global_bounds.size.x, _global_bounds.size.y],
		"actions": actions,
	}
	var file := FileAccess.open(_variant_root(variant) + "/manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write manifest for %s showid %d." % [variant["kind"], variant["showid"]])
		return false
	file.store_string(JSON.stringify(manifest, "  "))
	return true
