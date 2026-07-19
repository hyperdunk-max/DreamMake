extends SceneTree

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(change_scene_to_file("res://scenes/main.tscn") == OK, "Main scene should load.")
	await process_frame
	await process_frame

	var main: Node = current_scene
	var player: CharacterBody2D = main.get_node("Player")
	var inventory_panel: InventoryPanel
	var stats_panel: StatsPanel
	for child: Node in main.get_children():
		if child is InventoryPanel:
			inventory_panel = child
		elif child is StatsPanel:
			stats_panel = child
	_assert(inventory_panel != null, "InventoryPanel should be attached to Main.")
	_assert(stats_panel != null, "StatsPanel should be attached to Main.")
	if inventory_panel == null or stats_panel == null:
		quit(1)
		return

	# Force multiple pages without depending on the current demo seed catalog.
	for index: int in range(27):
		player.inventory.add_item("test_material_%02d" % index, index + 1)
	var presenter: InventoryPresenter = inventory_panel.get_presenter()
	var first_snapshot: Dictionary = presenter.get_last_snapshot()
	_assert(int(first_snapshot.get("page_count", 0)) >= 2, "Inventory should split content into pages.")
	_assert(Array(first_snapshot.get("items", [])).size() == 20, "A full page should expose exactly twenty cells.")

	inventory_panel.open()
	await process_frame
	await process_frame
	var first_metrics: Dictionary = inventory_panel.get_pool_metrics()
	_assert(int(first_metrics.get("created", 0)) == 20, "The first render should create one fixed page of slots.")
	_assert(int(first_metrics.get("active", 0)) == 20, "All twenty pooled slots should be active.")
	presenter.next_page()
	await process_frame
	var second_metrics: Dictionary = inventory_panel.get_pool_metrics()
	_assert(int(second_metrics.get("created", 0)) == 20, "Turning a page must reuse slots instead of creating more.")
	_assert(int(second_metrics.get("active", 0)) == 20, "Recycled slots should fill the next page.")

	var selection_event: Dictionary = {"count": 0, "detail": {}}
	presenter.selection_changed.connect(
		func(detail: Dictionary) -> void:
			selection_event["count"] = int(selection_event["count"]) + 1
			selection_event["detail"] = detail
	)
	presenter.select_page_index(0)
	_assert(int(selection_event["count"]) == 1, "Selecting a slot should publish one detail event.")
	_assert(not Dictionary(selection_event["detail"]).is_empty(), "Selection details should be supplied as a snapshot.")

	# Extracted Flash atlas art should be alpha-cropped, not kept as a 200px cell.
	presenter.set_page(0)
	var equipment_item: Dictionary = {}
	for item_value: Variant in Array(presenter.get_last_snapshot().get("items", [])):
		var item: Dictionary = item_value
		if str(item.get("type", "")) == "equipment":
			equipment_item = item
			break
	_assert(not equipment_item.is_empty(), "The seeded inventory should expose equipment art.")
	if not equipment_item.is_empty():
		var icon: Texture2D = InventoryIconProvider.new().get_item_icon(equipment_item)
		_assert(icon != null, "Equipment should produce a Flash-atlas icon.")
		if icon != null:
			_assert(icon.get_width() < 200 or icon.get_height() < 200, "Equipment icon should trim transparent atlas margins.")

	var stats_events: Dictionary = {"count": 0}
	stats_panel.get_presenter().view_changed.connect(
		func(_snapshot: Dictionary) -> void:
			stats_events["count"] = int(stats_events["count"]) + 1
	)
	_assert(player.equip_item("wukong_weapon_0"), "Seeded weapon should equip.")
	_assert(int(stats_events["count"]) > 0, "Equipment changes should notify the stats view through an event.")
	_assert(player.equip_inventory_item("equip_wukong_weapon_0"), "Owned inventory equipment should equip.")
	_assert(not player.equip_inventory_item("missing_equipment_item"), "Unowned equipment should be rejected.")
	var equipped_count_before: int = player.inventory.get_count("equip_wukong_weapon_0")
	main._on_inventory_sell("equip_wukong_weapon_0")
	_assert(
		player.inventory.get_count("equip_wukong_weapon_0") == equipped_count_before,
		"An equipped item must not be sold before it is removed."
	)
	var potion_count_before: int = player.inventory.get_count("health_potion_small")
	main._on_inventory_use("health_potion_small")
	_assert(player.inventory.get_count("health_potion_small") == potion_count_before - 1, "Using a potion should consume one item.")

	inventory_panel.close()
	stats_panel.open()
	await process_frame
	await process_frame
	var stats_snapshot: Dictionary = stats_panel.get_presenter().get_last_snapshot()
	var body_atlas: Texture2D = stats_snapshot.get("body_atlas") as Texture2D
	var weapon_atlas: Texture2D = stats_snapshot.get("weapon_atlas") as Texture2D
	var frame_size: Vector2i = Vector2i(stats_snapshot.get("frame_size", Vector2i.ZERO))
	_assert(body_atlas != null and weapon_atlas != null, "Stats portrait should use extracted body and weapon atlases.")
	_assert(
		InventoryIconProvider.new().get_character_portrait(body_atlas, weapon_atlas, frame_size) != null,
		"Stats portrait should compose the original Flash layers."
	)
	main._switch_role(2)
	_assert(player.inventory.has_item("equip_tangseng_weapon_0"), "Switching roles should grant that role's starter weapon.")
	_assert(player.inventory.has_item("equip_tangseng_armor_1"), "Switching roles should grant that role's starter armor.")
	_assert(str(player.equipped.get("weapon", "")) == "tangseng_weapon_0", "Role switching should equip the owned starter weapon.")

	if _failed:
		quit(1)
	else:
		print("PASS: paged inventory pooling, Flash icon cropping, and event-driven stats UI.")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
