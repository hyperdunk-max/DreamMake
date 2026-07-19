class_name Inventory
extends RefCounted

## Simple key-value inventory: item_id → count.
## No UI — pure data store.  Signals allow future UI binding.

signal item_changed(item_id: String, new_count: int)
signal item_added(item_id: String, count_added: int)
signal item_removed(item_id: String, count_removed: int)

var _items: Dictionary = {}


## Add items to the inventory.  Returns the new total count.
func add_item(item_id: String, count: int = 1) -> int:
	if count <= 0:
		return get_count(item_id)
	var previous := get_count(item_id)
	var new_count := previous + count
	_items[item_id] = new_count
	item_changed.emit(item_id, new_count)
	item_added.emit(item_id, count)
	return new_count


## Remove items from the inventory.  Returns false if insufficient quantity.
func remove_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return true
	var previous := get_count(item_id)
	if previous < count:
		return false
	var new_count := previous - count
	if new_count <= 0:
		_items.erase(item_id)
	else:
		_items[item_id] = new_count
	item_changed.emit(item_id, new_count if new_count > 0 else 0)
	item_removed.emit(item_id, count)
	return true


## Get the current count of an item (0 if not present).
func get_count(item_id: String) -> int:
	return int(_items.get(item_id, 0))


## Check if we have at least `count` of an item.
func has_item(item_id: String, count: int = 1) -> bool:
	return get_count(item_id) >= count


## Return a copy of the full inventory dict.
func get_all_items() -> Dictionary:
	return _items.duplicate()


## Return all item ids currently in the inventory.
func get_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _items:
		ids.append(str(key))
	return ids


## Clear the inventory completely.
func clear() -> void:
	_items.clear()


## Get the total number of unique item types.
func get_unique_item_count() -> int:
	return _items.size()


## Get the total number of item instances (sum of all counts).
func get_total_item_count() -> int:
	var total := 0
	for count in _items.values():
		total += int(count)
	return total
