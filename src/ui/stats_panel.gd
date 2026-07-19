class_name StatsPanel
extends CanvasLayer

## Character attribute view. It renders StatsPresenter snapshots and contains no
## equipment/stat calculation logic.

const ROW_HEIGHT: float = 31.0
const QUALITY_COLORS: Dictionary = {
	"common": Color("c9b17a"), "excellent": Color("70d373"),
	"fine": Color("6bbbf0"), "epic": Color("d18af0"),
	"evil": Color("ed7668"), "legendary": Color("ffd05d"),
}

var _presenter: StatsPresenter = StatsPresenter.new()
var _icon_provider: InventoryIconProvider = InventoryIconProvider.new()
var _snapshot: Dictionary = {}
var _value_labels: Dictionary = {}
var _detail_labels: Dictionary = {}
var _equipment_labels: Array[Label] = []

var _root: Control
var _portrait: TextureRect
var _name_label: Label
var _resource_label: Label


func setup(owner_player: CharacterBody2D) -> void:
	if not _presenter.view_changed.is_connected(_on_view_changed):
		_presenter.view_changed.connect(_on_view_changed)
	_presenter.setup(owner_player)


func _ready() -> void:
	layer = 11
	visible = false
	_build_panel()
	if not _snapshot.is_empty():
		_render_snapshot()


func open() -> void:
	visible = true
	_presenter.refresh()


func close() -> void:
	visible = false


func refresh() -> void:
	_presenter.refresh()


func get_presenter() -> StatsPresenter:
	return _presenter


