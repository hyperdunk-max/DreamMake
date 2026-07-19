class_name EquipmentData
extends RefCounted

## Loads and queries equipment definitions from a JSON catalog file.
## Usage:
##   var equip_data := EquipmentData.new()
##   equip_data.load_from_file("res://resources/equipment/equipment_data.json")
##   var sword := equip_data.get_equipment("wukong_weapon_0")

const DEFAULT_PATH := "res://resources/equipment/equipment_data.json"

var _catalog: Dictionary = {}
var _loaded := false


func load_from_file(path: String = DEFAULT_PATH) -> Error:
	_catalog.clear()
	_loaded = false
	if not FileAccess.file_exists(path):
		push_error("EquipmentData: file not found: %s" % path)
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("EquipmentData: failed to parse JSON from %s" % path)
		return ERR_PARSE_ERROR
	_catalog = parsed.get("equipment", {})
	_loaded = true
	return OK


func is_loaded() -> bool:
	return _loaded


## Return the full equipment entry dictionary, or empty dict if not found.
func get_equipment(equip_id: String) -> Dictionary:
	return _catalog.get(equip_id, {})


## Return all equipment ids for a given role and slot.
## role_id = 0 means "any role" (e.g. universal accessories).
func get_equipment_for_slot(role_id: int, slot: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for equip_id in _catalog:
		var entry: Dictionary = _catalog[equip_id]
		var entry_role := int(entry.get("role_id", 0))
		var entry_slot := str(entry.get("slot", ""))
		if entry_slot == slot and (entry_role == role_id or entry_role == 0):
			results.append(entry)
	return results


## Return all equipment ids for a given role.
func get_equipment_for_role(role_id: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for equip_id in _catalog:
		var entry: Dictionary = _catalog[equip_id]
		if int(entry.get("role_id", 0)) == role_id or int(entry.get("role_id", 0)) == 0:
			results.append(entry)
	return results


## Get the stat bonus dict from an equipment entry (empty dict if missing).
func get_stats(equip_id: String) -> Dictionary:
	var entry := get_equipment(equip_id)
	if entry.is_empty():
		return {}
	return entry.get("stats", {})


## Return all loaded equipment ids.
func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _catalog:
		ids.append(str(key))
	return ids


## Return the full catalog (for debugging).
func get_catalog() -> Dictionary:
	return _catalog.duplicate(true)
