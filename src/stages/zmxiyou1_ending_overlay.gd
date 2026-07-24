class_name Zmxiyou1EndingOverlay
extends CanvasLayer

## Source-faithful Ending renderer for OtherMat_v9 symbols 702 -> 701.
## The pixels stay in four sprite packs while this node replays the original
## 24 Hz display-list positions inside the original Flash mask.

signal finished

const TIMELINE_PATH := "res://assets/selected/zmxiyou1/ui/ending/timeline.json"

var _timeline: Dictionary = {}
var _root: Control
var _canvas: Control
var _clip: Control
var _track_views: Dictionary = {}
var _source_frame := 1
var _frame_accumulator := 0.0
var _has_finished := false


func _ready() -> void:
	layer = 200
	if not _load_timeline():
		call_deferred(&"_finish")
		return
	_build_visuals()
	_layout_canvas()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_layout_canvas):
		viewport.size_changed.connect(_layout_canvas)
	_apply_source_frame()


func _process(delta: float) -> void:
	if _has_finished or _timeline.is_empty():
		return
	var source_fps := float(_timeline.get("source_fps", 24.0))
	_frame_accumulator += maxf(0.0, delta) * source_fps
	var pending_frames := int(_frame_accumulator)
	if pending_frames <= 0:
		return
	_frame_accumulator -= pending_frames
	for _step in pending_frames:
		_source_frame += 1
		if _source_frame >= int(_timeline.get("destroy_frame", 1204)):
			_finish()
			return
	_apply_source_frame()


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_layout_canvas):
		viewport.size_changed.disconnect(_layout_canvas)


func _load_timeline() -> bool:
	var file := FileAccess.open(TIMELINE_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open ZMX1 Ending timeline: %s" % TIMELINE_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Cannot parse ZMX1 Ending timeline: %s" % TIMELINE_PATH)
		return false
	_timeline = parsed as Dictionary
	return (
		int(_timeline.get("source_frame_count", 0)) == 1205
		and int(_timeline.get("destroy_frame", 0)) == 1204
		and not Array(_timeline.get("tracks", [])).is_empty()
	)


func _build_visuals() -> void:
	_root = Control.new()
	_root.name = "EndingViewport"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var letterbox := ColorRect.new()
	letterbox.name = "Letterbox"
	letterbox.color = Color.BLACK
	letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(letterbox)

	var canvas_size_data: Dictionary = _timeline.get("canvas_size", {})
	var canvas_size := Vector2(
		float(canvas_size_data.get("w", 940.0)),
		float(canvas_size_data.get("h", 590.0))
	)
	_canvas = Control.new()
	_canvas.name = "SourceCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.size = canvas_size
	_root.add_child(_canvas)

	var background_data: Dictionary = _timeline.get("background", {})
	var background := _new_texture_view(background_data)
	background.name = "Background"
	background.position = Vector2.ZERO
	background.size = canvas_size
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas.add_child(background)

	var clip_data: Dictionary = _timeline.get("clip_rect_in_canvas_px", {})
	_clip = Control.new()
	_clip.name = "CreditsClip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	_clip.position = Vector2(float(clip_data.get("x", 0.0)), float(clip_data.get("y", 0.0)))
	_clip.size = Vector2(float(clip_data.get("w", 0.0)), float(clip_data.get("h", 0.0)))
	_canvas.add_child(_clip)

	for track_variant: Variant in Array(_timeline.get("tracks", [])):
		var track := Dictionary(track_variant)
		var view := _new_texture_view(track)
		var track_name := StringName(track.get("name", "track"))
		view.name = str(track_name).to_pascal_case()
		view.size = view.texture.get_size() if view.texture != null else Vector2.ZERO
		_clip.add_child(view)
		_track_views[track_name] = {"view": view, "track": track}


func _new_texture_view(asset: Dictionary) -> TextureRect:
	var view := TextureRect.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var atlas := SpriteSheetAtlas.load_atlas(
		str(asset.get("sheet_path", "")),
		str(asset.get("json_path", ""))
	)
	if atlas.is_empty():
		return view
	var frame_names: PackedStringArray = atlas["frame_names"]
	if frame_names.is_empty():
		return view
	var frames: Dictionary = atlas["frames"]
	view.texture = SpriteSheetAtlas.make_frame_texture(
		atlas["texture"] as Texture2D,
		frames[frame_names[0]],
		atlas["meta"]
	)
	return view


func _layout_canvas() -> void:
	if _canvas == null or get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var fit_scale := minf(viewport_size.x / _canvas.size.x, viewport_size.y / _canvas.size.y)
	_canvas.scale = Vector2.ONE * fit_scale
	_canvas.position = (viewport_size - _canvas.size * fit_scale) * 0.5


func _apply_source_frame() -> void:
	var mask_data: Dictionary = _timeline.get("mask_rect_in_symbol_px", {})
	var mask_origin := Vector2(float(mask_data.get("x", 0.0)), float(mask_data.get("y", 0.0)))
	for track_name: StringName in _track_views:
		var state: Dictionary = _track_views[track_name]
		var track: Dictionary = state["track"]
		var view := state["view"] as TextureRect
		var first_frame := int(track.get("first_frame", 1))
		var last_frame := int(track.get("last_frame", 0))
		view.visible = _source_frame >= first_frame and _source_frame <= last_frame
		if not view.visible:
			continue
		var sample_index := _source_frame - first_frame
		var y_samples: Array = track.get("registration_y_twips", [])
		if sample_index < 0 or sample_index >= y_samples.size():
			view.visible = false
			continue
		var bounds: Dictionary = track.get("shape_bounds_px", {})
		var registration := Vector2(
			float(track.get("registration_x_twips", 0)) / 20.0,
			float(y_samples[sample_index]) / 20.0
		)
		view.position = registration + Vector2(
			float(bounds.get("x", 0.0)),
			float(bounds.get("y", 0.0))
		) - mask_origin


func _finish() -> void:
	if _has_finished:
		return
	_has_finished = true
	set_process(false)
	visible = false
	finished.emit()
	queue_free()


func seek_source_frame(frame_number: int) -> void:
	if _has_finished or _timeline.is_empty():
		return
	_source_frame = clampi(frame_number, 1, int(_timeline.get("source_frame_count", 1205)))
	_frame_accumulator = 0.0
	if _source_frame >= int(_timeline.get("destroy_frame", 1204)):
		_finish()
		return
	_apply_source_frame()


func finish_immediately() -> void:
	_finish()


func get_source_frame() -> int:
	return _source_frame


func get_source_duration_seconds() -> float:
	return float(_timeline.get("duration_seconds", 0.0))


func get_clip_rect() -> Rect2:
	return Rect2(_clip.position, _clip.size) if _clip != null else Rect2()


func get_track_state(track_name: StringName) -> Dictionary:
	if not _track_views.has(track_name):
		return {}
	var state: Dictionary = _track_views[track_name]
	var view := state["view"] as TextureRect
	return {"visible": view.visible, "position": view.position, "size": view.size}
