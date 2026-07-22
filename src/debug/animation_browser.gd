class_name AnimationBrowser
extends Control

const BROWSER_WINDOW_SIZE := Vector2i(1280, 800)
const MODULES := [
	{
		"id": "roles",
		"label": "角色动作",
		"description": "四名角色、装备组合与全部运行时动作",
		"scene": preload("res://scenes/debug/role_animation_preview.tscn"),
	},
	{
		"id": "enemies",
		"label": "敌人动作",
		"description": "完整时间轴、源码事件帧与碰撞参考",
		"scene": preload("res://scenes/debug/enemy_animation_preview.tscn"),
	},
	{
		"id": "skills",
		"label": "技能特效",
		"description": "角色技能特效、注册点与显示偏移校准",
		"scene": preload("res://scenes/debug/skill_effect_calibrator.tscn"),
	},
]

@onready var description_label: Label = $Header/Margin/Row/Description
@onready var mode_buttons: HBoxContainer = $Header/Margin/Row/ModeButtons
@onready var module_viewport: SubViewport = $ModuleContainer/ModuleViewport

var _active_index := -1
var _active_module: Node


func _ready() -> void:
	if get_viewport() is Window:
		get_window().content_scale_size = BROWSER_WINDOW_SIZE
		get_window().size = BROWSER_WINDOW_SIZE
	for index in range(mode_buttons.get_child_count()):
		var button := mode_buttons.get_child(index) as Button
		button.pressed.connect(show_mode.bind(index))
	var requested_mode := _requested_mode_index()
	show_mode(requested_mode)


func show_mode(index: int) -> void:
	if index < 0 or index >= MODULES.size() or index == _active_index:
		return
	if _active_module != null and is_instance_valid(_active_module):
		_active_module.free()
	var module: Dictionary = MODULES[index]
	_active_module = (module["scene"] as PackedScene).instantiate()
	module_viewport.add_child(_active_module)
	_active_index = index
	description_label.text = str(module["description"])
	for button_index in range(mode_buttons.get_child_count()):
		var button := mode_buttons.get_child(button_index) as Button
		button.button_pressed = button_index == index


func show_mode_by_id(mode_id: String) -> void:
	for index in range(MODULES.size()):
		if str(MODULES[index]["id"]) == mode_id:
			show_mode(index)
			return


func get_active_mode_id() -> String:
	return str(MODULES[_active_index]["id"]) if _active_index >= 0 else ""


func get_active_module() -> Node:
	return _active_module


func _requested_mode_index() -> int:
	var environment_mode := OS.get_environment("DREAMMAKE_ANIMATION_MODE")
	if not environment_mode.is_empty():
		for index in range(MODULES.size()):
			if str(MODULES[index]["id"]) == environment_mode:
				return index
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--animation-mode="):
			continue
		var requested := argument.trim_prefix("--animation-mode=")
		for index in range(MODULES.size()):
			if str(MODULES[index]["id"]) == requested:
				return index
	return 0
