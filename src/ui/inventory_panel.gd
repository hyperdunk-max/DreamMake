class_name InventoryPanel
extends CanvasLayer

## Backpack view. Domain state arrives only as presenter snapshots; user actions
## leave only as intent signals handled by the gameplay layer.

signal equip_requested(item_id: String, equip_id: String)
signal unequip_requested(slot: String)
signal use_requested(item_id: String)
signal sell_requested(item_id: String)

const GRID_COLUMNS: int = 5
const GRID_ROWS: int = 4
const SLOT_COUNT: int = GRID_COLUMNS * GRID_ROWS
const SLOT_PITCH: Vector2 = Vector2(69, 69)
const QUALITY_LABELS: Dictionary = {
	"common": "普通", "excellent": "优秀", "fine": "精良",
	"epic": "史诗", "evil": "邪灵", "legendary": "传说",
}
const STAT_LABELS: Dictionary = {
	"attack": "攻击", "defense": "防御", "max_health": "生命",
	"max_mana": "魔法", "crit_rate": "暴击", "dodge_rate": "闪避",
	"hp_regen": "回血", "mp_regen": "回蓝", "magic_resist": "魔抗",
}

var _presenter: InventoryPresenter = InventoryPresenter.new()
var _icon_provider: InventoryIconProvider = InventoryIconProvider.new()
var _slot_pool: InventorySlotPool = InventorySlotPool.new()
var _snapshot: Dictionary = {}
var _selected_detail: Dictionary = {}
var _active_slots: Array[InventorySlot] = []

var _root: Control
var _grid_host: Control
var _page_label: Label
var _capacity_label: Label
var _previous_button: Button
var _next_button: Button
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_desc: Label
var _detail_stats: Label
var _equip_button: Button
var _unequip_button: Button
var _use_button: Button
var _sell_button: Button


func setup(owner_player: CharacterBody2D) -> void:
	if not _presenter.view_changed.is_connected(_on_view_changed):
		_presenter.view_changed.connect(_on_view_changed)
	if not _presenter.selection_changed.is_connected(_on_selection_changed):
		_presenter.selection_changed.connect(_on_selection_changed)
	_presenter.setup(owner_player, SLOT_COUNT)


func _ready() -> void:
	layer = 10
	visible = false
	_build_panel()
	if not _snapshot.is_empty():
		_render_snapshot()
		_render_detail()


func open() -> void:
	visible = true
	_presenter.refresh()


func close() -> void:
	visible = false


func refresh() -> void:
	_presenter.refresh()


func get_presenter() -> InventoryPresenter:
	return _presenter


func get_pool_metrics() -> Dictionary:
	return {
		"created": _slot_pool.get_created_count(),
		"active": _slot_pool.get_active_count(),
		"available": _slot_pool.get_available_count(),
	}


