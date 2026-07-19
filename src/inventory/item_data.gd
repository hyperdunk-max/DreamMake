class_name ItemData
extends RefCounted

## Loads and queries item definitions from a JSON catalog file.
## Items can be consumables, materials, or equipment references.

const DEFAULT_PATH := "res://resources/items/item_data.json"

var _catalog: Dictionary = {}
var _loaded := false


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	_catalog.clear()
	_loaded = false
	if not FileAccess.file_exists(path):
		push_error("ItemData: file not found: %s" % path)
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("ItemData: failed to parse JSON from %s" % path)
		return ERR_PARSE_ERROR
	_catalog = parsed.get("items", {})
	_loaded = true
	return OK


func is_loaded() -> bool:
	return _loaded


## Return the full item entry dictionary, or empty dict if not found.
func get_item(item_id: String) -> Dictionary:
	return _catalog.get(item_id, {})


func is_equipment(item_id: String) -> bool:
	var entry := get_item(item_id)
	return str(entry.get("type", "")) == "equipment"


func is_consumable(item_id: String) -> bool:
	var entry := get_item(item_id)
	return str(entry.get("type", "")) == "consumable"


func is_material(item_id: String) -> bool:
	var entry := get_item(item_id)
	return str(entry.get("type", "")) == "material"


func get_item_type(item_id: String) -> String:
	var entry := get_item(item_id)
	return str(entry.get("type", ""))


## For equipment-type items, returns the referenced equip_id.
func get_equip_id(item_id: String) -> String:
	var entry := get_item(item_id)
	return str(entry.get("equip_id", ""))


## For consumable items, returns the effect dict (e.g. {"heal": 50}).
func get_effect(item_id: String) -> Dictionary:
	var entry := get_item(item_id)
	return entry.get("effect", {})


func get_max_stack(item_id: String) -> int:
	var entry := get_item(item_id)
	return int(entry.get("max_stack", 99))


func is_stackable(item_id: String) -> bool:
	var entry := get_item(item_id)
	return bool(entry.get("stackable", true))


func get_item_name(item_id: String) -> String:
	var entry := get_item(item_id)
	return str(entry.get("name", item_id))


## Return all loaded item ids.
func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _catalog:
		ids.append(str(key))
	return ids
