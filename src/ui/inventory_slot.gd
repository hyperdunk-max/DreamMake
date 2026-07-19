class_name InventorySlot
extends Panel

## Reusable backpack cell. It only renders a supplied snapshot and emits input.

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)

const SLOT_SIZE: Vector2 = Vector2(64, 64)
const ICON_SIZE: Vector2 = Vector2(52, 52)
const QUALITY_COLORS: Dictionary = {
	"common": Color("9a8358"),
	"excellent": Color("55c85a"),
	"fine": Color("54a9e8"),
	"epic": Color("b76be3"),
	"evil": Color("dc5748"),
	"legendary": Color("f1bd43"),
}

var slot_index: int = -1
var item_id: String = ""
var count: int = 0

var _icon: TextureRect
var _count_label: Label
var _equipped_label: Label
var _selection_border: StyleBoxFlat
var _normal_border: StyleBoxFlat
var _selected: bool = false
var _ready_complete: bool = false


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_normal_border = StyleBoxFlat.new()
	_normal_border.bg_color = Color("21160f")
	_normal_border.border_color = QUALITY_COLORS["common"]
	_normal_border.set_border_width_all(2)
	_normal_border.set_corner_radius_all(3)

	_selection_border = StyleBoxFlat.new()
	_selection_border.bg_color = Color("3b2812")
	_selection_border.border_color = Color("ffd45c")
	_selection_border.set_border_width_all(3)
	_selection_border.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", _normal_border)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size = ICON_SIZE
	_icon.position = (SLOT_SIZE - ICON_SIZE) * 0.5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count_label = Label.new()
	_count_label.position = Vector2(2, SLOT_SIZE.y - 19)
	_count_label.size = Vector2(SLOT_SIZE.x - 5, 17)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_count_label.add_theme_constant_override("outline_size", 3)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	_equipped_label = Label.new()
	_equipped_label.text = "装"
	_equipped_label.position = Vector2(3, 3)
	_equipped_label.size = Vector2(20, 18)
	_equipped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_equipped_label.add_theme_font_size_override("font_size", 12)
	_equipped_label.add_theme_color_override("font_color", Color("fff0a2"))
	_equipped_label.add_theme_color_override("font_outline_color", Color("5a2d09"))
	_equipped_label.add_theme_constant_override("outline_size", 3)
	_equipped_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_equipped_label)
	_ready_complete = true
	clear()


func bind(item: Dictionary, icon_texture: Texture2D) -> void:
	item_id = str(item.get("id", ""))
	count = int(item.get("count", 0))
	_icon.texture = icon_texture
	_count_label.text = str(count) if count > 1 else ""
	_count_label.visible = count > 1
	_equipped_label.visible = bool(item.get("equipped", false))
	var quality: String = str(item.get("quality", "common"))
	_normal_border.border_color = Color(QUALITY_COLORS.get(quality, QUALITY_COLORS["common"]))
	tooltip_text = str(item.get("name", item_id))
	set_selected(false)


func set_item(id: String, item_count: int, icon_texture: Texture2D = null) -> void:
	bind({"id": id, "count": item_count}, icon_texture)


func clear() -> void:
	item_id = ""
	count = 0
	tooltip_text = ""
	if not _ready_complete:
		return
	_icon.texture = null
	_count_label.text = ""
	_count_label.visible = false
	_equipped_label.visible = false
	_normal_border.border_color = Color("5b4630")
	set_selected(false)


func reset_for_pool() -> void:
	clear()
	slot_index = -1
	visible = false


func set_selected(selected: bool) -> void:
	_selected = selected
	if _ready_complete:
		add_theme_stylebox_override("panel", _selection_border if selected else _normal_border)


func is_selected() -> bool:
	return _selected


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			slot_clicked.emit(slot_index)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			slot_right_clicked.emit(slot_index)


func _on_mouse_entered() -> void:
	if not _selected:
		modulate = Color(1.12, 1.08, 0.92, 1.0)


func _on_mouse_exited() -> void:
	modulate = Color.WHITE
