class_name RoleAnimationPreview
extends Node2D

const PREVIEW_WINDOW_SIZE := Vector2i(1280, 724)
const PANEL_WIDTH := 320.0
const ROLE_ENTRIES := [
	{"name": "悟空", "path": "res://resources/roles/role_1_wukong_definition.tres"},
	{"name": "唐僧", "path": "res://resources/roles/role_2_tangseng_definition.tres"},
	{"name": "八戒", "path": "res://resources/roles/role_3_bajie_definition.tres"},
	{"name": "沙僧", "path": "res://resources/roles/role_4_shaseng_definition.tres"},
]
const ACTION_ORDER := [
	&"idle", &"run", &"move", &"jump", &"jump_down", &"attack1", &"attack2",
	&"attack3", &"attack4", &"hurt", &"death",
]

@onready var preview_world: Node2D = $PreviewWorld
@onready var animator: LayeredSpriteAnimator = $PreviewWorld/LayeredSpriteAnimator
@onready var role_option: OptionButton = $UI/Panel/Margin/VBox/RoleOption
@onready var action_option: OptionButton = $UI/Panel/Margin/VBox/ActionOption
@onready var body_option: OptionButton = $UI/Panel/Margin/VBox/BodyOption
@onready var weapon_option: OptionButton = $UI/Panel/Margin/VBox/WeaponOption
@onready var replay_button: Button = $UI/Panel/Margin/VBox/Buttons/ReplayButton
@onready var pause_button: Button = $UI/Panel/Margin/VBox/Buttons/PauseButton
@onready var facing_button: Button = $UI/Panel/Margin/VBox/Buttons/FacingButton
@onready var zoom_spin: SpinBox = $UI/Panel/Margin/VBox/ZoomRow/ZoomSpin
@onready var x_spin: SpinBox = $UI/Panel/Margin/VBox/Coordinates/XSpin
@onready var y_spin: SpinBox = $UI/Panel/Margin/VBox/Coordinates/YSpin
@onready var frame_label: Label = $UI/Panel/Margin/VBox/FrameLabel
@onready var position_label: Label = $UI/Panel/Margin/VBox/PositionLabel
@onready var source_label: Label = $UI/Panel/Margin/VBox/SourceLabel
@onready var status_label: Label = $UI/Panel/Margin/VBox/StatusLabel

var _definition: RoleDefinition
var _profile: RoleAnimationProfile
var _paused := false
var _facing := 1.0
var _saved_offset := Vector2.ZERO
var _preview_offset := Vector2.ZERO
var _dragging := false
var _updating_controls := false


func _ready() -> void:
	if get_viewport() is Window:
		get_window().content_scale_size = PREVIEW_WINDOW_SIZE
		get_window().size = PREVIEW_WINDOW_SIZE
	get_viewport().size_changed.connect(_update_layout)
	role_option.item_selected.connect(_on_role_selected)
	action_option.item_selected.connect(_on_action_selected)
	body_option.item_selected.connect(_on_body_selected)
	weapon_option.item_selected.connect(_on_weapon_selected)
	replay_button.pressed.connect(_replay)
	pause_button.pressed.connect(_toggle_pause)
	facing_button.pressed.connect(_toggle_facing)
	zoom_spin.value_changed.connect(_on_zoom_changed)
	x_spin.value_changed.connect(_on_coordinate_changed)
	y_spin.value_changed.connect(_on_coordinate_changed)
	$UI/Panel/Margin/VBox/EditButtons/ResetButton.pressed.connect(_reset_offset)
	$UI/Panel/Margin/VBox/EditButtons/SaveButton.pressed.connect(_save_offset)
	for entry: Dictionary in ROLE_ENTRIES:
		role_option.add_item(str(entry["name"]))
	role_option.select(0)
	_on_role_selected(0)
	_on_zoom_changed(zoom_spin.value)
	_update_layout()


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
	frame_label.text = "当前帧：%d / %d　动作：%s" % [
		animator.get_current_frame_index() + 1,
		animator.get_current_frame_count(),
		str(animator.get_current_action()),
	]
	queue_redraw()


func _on_role_selected(index: int) -> void:
	if index < 0 or index >= ROLE_ENTRIES.size():
		return
	_definition = load(str(ROLE_ENTRIES[index]["path"])) as RoleDefinition
	if _definition == null or _definition.animation_profile == null:
		status_label.text = "角色动画资源加载失败"
		return
	_profile = _definition.animation_profile
	var errors := _definition.validate()
	if not errors.is_empty():
		status_label.text = "配置错误：\n" + "\n".join(errors)
		return
	if not animator.register_role(
		_definition.role_id, _profile,
		_definition.default_body_showid, _definition.default_weapon_showid
	):
		status_label.text = "角色动画注册失败"
		return
	animator.set_facing(_facing)
	_load_saved_offset()
	_populate_bodies()
	_populate_weapons()
	_populate_actions(_profile.default_action)
	_update_source_label()
	status_label.text = "已加载 %s 的全部运行时动作" % _definition.display_name


func _populate_bodies() -> void:
	body_option.clear()
	var showids := _profile.get_body_showids()
	showids.sort()
	for raw_showid: Variant in showids:
		var showid := int(raw_showid)
		body_option.add_item("%s（ID %d）" % [_profile.get_body_name(showid), showid])
		body_option.set_item_metadata(body_option.item_count - 1, showid)
	_select_metadata(body_option, animator.get_body_showid())