func _build_panel() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.015, 0.01, 0.008, 0.7)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_root = Control.new()
	_root.position = Vector2(110, 48)
	_root.size = Vector2(720, 494)
	add_child(_root)

	var shadow: Panel = Panel.new()
	shadow.position = Vector2(7, 8)
	shadow.size = _root.size
	shadow.add_theme_stylebox_override("panel", _make_style(Color(0.0, 0.0, 0.0, 0.58), Color.TRANSPARENT, 0, 10))
	_root.add_child(shadow)
	var panel: Panel = Panel.new()
	panel.size = _root.size
	panel.add_theme_stylebox_override("panel", _make_style(Color("24150d"), Color("c89b45"), 4, 10))
	_root.add_child(panel)
	var inner: Panel = Panel.new()
	inner.position = Vector2(10, 10)
	inner.size = Vector2(700, 474)
	inner.add_theme_stylebox_override("panel", _make_style(Color("49301c"), Color("6f4a26"), 2, 6))
	_root.add_child(inner)

	var title_band: Panel = Panel.new()
	title_band.position = Vector2(20, 18)
	title_band.size = Vector2(680, 48)
	title_band.add_theme_stylebox_override("panel", _make_style(Color("244c52"), Color("e1c46c"), 2, 5))
	_root.add_child(title_band)
	_add_label("角 色 属 性", Vector2(270, 26), Vector2(180, 32), 24, Color("ffeaa0"), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("E 关闭", Vector2(620, 34), Vector2(60, 20), 12, Color("d2c28b"), HORIZONTAL_ALIGNMENT_RIGHT)

	var portrait_frame: Panel = Panel.new()
	portrait_frame.position = Vector2(24, 82)
	portrait_frame.size = Vector2(220, 240)
	portrait_frame.add_theme_stylebox_override("panel", _make_style(Color("151512"), Color("98733d"), 2, 5))
	_root.add_child(portrait_frame)
	var portrait_glow: ColorRect = ColorRect.new()
	portrait_glow.position = Vector2(32, 90)
	portrait_glow.size = Vector2(204, 224)
	portrait_glow.color = Color("183c3d")
	_root.add_child(portrait_glow)
	_portrait = TextureRect.new()
	_portrait.position = Vector2(42, 96)
	_portrait.size = Vector2(184, 190)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_root.add_child(_portrait)
	_name_label = _add_label("", Vector2(36, 278), Vector2(196, 28), 20, Color("ffe29a"), HORIZONTAL_ALIGNMENT_CENTER)
	_resource_label = _add_label("", Vector2(34, 330), Vector2(204, 48), 13, Color("d8c69b"), HORIZONTAL_ALIGNMENT_CENTER)

	var equipment_title: Label = _add_label("当前装备", Vector2(38, 386), Vector2(196, 22), 14, Color("d5b96f"), HORIZONTAL_ALIGNMENT_CENTER)
	equipment_title.add_theme_color_override("font_outline_color", Color("29160b"))
	equipment_title.add_theme_constant_override("outline_size", 3)
	for index: int in range(4):
		var equipment_label: Label = _add_label("", Vector2(34, 412 + index * 17), Vector2(204, 17), 11, Color("b9a17d"))
		_equipment_labels.append(equipment_label)

	var stats_frame: Panel = Panel.new()
	stats_frame.position = Vector2(260, 82)
	stats_frame.size = Vector2(436, 390)
	stats_frame.add_theme_stylebox_override("panel", _make_style(Color("17110c"), Color("98733d"), 2, 5))
	_root.add_child(stats_frame)
	_add_label("属性", Vector2(280, 96), Vector2(140, 22), 13, Color("bba77d"))
	_add_label("当前", Vector2(470, 96), Vector2(80, 22), 13, Color("bba77d"), HORIZONTAL_ALIGNMENT_RIGHT)
	_add_label("基础 + 装备", Vector2(562, 96), Vector2(112, 22), 13, Color("bba77d"), HORIZONTAL_ALIGNMENT_RIGHT)
	var separator: ColorRect = ColorRect.new()
	separator.position = Vector2(278, 121)
	separator.size = Vector2(400, 1)
	separator.color = Color("715536")
	_root.add_child(separator)

	var keys: Array[String] = [
		"max_health", "max_mana", "attack", "defense", "crit_rate",
		"dodge_rate", "hp_regen", "mp_regen", "magic_resist",
	]
	var labels: Array[String] = ["生命上限", "魔法上限", "攻击力", "防御力", "暴击率", "闪避率", "生命恢复", "魔法恢复", "魔法抗性"]
	for index: int in range(keys.size()):
		var y: float = 130.0 + index * ROW_HEIGHT
		if index % 2 == 0:
			var row_background: ColorRect = ColorRect.new()
			row_background.position = Vector2(272, y - 3)
			row_background.size = Vector2(412, ROW_HEIGHT)
			row_background.color = Color(0.95, 0.77, 0.43, 0.055)
			_root.add_child(row_background)
		_add_label(labels[index], Vector2(282, y), Vector2(160, 24), 14, Color("ead8ad"))
		var value_label: Label = _add_label("", Vector2(450, y), Vector2(100, 24), 15, Color("9be184"), HORIZONTAL_ALIGNMENT_RIGHT)
		var detail_label: Label = _add_label("", Vector2(558, y), Vector2(116, 24), 12, Color("b9a889"), HORIZONTAL_ALIGNMENT_RIGHT)
		_value_labels[keys[index]] = value_label
		_detail_labels[keys[index]] = detail_label
	_add_label("绿色数值为装备加成后的实际属性", Vector2(282, 426), Vector2(392, 24), 12, Color("8f7c61"), HORIZONTAL_ALIGNMENT_CENTER)


func _render_snapshot() -> void:
	if _name_label == null:
		return
	_name_label.text = "%s  ·  壹级" % str(_snapshot.get("role_name", ""))
	_resource_label.text = "当前生命  %d\n当前魔法  %d" % [int(_snapshot.get("health", 0)), int(_snapshot.get("mana", 0))]
	var body_atlas: Texture2D = _snapshot.get("body_atlas") as Texture2D
	var weapon_atlas: Texture2D = _snapshot.get("weapon_atlas") as Texture2D
	var frame_size: Vector2i = Vector2i(_snapshot.get("frame_size", Vector2i(200, 200)))
	_portrait.texture = _icon_provider.get_character_portrait(body_atlas, weapon_atlas, frame_size)

	var rows: Array = _snapshot.get("rows", [])
	for row_value: Variant in rows:
		var row: Dictionary = row_value
		var key: String = str(row.get("key", ""))
		var value_label: Label = _value_labels.get(key) as Label
		var detail_label: Label = _detail_labels.get(key) as Label
		var is_percent: bool = bool(row.get("percent", false))
		var base_value: float = float(row.get("base", 0.0))
		var bonus_value: float = float(row.get("bonus", 0.0))
		var effective_value: float = float(row.get("effective", 0.0))
		if is_percent:
			value_label.text = "%.1f%%" % (effective_value * 100.0)
			detail_label.text = _format_percent_detail(base_value, bonus_value)
		else:
			value_label.text = str(roundi(effective_value))
			detail_label.text = _format_number_detail(roundi(base_value), roundi(bonus_value))

	var equipment: Array = _snapshot.get("equipment", [])
	for index: int in range(_equipment_labels.size()):
		var label: Label = _equipment_labels[index]
		if index >= equipment.size():
			label.text = ""
			continue
		var entry: Dictionary = equipment[index]
		label.text = "%s  ·  %s" % [entry.get("slot_label", ""), entry.get("name", "未装备")]
		label.add_theme_color_override("font_color", Color(QUALITY_COLORS.get(str(entry.get("quality", "common")), QUALITY_COLORS["common"])))


func _format_percent_detail(base_value: float, bonus_value: float) -> String:
	if is_zero_approx(bonus_value):
		return "%.1f%%" % (base_value * 100.0)
	return "%.1f%%  +%.1f%%" % [base_value * 100.0, bonus_value * 100.0]


func _format_number_detail(base_value: int, bonus_value: int) -> String:
	if bonus_value == 0:
		return str(base_value)
	return "%d  +%d" % [base_value, bonus_value]


func _on_view_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_render_snapshot()


func _add_label(text: String, position: Vector2, label_size: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = position
	label.size = label_size
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_root.add_child(label)
	return label


func _make_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
