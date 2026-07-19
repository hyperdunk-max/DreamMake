class_name InventorySlotPool
extends RefCounted

## Reuses the same InventorySlot nodes when a page is turned.

var _available: Array[InventorySlot] = []
var _active: Array[InventorySlot] = []
var _created_count: int = 0


func acquire(parent: Control, slot_index: int, slot_position: Vector2, click_callback: Callable) -> InventorySlot:
	var slot: InventorySlot
	if _available.is_empty():
		slot = InventorySlot.new()
		_created_count += 1
	else:
		slot = _available.pop_back()
	if slot.get_parent() != parent:
		parent.add_child(slot)
	slot.slot_index = slot_index
	slot.position = slot_position
	slot.visible = true
	if not slot.slot_clicked.is_connected(click_callback):
		slot.slot_clicked.connect(click_callback)
	_active.append(slot)
	return slot


func release_all() -> void:
	for slot: InventorySlot in _active:
		slot.reset_for_pool()
		var parent: Node = slot.get_parent()
		if parent != null:
			parent.remove_child(slot)
		_available.append(slot)
	_active.clear()


func get_created_count() -> int:
	return _created_count


func get_active_count() -> int:
	return _active.size()


func get_available_count() -> int:
	return _available.size()