func _build_panel() -> void:
	var overlay: ColorRect = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.015, 0.01, 0.008, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_root = Control.new()
	_root.position = Vector2(70, 40)
	_root.size = Vector2(800, 510)
	add_child(_root)

	var shadow: Panel = Panel.new()
	shadow.position = Vector2(6, 7)
	shadow.size = _root.size
	shadow.add_theme_stylebox_override("panel", _make_panel_style(Color(0.0, 0.0, 0.0, 0.6), Color.TRANSPARENT, 0, 10))
	_root.add_child(shadow)

	var panel: Panel = Panel.new()
	panel.size = _root.size
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color("24150d"), Color("c89b45"), 4, 10))
	_root.add_child(panel)

	var inner: Panel = Panel.new()
	inner.position = Vector2(10, 10)
	inner.size = Vector2(780, 490)
	inner.add_theme_stylebox_override("panel", _make_panel_style(Color("49301c"), Color("6f4a26"), 2, 6))
	_root.add_child(inner)

	var title_band: Panel = Panel.new()
	title_band.position = Vector2(20, 18)
	title_band.size = Vector2(760, 48)
	title_band.add_theme_stylebox_override("panel", _make_panel_style(Color("7c281a"), Color("e5bd66"), 2, 5))
	_root.add_child(title_band)
	_add_label(_root, "行 囊", Vector2(338, 26), Vector2(130, 32), 24, Color("ffe79a"), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(_root, "Tab 关闭", Vector2(680, 34), Vector2(80, 20), 12, Color("d2b785"), HORIZONTAL_ALIGNMENT_RIGHT)

	var grid_frame: Panel = Panel.new()
	grid_frame.position = Vector2(24, 80)
	grid_frame.size = Vector2(368, 356)
	grid_frame.add_theme_stylebox_override("panel", _make_panel_style(Color("160f0a"), Color("9b7139"), 2, 4))
	_root.add_child(grid_frame)
	_grid_host = Control.new()
	_grid_host.position = Vector2(36, 92)
	_grid_host.size = Vector2(340, 270)
	_root.add_child(_grid_host)

	_previous_button = _make_button("◀ 上一页", Vector2(36, 378), Vector2(100, 34), _on_previous_pressed)
	_next_button = _make_button("下一页 ▶", Vector2(276, 378), Vector2(100, 34), _on_next_pressed)
	_page_label = _add_label(_root, "1 / 1", Vector2(148, 382), Vector2(116, 26), 15, Color("f4d98a"), HORIZONTAL_ALIGNMENT_CENTER)
	_capacity_label = _add_label(_root, "", Vector2(36, 414), Vector2(340, 18), 12, Color("aa906c"), HORIZONTAL_ALIGNMENT_CENTER)

	var detail_frame: Panel = Panel.new()
	detail_frame.position = Vector2(408, 80)
	detail_frame.size = Vector2(368, 356)
	detail_frame.add_theme_stylebox_override("panel", _make_panel_style(Color("1c120b"), Color("9b7139"), 2, 4))
	_root.add_child(detail_frame)

	var icon_frame: Panel = Panel.new()
	icon_frame.position = Vector2(426, 98)
	icon_frame.size = Vector2(88, 88)
	icon_frame.add_theme_stylebox_override("panel", _make_panel_style(Color("100b08"), Color("70502c"), 2, 3))
	_root.add_child(icon_frame)
	_detail_icon = TextureRect.new()
	_detail_icon.position = Vector2(432, 104)
	_detail_icon.size = Vector2(76, 76)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_root.add_child(_detail_icon)

	_detail_name = _add_label(_root, "请选择物品", Vector2(526, 100), Vector2(232, 28), 18, Color("ffe29a"))
	_detail_desc = _add_label(_root, "", Vector2(526, 132), Vector2(228, 54), 12, Color("d0bd9d"))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_stats = _add_label(_root, "", Vector2(426, 202), Vector2(328, 188), 14, Color("b9e28a"))

	_equip_button = _make_button("装 备", Vector2(426, 394), Vector2(76, 34), _on_equip_pressed)
	_unequip_button = _make_button("卸 下", Vector2(510, 394), Vector2(76, 34), _on_unequip_pressed)
	_use_button = _make_button("使 用", Vector2(594, 394), Vector2(76, 34), _on_use_pressed)
	_sell_button = _make_button("出 售", Vector2(678, 394), Vector2(76, 34), _on_sell_pressed)
	_add_label(_root, "原作角色与装备图集 · 分页格复用", Vector2(30, 458), Vector2(740, 20), 12, Color("90765a"), HORIZONTAL_ALIGNMENT_CENTER)


func _render_snapshot() -> void:
	if _grid_host == null:
		return
	_slot_pool.release_all()
	_active_slots.clear()
	var items: Array = _snapshot.get("items", [])
	var selected_item_id: String = str(_snapshot.get("selected_item_id", ""))
	for index: int in range(SLOT_COUNT):
		var row: int = index / GRID_COLUMNS
		var column: int = index % GRID_COLUMNS
		var slot: InventorySlot = _slot_pool.acquire(
			_grid_host,
			index,
			Vector2(column, row) * SLOT_PITCH,
			_on_slot_clicked
		)
		if index < items.size():
			var item: Dictionary = items[index]
			slot.bind(item, _icon_provider.get_item_icon(item))
			slot.set_selected(str(item.get("id", "")) == selected_item_id)
		else:
			slot.clear()
		_active_slots.append(slot)
	var page: int = int(_snapshot.get("current_page", 0)) + 1
	var page_count: int = int(_snapshot.get("page_count", 1))
	_page_label.text = "%d / %d" % [page, page_count]
	_capacity_label.text = "已占用 %d 格 · 每页 %d 格" % [int(_snapshot.get("total_items", 0)), SLOT_COUNT]
	_previous_button.disabled = not bool(_snapshot.get("can_previous", false))
	_next_button.disabled = not bool(_snapshot.get("can_next", false))


func _render_detail() -> void:
	if _detail_name == null:
		return
	if _selected_detail.is_empty():
		_detail_icon.texture = null
		_detail_name.text = "请选择物品"
		_detail_desc.text = "点击行囊格查看说明与属性。"
		_detail_stats.text = ""
		_set_action_buttons(false, false, false, false)
		return
	_detail_icon.texture = _icon_provider.get_item_icon(_selected_detail)
	_detail_name.text = str(_selected_detail.get("name", ""))
	_detail_desc.text = str(_selected_detail.get("description", ""))
	var lines: PackedStringArray = []
	var item_type: String = str(_selected_detail.get("type", ""))
	if item_type == "equipment":
		var slot_labels: Dictionary = {"weapon": "武器", "armor": "防具", "accessory": "饰品"}
		lines.append("部位  %s" % slot_labels.get(str(_selected_detail.get("slot", "")), "装备"))
		lines.append("品质  %s" % QUALITY_LABELS.get(str(_selected_detail.get("quality", "common")), "普通"))
		lines.append("")
		var stats: Dictionary = _selected_detail.get("stats", {})
		for raw_key: Variant in stats:
			var key: String = str(raw_key)
			var value: Variant = stats[raw_key]
			if key in ["crit_rate", "dodge_rate", "magic_resist"]:
				lines.append("%s  +%.1f%%" % [STAT_LABELS.get(key, key), float(value) * 100.0])
			else:
				lines.append("%s  +%s" % [STAT_LABELS.get(key, key), value])
		if bool(_selected_detail.get("equipped", false)):
			lines.append("")
			lines.append("【当前已装备】")
		var compatible: bool = bool(_selected_detail.get("role_compatible", false))
		var equipped: bool = bool(_selected_detail.get("equipped", false))
		_set_action_buttons(compatible and not equipped, equipped, false, not equipped)
	else:
		var type_labels: Dictionary = {"consumable": "消耗品", "material": "材料"}
		lines.append("类型  %s" % type_labels.get(item_type, item_type))
		lines.append("数量  %d" % int(_selected_detail.get("count", 0)))
		_set_action_buttons(false, false, item_type == "consumable", true)
	_detail_stats.text = "\n".join(lines)


func _set_action_buttons(can_equip: bool, can_unequip: bool, can_use: bool, can_sell: bool) -> void:
	_equip_button.disabled = not can_equip
	_unequip_button.disabled = not can_unequip
	_use_button.disabled = not can_use
	_sell_button.disabled = not can_sell


func _on_view_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_render_snapshot()


func _on_selection_changed(detail: Dictionary) -> void:
	_selected_detail = detail
	_render_detail()


func _on_slot_clicked(index: int) -> void:
	_presenter.select_page_index(index)


func _on_previous_pressed() -> void:
	_presenter.previous_page()


func _on_next_pressed() -> void:
	_presenter.next_page()


func _on_equip_pressed() -> void:
	if _selected_detail.is_empty():
		return
	equip_requested.emit(str(_selected_detail.get("id", "")), str(_selected_detail.get("equip_id", "")))


func _on_unequip_pressed() -> void:
	if _selected_detail.is_empty():
		return
	unequip_requested.emit(str(_selected_detail.get("slot", "")))


func _on_use_pressed() -> void:
	if _selected_detail.is_empty():
		return
	use_requested.emit(str(_selected_detail.get("id", "")))


func _on_sell_pressed() -> void:
	if _selected_detail.is_empty():
		return
	sell_requested.emit(str(_selected_detail.get("id", "")))


func _make_button(text: String, position: Vector2, button_size: Vector2, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.position = position
	button.size = button_size
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("ffe3a0"))
	button.add_theme_color_override("font_disabled_color", Color("786b58"))
	button.add_theme_stylebox_override("normal", _make_panel_style(Color("6e341d"), Color("b88943"), 2, 4))
	button.add_theme_stylebox_override("hover", _make_panel_style(Color("985129"), Color("f0c86a"), 2, 4))
	button.add_theme_stylebox_override("pressed", _make_panel_style(Color("4b2517"), Color("d7a74d"), 2, 4))
	button.add_theme_stylebox_override("disabled", _make_panel_style(Color("35271e"), Color("5b4938"), 1, 4))
	button.pressed.connect(callback)
	_root.add_child(button)
	return button


func _add_label(parent: Control, text: String, position: Vector2, label_size: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = position
	label.size = label_size
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _make_panel_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
