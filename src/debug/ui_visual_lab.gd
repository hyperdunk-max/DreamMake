extends Control

const STYLE_PATHS: PackedStringArray = [
	"res://resources/ui/number_styles/pnum_player_damage.tres",
	"res://resources/ui/number_styles/bunum_recovery.tres",
	"res://resources/ui/number_styles/bulnum_bullet.tres",
	"res://resources/ui/number_styles/hurtnum_damage.tres",
	"res://resources/ui/number_styles/bnum_critical.tres",
	"res://resources/ui/number_styles/num_combo.tres",
]
const SAMPLE_EQUIPMENT_PATH := "res://assets/ui/equipment/qlp.png"


func _ready() -> void:
	_build_background()
	_build_number_preview()
	_build_equipment_preview()
	if OS.has_environment("DREAMMAKE_CAPTURE_UI_LAB"):
		get_tree().create_timer(0.5).timeout.connect(_capture_now)


func _build_background() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("120d14")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_add_caption("Flash 数字 → Godot Text + 参数化描边/发光", Vector2(28, 18), 24, Color("ffe6a0"))
	_add_caption("同一字体、同一 shader；每种效果仅保存轻量 Style 资源", Vector2(30, 52), 14, Color("a997b1"))


func _build_number_preview() -> void:
	for index: int in range(STYLE_PATHS.size()):
		var style := load(STYLE_PATHS[index]) as FloatingNumberStyle
		if style == null:
			continue
		var row := index / 2
		var column := index % 2
		var origin := Vector2(32 + column * 440, 88 + row * 104)
		_add_caption(style.display_name, origin, 15, Color("d8c9df"))
		var number := FloatingNumber.new()
		number.position = origin + Vector2(0, 24)
		number.configure("0123456789" if style.style_id != &"num" else "12345", style, false)
		add_child(number)


func _build_equipment_preview() -> void:
	var texture := load(SAMPLE_EQUIPMENT_PATH) as Texture2D
	var top := 414.0
	_add_caption("装备：一个透明图标，两种组合上下文", Vector2(30, top), 18, Color("ffe6a0"))
	var inventory_view := EquipmentIconView.new()
	inventory_view.position = Vector2(42, top + 38)
	inventory_view.configure(texture, "fine", EquipmentIconView.Context.INVENTORY)
	add_child(inventory_view)
	_add_caption("背包 = 格子 + 品质框 + 图标", Vector2(116, top + 52), 14, Color("c9bb9e"))

	var drop_view := EquipmentIconView.new()
	drop_view.position = Vector2(454, top + 38)
	drop_view.configure(texture, "fine", EquipmentIconView.Context.DROP)
	add_child(drop_view)
	_add_caption("掉落 = 同一图标 + 发光/浮动", Vector2(528, top + 52), 14, Color("c9bb9e"))
	_add_caption("不再保留“格子背景已烘焙进装备图”的重复 PNG", Vector2(30, 536), 13, Color("8e7f95"))


func _add_caption(text: String, position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = Vector2(410, 28)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _capture_now() -> void:
	var path := OS.get_environment("DREAMMAKE_CAPTURE_UI_LAB")
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Failed to save UI visual lab capture: %s" % error)
	get_tree().quit(0 if error == OK else 1)
