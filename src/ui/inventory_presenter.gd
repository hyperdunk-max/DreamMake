class_name InventoryPresenter
extends RefCounted

## Converts inventory/equipment domain state into immutable, paged UI snapshots.
## The view never needs to inspect Player, Inventory, or the JSON catalogs.

signal view_changed(snapshot: Dictionary)
signal selection_changed(detail: Dictionary)

const DEFAULT_PAGE_SIZE: int = 20
const TYPE_ORDER: Dictionary = {
	"equipment": 0,
	"consumable": 1,
	"material": 2,
}

var page_size: int = DEFAULT_PAGE_SIZE
var current_page: int = 0

var _player: CharacterBody2D
var _items: Array[Dictionary] = []
var _selected_item_id: String = ""
var _last_snapshot: Dictionary = {}


func setup(owner_player: CharacterBody2D, items_per_page: int = DEFAULT_PAGE_SIZE) -> void:
	_player = owner_player
	page_size = maxi(1, items_per_page)
	_connect_domain_events()
	refresh()


func refresh() -> void:
	_rebuild_items()
	var page_count: int = get_page_count()
	current_page = clampi(current_page, 0, page_count - 1)
	if not _selected_item_id.is_empty() and not _contains_item(_selected_item_id):
		_selected_item_id = ""
	_emit_view()
	_emit_selection()


func set_page(page_index: int) -> void:
	var next_page: int = clampi(page_index, 0, get_page_count() - 1)
	if next_page == current_page:
		return
	current_page = next_page
	_selected_item_id = ""
	_emit_view()
	_emit_selection()


func next_page() -> void:
	set_page(current_page + 1)


func previous_page() -> void:
	set_page(current_page - 1)


func select_page_index(local_index: int) -> void:
	var page_items: Array[Dictionary] = _get_current_page_items()
	if local_index < 0 or local_index >= page_items.size():
		_selected_item_id = ""
	else:
		_selected_item_id = str(page_items[local_index].get("id", ""))
	_emit_view()
	_emit_selection()


func get_page_count() -> int:
	return maxi(1, ceili(float(_items.size()) / float(page_size)))


func get_last_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func get_selected_detail() -> Dictionary:
	if _selected_item_id.is_empty():
		return {}
	for item: Dictionary in _items:
		if str(item.get("id", "")) == _selected_item_id:
			return _build_detail(item)
	return {}


func _connect_domain_events() -> void:
	if _player == null:
		return
	if not _player.inventory.item_changed.is_connected(_on_inventory_changed):
		_player.inventory.item_changed.connect(_on_inventory_changed)
	if not _player.equipment_changed.is_connected(_on_equipment_changed):
		_player.equipment_changed.connect(_on_equipment_changed)
	if not _player.role_changed.is_connected(_on_role_changed):
		_player.role_changed.connect(_on_role_changed)


func _rebuild_items() -> void:
	_items.clear()
	if _player == null:
		return
	var all_items: Dictionary = _player.inventory.get_all_items()
	for raw_item_id: Variant in all_items:
		var item_id: String = str(raw_item_id)
		var count: int = _player.inventory.get_count(item_id)
		if count <= 0:
			continue
		var entry: Dictionary = _player.item_data.get_item(item_id)
		var equip_id: String = str(entry.get("equip_id", ""))
		var equip_entry: Dictionary = _player.equipment_data.get_equipment(equip_id)
		_items.append({
			"id": item_id,
			"count": count,
			"type": str(entry.get("type", "")),
			"equip_id": equip_id,
			"name": str(entry.get("name", item_id)),
			"description": str(entry.get("description", "")),
			"quality": str(equip_entry.get("quality", "common")),
			"equipped": _is_equipped(equip_id),
			"icon_source": _get_icon_source(equip_entry),
		})
	_items.sort_custom(_sort_items)


func _sort_items(left: Dictionary, right: Dictionary) -> bool:
	var left_type: String = str(left.get("type", ""))
	var right_type: String = str(right.get("type", ""))
	var left_order: int = int(TYPE_ORDER.get(left_type, 99))
	var right_order: int = int(TYPE_ORDER.get(right_type, 99))
	if left_order != right_order:
		return left_order < right_order
	return str(left.get("id", "")) < str(right.get("id", ""))


func _get_current_page_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index: int = current_page * page_size
	var end_index: int = mini(start_index + page_size, _items.size())
	for index: int in range(start_index, end_index):
		result.append(_items[index].duplicate(true))
	return result


func _emit_view() -> void:
	var page_count: int = get_page_count()
	_last_snapshot = {
		"items": _get_current_page_items(),
		"current_page": current_page,
		"page_count": page_count,
		"total_items": _items.size(),
		"page_size": page_size,
		"selected_item_id": _selected_item_id,
		"can_previous": current_page > 0,
		"can_next": current_page + 1 < page_count,
	}
	view_changed.emit(_last_snapshot.duplicate(true))


func _emit_selection() -> void:
	selection_changed.emit(get_selected_detail())


func _build_detail(item: Dictionary) -> Dictionary:
	var detail: Dictionary = item.duplicate(true)
	var equip_id: String = str(item.get("equip_id", ""))
	var equip_entry: Dictionary = _player.equipment_data.get_equipment(equip_id)
	if not equip_entry.is_empty():
		detail["slot"] = str(equip_entry.get("slot", ""))
		detail["stats"] = Dictionary(equip_entry.get("stats", {})).duplicate(true)
		detail["role_compatible"] = int(equip_entry.get("role_id", 0)) in [0, _player.role_id]
	else:
		detail["slot"] = ""
		detail["stats"] = {}
		detail["role_compatible"] = false
	return detail


func _get_icon_source(equip_entry: Dictionary) -> Dictionary:
	if equip_entry.is_empty():
		return {}
	var icon_path: String = str(equip_entry.get("icon_path", ""))
	if not icon_path.is_empty():
		return {"texture_path": icon_path}
	if _player.animation_profile == null:
		return {}
	var slot: String = str(equip_entry.get("slot", ""))
	var showid: int = int(equip_entry.get("showid", -1))
	if showid < 0:
		return {}
	var atlas: Texture2D
	if slot == "weapon":
		atlas = _player.animation_profile.get_weapon_atlas(showid)
	elif slot == "armor":
		atlas = _player.animation_profile.get_body_atlas(showid, _player.weapon_showid)
	if atlas == null:
		return {}
	return {"atlas": atlas, "frame_size": _player.animation_profile.frame_size}


func _is_equipped(equip_id: String) -> bool:
	if equip_id.is_empty():
		return false
	return _player.equipped.values().has(equip_id)


func _contains_item(item_id: String) -> bool:
	for item: Dictionary in _items:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _on_inventory_changed(_item_id: String, _new_count: int) -> void:
	refresh()


func _on_equipment_changed(_slot: String, _equip_id: String) -> void:
	refresh()


func _on_role_changed(_role_id: int, _display_name: String) -> void:
	refresh()
