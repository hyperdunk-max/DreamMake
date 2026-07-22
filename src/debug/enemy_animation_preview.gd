class_name EnemyAnimationPreview
extends Node2D

const PREVIEW_WINDOW_SIZE := Vector2i(1024, 680)
const PANEL_WIDTH := 300.0
const ACTION_ORDER := [
	&"idle", &"move", &"fly", &"attack1", &"attack2", &"attack3",
	&"attack4", &"egg", &"reburn", &"hurt", &"death",
]

@export var definition: EnemyDefinition

@onready var preview_world: Node2D = $PreviewWorld
@onready var sprite: AnimatedSprite2D = $PreviewWorld/AnimatedSprite2D
@onready var action_option: OptionButton = $UI/Panel/Margin/VBox/ActionOption
@onready var replay_button: Button = $UI/Panel/Margin/VBox/Buttons/ReplayButton
@onready var pause_button: Button = $UI/Panel/Margin/VBox/Buttons/PauseButton
@onready var facing_button: Button = $UI/Panel/Margin/VBox/Buttons/FacingButton
@onready var auto_next_check: CheckBox = $UI/Panel/Margin/VBox/AutoNextCheck
@onready var zoom_spin: SpinBox = $UI/Panel/Margin/VBox/ZoomRow/ZoomSpin
@onready var x_spin: SpinBox = $UI/Panel/Margin/VBox/Coordinates/XSpin
@onready var y_spin: SpinBox = $UI/Panel/Margin/VBox/Coordinates/YSpin
@onready var frame_label: Label = $UI/Panel/Margin/VBox/FrameLabel
@onready var offset_label: Label = $UI/Panel/Margin/VBox/OffsetLabel
@onready var source_label: Label = $UI/Panel/Margin/VBox/SourceLabel
@onready var event_label: Label = $UI/Panel/Margin/VBox/EventLabel
@onready var status_label: Label = $UI/Panel/Margin/VBox/StatusLabel

var _profile: EnemyAnimationProfile
var _current_action: StringName = &"attack1"
var _paused := false
var _saved_offset := Vector2.ZERO
var _preview_offset := Vector2.ZERO
var _dragging := false
var _updating_controls := false