func _populate_weapons() -> void:
	weapon_option.clear()
	var showids := _profile.get_weapon_showids()
	showids.sort()
	for raw_showid: Variant in showids:
		var showid := int(raw_showid)
		var mode := _profile.get_weapon_mode(showid)
		weapon_option.add_item("%s · %s（ID %d）" % [_profile.get_weapon_name(showid), mode, showid])
		weapon_option.set_item_metadata(weapon_option.item_count - 1, showid)
	_select_metadata(weapon_option, animator.get_weapon_showid())


func _populate_actions(preferred: StringName) -> void:
	action_option.clear()
	var compiled := _profile.compile_animations(animator.get_weapon_showid())
	var ordered: Array[StringName] = []
	for action: StringName in ACTION_ORDER:
		if compiled.has(action):
			ordered.append(action)
	var remaining: Array[String] = []
	for raw_action: Variant in compiled:
		var action := StringName(raw_action)
		if not ordered.has(action):
			remaining.append(str(action))
	remaining.sort()
	for raw_action: String in remaining:
		ordered.append(StringName(raw_action))
	for action: StringName in ordered:
		action_option.add_item(str(action))
		action_option.set_item_metadata(action_option.item_count - 1, action)
	var selected_action := preferred if compiled.has(preferred) else _profile.default_action
	_select_metadata(action_option, selected_action)
	animator.play_action(selected_action, true)


func _select_metadata(option: OptionButton, value: Variant) -> void:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)


func _on_action_selected(index: int) -> void:
	if index >= 0 and index < action_option.item_count:
		animator.play_action(StringName(action_option.get_item_metadata(index)), true)


func _on_body_selected(index: int) -> void:
	if index >= 0 and index < body_option.item_count:
		animator.set_body(int(body_option.get_item_metadata(index)))
		_update_source_label()


func _on_weapon_selected(index: int) -> void:
	if index < 0 or index >= weapon_option.item_count:
		return
	var previous_action := animator.get_current_action()
	if animator.set_weapon(int(weapon_option.get_item_metadata(index))):
		_populate_actions(previous_action)
		_update_source_label()


func _replay() -> void:
	animator.play_action(animator.get_current_action(), true)


func _toggle_pause() -> void:
	_paused = not _paused
	animator.process_mode = Node.PROCESS_MODE_DISABLED if _paused else Node.PROCESS_MODE_INHERIT
	pause_button.text = "继续" if _paused else "暂停"


func _toggle_facing() -> void:
	_facing *= -1.0
	animator.set_facing(_facing)
	facing_button.text = "朝向：右" if _facing > 0.0 else "朝向：左"


func _on_zoom_changed(value: float) -> void:
	preview_world.scale = Vector2.ONE * float(value)
	queue_redraw()


func set_preview_offset(value: Vector2, mark_dirty := true) -> void:
	_preview_offset = Vector2(roundf(value.x), roundf(value.y))
	animator.position = _preview_offset
	_updating_controls = true
	x_spin.value = _preview_offset.x
	y_spin.value = _preview_offset.y
	_updating_controls = false
	position_label.text = "当前：Vector2(%d, %d)" % [int(_preview_offset.x), int(_preview_offset.y)]
	if mark_dirty:
		status_label.text = "预览坐标已修改，尚未写入角色动画配置"
	queue_redraw()


func get_preview_offset() -> Vector2:
	return _preview_offset


func _load_saved_offset() -> void:
	_saved_offset = _profile.get_runtime_visual_offset()
	set_preview_offset(_saved_offset, false)


func _on_coordinate_changed(_value: float) -> void:
	if _updating_controls:
		return
	set_preview_offset(Vector2(x_spin.value, y_spin.value))


func _update_offset_from_mouse(mouse_position: Vector2) -> void:
	set_preview_offset(preview_world.to_local(mouse_position))


func _reset_offset() -> void:
	set_preview_offset(_saved_offset, false)
	status_label.text = "已恢复最近一次保存坐标"


func _save_offset() -> void:
	if _profile == null or _profile.resource_path.is_empty():
		status_label.text = "保存失败：角色动画配置没有资源路径"
		return
	_profile.visual_nudge = _preview_offset - _profile.visual_offset
	var error := ResourceSaver.save(_profile, _profile.resource_path)
	if error != OK:
		status_label.text = "保存失败，错误码：%d" % error
		return
	_saved_offset = _preview_offset
	status_label.text = "已保存到角色动画配置：Vector2(%d, %d)" % [
		int(_preview_offset.x), int(_preview_offset.y),
	]


func _update_source_label() -> void:
	if _profile == null:
		return
	source_label.text = "配置：%s　逻辑帧率：%.1f FPS\n防具 ID：%d　武器 ID：%d　模式：%s\n保存字段：visual_nudge" % [
		str(_profile.role_key), _profile.logical_fps,
		animator.get_body_showid(), animator.get_weapon_showid(),
		str(_profile.get_weapon_mode(animator.get_weapon_showid())),
	]


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
	if animator != null:
		var visual_origin := preview_world.to_global(animator.position)
		draw_line(origin, visual_origin, Color(0.3, 0.85, 1.0, 0.8), 2.0)
		draw_circle(visual_origin, 5.0, Color(0.3, 0.85, 1.0))
