extends CanvasLayer

var player_bar: ProgressBar
var enemy_bar: ProgressBar
var message_label: Label
var weapon_label: Label
var body_label: Label
var player_name_label: Label


func _ready() -> void:
	player_bar = _make_bar(Vector2(32, 35), Vector2(285, 22), Color("d84a38"))
	enemy_bar = _make_bar(Vector2(623, 35), Vector2(285, 22), Color("9e3131"))

	var title := Label.new()
	title.text = "造梦西游 3 · 角色战斗验证"
	title.position = Vector2(350, 15)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	player_name_label = Label.new()
	player_name_label.text = "悟空"
	player_name_label.position = Vector2(32, 10)
	player_name_label.add_theme_font_size_override("font_size", 18)
	add_child(player_name_label)

	var enemy_name := Label.new()
	enemy_name.text = "训练木妖"
	enemy_name.position = Vector2(824, 10)
	enemy_name.add_theme_font_size_override("font_size", 18)
	add_child(enemy_name)

	var controls := Label.new()
	controls.text = "A/D 移动  K 二段跳  J 普攻  Q 换武器  E 换衣服  H 敌人攻击  1-4 换角色  R 重开"
	controls.position = Vector2(48, 550)
	controls.add_theme_font_size_override("font_size", 15)
	controls.add_theme_color_override("font_color", Color("f5dfac"))
	add_child(controls)

	weapon_label = _make_equipment_label(Vector2(32, 62))
	body_label = _make_equipment_label(Vector2(32, 83))

	message_label = Label.new()
	message_label.position = Vector2(250, 245)
	message_label.size = Vector2(440, 70)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 25)
	message_label.add_theme_color_override("font_color", Color("ffe08b"))
	add_child(message_label)


func _make_equipment_label(position: Vector2) -> Label:
	var label := Label.new()
	label.position = position
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("f5dfac"))
	add_child(label)
	return label


func _make_bar(position: Vector2, size: Vector2, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position
	bar.size = size
	bar.show_percentage = false
	bar.max_value = 100
	var background := StyleBoxFlat.new()
	background.bg_color = Color("221d1c")
	background.border_color = Color("d2b26e")
	background.set_border_width_all(2)
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill
	foreground.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", foreground)
	add_child(bar)
	return bar


func set_player_health(current: int, maximum: int) -> void:
	player_bar.max_value = maximum
	player_bar.value = current


func set_enemy_health(current: int, maximum: int) -> void:
	enemy_bar.max_value = maximum
	enemy_bar.value = current


func show_message(text: String) -> void:
	message_label.text = text


func set_weapon(showid: int, weapon_name: String) -> void:
	weapon_label.text = "武器 showid %d · %s" % [showid, weapon_name]


func set_body(showid: int, body_name: String) -> void:
	body_label.text = "衣服 showid %d · %s" % [showid, body_name]


func set_role(_role_id: int, display_name: String) -> void:
	player_name_label.text = display_name