func _ready() -> void:
	if get_viewport() is Window:
		get_window().content_scale_size = PREVIEW_WINDOW_SIZE
		get_window().size = PREVIEW_WINDOW_SIZE
	get_viewport().size_changed.connect(_update_layout)
	action_option.item_selected.connect(_on_action_selected)
	replay_button.pressed.connect(_replay)
	pause_button.pressed.connect(_toggle_pause)
	facing_button.pressed.connect(_toggle_facing)
	zoom_spin.value_changed.connect(_on_zoom_changed)
	x_spin.value_changed.connect(_on_coordinate_changed)
	y_spin.value_changed.connect(_on_coordinate_changed)
	$UI/Panel/Margin/VBox/EditButtons/ResetButton.pressed.connect(_reset_offset)
	$UI/Panel/Margin/VBox/EditButtons/SaveButton.pressed.connect(_save_offset)
	sprite.animation_finished.connect(_on_animation_finished)
	if definition == null or definition.animation_profile == null:
		status_label.text = "缺少敌人动画配置"
		return
	_profile = definition.animation_profile
	var errors := definition.validate()
	if not errors.is_empty():
		status_label.text = "配置错误：\n" + "\n".join(errors)
		return
	sprite.sprite_frames = _profile.build_sprite_frames()
	for action: StringName in ACTION_ORDER:
		if not _profile.actions.has(action):
			continue
		action_option.add_item(_profile.get_display_name(action))
		action_option.set_item_metadata(action_option.item_count - 1, action)
		if action == _current_action:
			action_option.select(action_option.item_count - 1)
	_update_layout()
	_on_zoom_changed(zoom_spin.value)
	play_action(_current_action)
	status_label.text = "已加载 %d 个动作；当前默认播放攻击1" % action_option.item_count
	if "--capture-preview" in OS.get_cmdline_user_args():
		_capture_preview.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.x > PANEL_WIDTH:
			_dragging = true
			_update_offset_from_mouse(event.position)
		elif not event.pressed:
			_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_update_offset_from_mouse(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var step := 10.0 if event.shift_pressed else 1.0
		var movement := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: movement.x = -step
			KEY_RIGHT: movement.x = step
			KEY_UP: movement.y = -step
			KEY_DOWN: movement.y = step
		if movement != Vector2.ZERO:
			set_preview_offset(_preview_offset + movement)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _profile == null:
		return
	var spec := _profile.get_spec(_current_action)
	frame_label.text = "当前帧：%d / %d" % [sprite.frame + 1, int(spec.get("frame_count", 0))]
	var manual_events := _profile.get_event_frames(_current_action)
	var source_events := _profile.get_source_events_at_frame(_current_action, sprite.frame)
	var is_manual_event_frame := sprite.frame in manual_events
	var is_source_event_frame := not source_events.is_empty()
	var is_hitbox_active := _profile.is_source_hitbox_active(_current_action, sprite.frame)
	var source_event_names := PackedStringArray()
	for source_event: Dictionary in source_events:
		source_event_names.append(str(source_event.get("id", "unknown")))
	event_label.text = "源码事件：%s" % (", ".join(source_event_names) if is_source_event_frame else "无")
	event_label.text += "\n人工事件：%s　%s" % [
		"是" if is_manual_event_frame else "否", str(spec.get("event_note", "")),
	]
	event_label.text += "\n源码 stick：%s　%s" % [
		"生效" if is_hitbox_active else "关闭", str(spec.get("hitbox_note", ""))
	]
	event_label.modulate = (
		Color("ffbd4a")
		if is_source_event_frame or is_manual_event_frame or is_hitbox_active
		else Color("aab4c8")
	)
	queue_redraw()


func play_action(action: StringName) -> void:
	if _profile == null or not _profile.actions.has(action):
		return
	_current_action = action
	var spec := _profile.get_spec(action)
	_saved_offset = _profile.get_offset(action)
	set_preview_offset(_saved_offset, false)
	sprite.play(action)
	sprite.pause() if _paused else sprite.play()
	offset_label.text = "当前坐标：%s" % sprite.position
	source_label.text = "SWF symbol %d　画布 %s\n保存字段：sprite_offset" % [
		int(spec.get("source_symbol_id", 0)), Vector2(spec.get("source_canvas", Vector2.ZERO))
	]


func _on_action_selected(index: int) -> void:
	play_action(StringName(action_option.get_item_metadata(index)))


func _replay() -> void:
	sprite.play(_current_action)
	if _paused:
		sprite.pause()


func _toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		sprite.pause()
		pause_button.text = "继续"
	else:
		sprite.play()
		pause_button.text = "暂停"


func _toggle_facing() -> void:
	sprite.flip_h = not sprite.flip_h
	facing_button.text = "朝向：左" if sprite.flip_h else "朝向：右"


func _on_zoom_changed(value: float) -> void:
	preview_world.scale = Vector2.ONE * value
	queue_redraw()


func set_preview_offset(value: Vector2, mark_dirty := true) -> void:
	_preview_offset = Vector2(roundf(value.x), roundf(value.y))
	sprite.position = _preview_offset
	_updating_controls = true
	x_spin.value = _preview_offset.x
	y_spin.value = _preview_offset.y
	_updating_controls = false
	offset_label.text = "当前坐标：Vector2(%d, %d)" % [int(_preview_offset.x), int(_preview_offset.y)]
	if mark_dirty:
		status_label.text = "预览坐标已修改，尚未写入当前敌人动作"
	queue_redraw()


func get_preview_offset() -> Vector2:
	return _preview_offset


func _on_coordinate_changed(_value: float) -> void:
	if _updating_controls:
		return
	set_preview_offset(Vector2(x_spin.value, y_spin.value))


func _update_offset_from_mouse(mouse_position: Vector2) -> void:
	set_preview_offset(preview_world.to_local(mouse_position))


func _reset_offset() -> void:
	set_preview_offset(_saved_offset, false)
	status_label.text = "已恢复当前动作最近一次保存坐标"


func _save_offset() -> void:
	if _profile == null or _profile.resource_path.is_empty():
		status_label.text = "保存失败：敌人动画配置没有资源路径"
		return
	var spec := _profile.get_spec(_current_action).duplicate(true)
	spec["sprite_offset"] = _preview_offset
	_profile.actions[_current_action] = spec
	var error := ResourceSaver.save(_profile, _profile.resource_path)
	if error != OK:
		status_label.text = "保存失败，错误码：%d" % error
		return
	_saved_offset = _preview_offset
	status_label.text = "已保存到动作 %s：Vector2(%d, %d)" % [
		str(_current_action), int(_preview_offset.x), int(_preview_offset.y),
	]


func _on_animation_finished() -> void:
	if not auto_next_check.button_pressed:
		return
	var next := _profile.get_next_animation(_current_action)
	play_action(next)
	for index in action_option.item_count:
		if StringName(action_option.get_item_metadata(index)) == next:
			action_option.select(index)
			break


func _update_layout() -> void:
	var size := get_viewport_rect().size
	preview_world.position = Vector2(PANEL_WIDTH + (size.x - PANEL_WIDTH) * 0.5, size.y - 105.0)
	queue_redraw()


func _capture_preview() -> void:
	await get_tree().create_timer(0.36).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://.tools/peng_demon_king_preview.png")
	if error != OK:
		push_error("Failed to save Peng Demon King preview: %s" % error_string(error))
	get_tree().quit(error)


func _draw() -> void:
	var size := get_viewport_rect().size
	for x in range(int(PANEL_WIDTH), int(size.x), 50):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.13, 0.17, 0.24), 1.0)
	for y in range(0, int(size.y), 50):
		draw_line(Vector2(PANEL_WIDTH, y), Vector2(size.x, y), Color(0.13, 0.17, 0.24), 1.0)
	var origin := preview_world.position
	draw_line(Vector2(PANEL_WIDTH, origin.y), Vector2(size.x, origin.y), Color(0.4, 0.65, 0.9), 2.0)
	draw_line(origin + Vector2(-12, 0), origin + Vector2(12, 0), Color.WHITE, 2.0)
	draw_line(origin + Vector2(0, -12), origin + Vector2(0, 12), Color.WHITE, 2.0)
	if sprite != null:
		var visual_origin := preview_world.to_global(sprite.position)
		draw_line(origin, visual_origin, Color(0.3, 0.85, 1.0, 0.8), 2.0)
		draw_circle(visual_origin, 5.0, Color(0.3, 0.85, 1.0))
	if definition != null:
		var collision_rect := Rect2(
			origin + Vector2(-definition.collision_size.x * 0.5, -definition.collision_size.y),
			definition.collision_size
		)
		draw_rect(collision_rect, Color(0.35, 0.9, 0.45, 0.45), false, 2.0)
	if _profile != null and (
		not _profile.get_source_events_at_frame(_current_action, sprite.frame).is_empty()
		or sprite.frame in _profile.get_event_frames(_current_action)
	):
		draw_circle(origin + Vector2(0, -145), 9.0, Color("ff9d32"))
		draw_string(ThemeDB.fallback_font, origin + Vector2(16, -140), "SOURCE EVENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ffbd4a"))
	if _profile != null and _profile.is_source_hitbox_active(_current_action, sprite.frame):
		draw_string(ThemeDB.fallback_font, origin + Vector2(16, -116), "STICK ACTIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ff6f59"))
