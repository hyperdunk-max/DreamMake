class_name EnemyAnimationPreview
extends Node2D

const PREVIEW_WINDOW_SIZE := Vector2i(1024, 680)
const PANEL_WIDTH := 300.0
const ACTION_ORDER := [
	&"idle", &"move", &"fly", &"attack1", &"attack2", &"attack3",
	&"attack4", &"egg", &"reburn", &"hurt", &"death",
]

## Master list of all available enemy definitions
@export var monster_definitions: Array[EnemyDefinition] = []

@onready var preview_world: Node2D = $PreviewWorld
@onready var sprite: AnimatedSprite2D = $PreviewWorld/AnimatedSprite2D
@onready var effects_layer: Node2D = $PreviewWorld/EffectsLayer
@onready var monster_option: OptionButton = $UI/Panel/Margin/VBox/MonsterRow/MonsterOption
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
var _active_definition_index := 0


func _ready() -> void:
	if get_viewport() is Window:
		get_window().content_scale_size = PREVIEW_WINDOW_SIZE
		get_window().size = PREVIEW_WINDOW_SIZE
	get_viewport().size_changed.connect(_update_layout)
	monster_option.item_selected.connect(_on_monster_selected)
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

	# Populate monster dropdown
	if monster_definitions.is_empty():
		status_label.text = "没有可用的怪物定义"
		return
	for defn: EnemyDefinition in monster_definitions:
		monster_option.add_item(defn.display_name)
	monster_option.select(0)
	_load_monster(0)


func _load_monster(index: int) -> void:
	if index < 0 or index >= monster_definitions.size():
		return
	_active_definition_index = index
	var defn := monster_definitions[index]
	if defn == null or defn.animation_profile == null:
		status_label.text = "怪物 '%s' 缺少动画配置" % defn.display_name
		return
	_profile = defn.animation_profile
	var errors := defn.validate()
	if not errors.is_empty():
		status_label.text = "配置错误：\n" + "\n".join(errors)
		return

	# Find default action
	_current_action = _profile.default_animation
	if not _profile.actions.has(_current_action):
		for key in _profile.actions:
			_current_action = StringName(key)
			break

	# Build sprite frames
	sprite.sprite_frames = _profile.build_sprite_frames()

	# Rebuild action dropdown
	action_option.clear()
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
	status_label.text = "%s · %d 个动作" % [defn.display_name, action_option.item_count]


func _on_monster_selected(index: int) -> void:
	_load_monster(index)


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
	queue_redraw()


func play_action(action: StringName) -> void:
	if _profile == null or not _profile.actions.has(action):
		return
	_current_action = action
	var spec := _profile.get_spec(action)
	_saved_offset = _profile.get_offset(action)
	set_preview_offset(_saved_offset, false)
	sprite.play(action)
	if _paused:
		sprite.pause()
	offset_label.text = "当前坐标：%s" % sprite.position
	var defn := monster_definitions[_active_definition_index]
	source_label.text = "%s · 动作 %d/%d" % [
		defn.display_name,
		action_option.selected + 1,
		action_option.item_count,
	]
	_load_effects(action)
	event_label.text = "帧数：%d　循环：%s" % [
		int(spec.get("frame_count", 0)),
		"是" if bool(spec.get("loop", false)) else "否",
	]


func _load_effects(action: StringName) -> void:
	for child in effects_layer.get_children():
		child.queue_free()
	var spec := _profile.get_spec(action)
	var bullet_sheet := str(spec.get("bullet_sprite_sheet", ""))
	var bullet_json := str(spec.get("bullet_sprite_json", ""))
	if bullet_sheet.is_empty():
		return
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(bullet_sheet)) != OK:
		return
	var texture := ImageTexture.create_from_image(image)
	var file := FileAccess.open(bullet_json, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null:
		return
	var frames_data: Dictionary = data.get("frames", {})
	var sorted_names := PackedStringArray(frames_data.keys())
	sorted_names.sort()
	var effect_sprite := AnimatedSprite2D.new()
	effect_sprite.name = "EffectBullet"
	var sf := SpriteFrames.new()
	sf.add_animation("bullet")
	for fname: String in sorted_names:
		var fi: Dictionary = frames_data[fname]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(fi.get("x", 0), fi.get("y", 0), fi.get("w", 64), fi.get("h", 64))
		sf.add_frame("bullet", atlas)
	effect_sprite.sprite_frames = sf
	effect_sprite.scale = sprite.scale
	effect_sprite.position = sprite.position
	effects_layer.add_child(effect_sprite)
	effect_sprite.play("bullet")
	event_label.text += "\n弹道特效"

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
	if _active_definition_index >= 0 and _active_definition_index < monster_definitions.size():
		var defn := monster_definitions[_active_definition_index]
		var collision_rect := Rect2(
			origin + Vector2(-defn.collision_size.x * 0.5, -defn.collision_size.y),
			defn.collision_size
		)
		draw_rect(collision_rect, Color(0.35, 0.9, 0.45, 0.45), false, 2.0)
