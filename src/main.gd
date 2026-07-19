extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $TrainingEnemy
@onready var hud: CanvasLayer = $HUD

@export var playable_roles: Array[Resource] = []

var _roles_by_id: Dictionary = {}
var _inventory_panel: InventoryPanel
var _stats_panel: StatsPanel


func _ready() -> void:
	for role_resource in playable_roles:
		var definition := role_resource as RoleDefinition
		if definition != null:
			_roles_by_id[definition.role_id] = definition

	# Load equipment and item data
	var eq_error: Error = player.equipment_data.load_from_file("res://resources/equipment/equipment_data.json")
	if eq_error != OK:
		push_warning("Failed to load equipment data.")
	var item_error: Error = player.item_data.load_from_file("res://resources/items/item_data.json")
	if item_error != OK:
		push_warning("Failed to load item data.")

	# Seed default inventory
	_seed_default_inventory()

	player.health_changed.connect(hud.set_player_health)
	player.mana_changed.connect(hud.set_player_mana)
	player.weapon_changed.connect(hud.set_weapon)
	player.body_changed.connect(hud.set_body)
	player.role_changed.connect(hud.set_role)
	player.equipment_changed.connect(_on_player_equipment_changed)
	enemy.health_changed.connect(hud.set_enemy_health)
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.set_attack_target(player)

	var effective_max_health: int = player.stats.get_effective_max_health()
	var effective_max_mana: int = player.stats.get_effective_max_mana()
	player.health_changed.emit(player.health, effective_max_health)
	player.mana_changed.emit(player.mana, effective_max_mana)
	hud.set_weapon(player.weapon_showid, player.get_weapon_name())
	hud.set_body(player.body_showid, player.get_body_name())
	hud.set_role(player.role_id, player.role_definition.display_name)
	enemy.health_changed.emit(enemy.health, enemy.max_health)

	# Debug: print inventory and equipment state
	print("[DreamMake] Equipment data loaded: %d entries." % player.equipment_data.get_all_ids().size())
	print("[DreamMake] Item data loaded: %d entries." % player.item_data.get_all_ids().size())
	print("[DreamMake] Inventory: ", player.inventory.get_all_items())
	print("[DreamMake] Equipped: ", player.equipped)
	print("[DreamMake] Effective stats: HP=%d/%d MP=%d/%d ATK=%d DEF=%d" % [
		player.health, effective_max_health,
		player.mana, effective_max_mana,
		player.stats.get_effective_attack(),
		player.stats.get_effective_defense(),
	])
	_update_hud_stats()
	_setup_ui_panels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("test_enemy_attack"):
		if not enemy.request_test_attack():
			hud.show_message("请等待训练木妖完成当前攻击")
	elif event.is_action_pressed("inventory"):
		_toggle_inventory()
	elif event.is_action_pressed("stats_panel"):
		_toggle_stats_panel()
	else:
		for role_number in range(1, 5):
			if event.is_action_pressed("role_%d" % role_number):
				_switch_role(role_number)
				break


func _switch_role(role_id: int) -> void:
	var definition: RoleDefinition = _roles_by_id.get(role_id)
	if definition == null:
		return
	if player.configure_role(definition):
		_ensure_role_starter_items(role_id)
		_auto_equip_defaults()
		hud.show_message("已切换：%s" % definition.display_name)
		_update_hud_stats()


func _on_player_equipment_changed(_slot: String, _equip_id: String) -> void:
	_update_hud_stats()


func _update_hud_stats() -> void:
	hud.set_stats(
		player.stats.get_effective_attack(),
		player.stats.get_effective_defense(),
		player.stats.get_effective_crit_rate(),
		player.stats.get_effective_dodge_rate()
	)


func _on_enemy_defeated() -> void:
	hud.show_message("训练完成！按 R 重新挑战")


func _seed_default_inventory() -> void:
	# Give the active character default equipment and a few consumables.
	_ensure_role_starter_items(player.role_id)
	player.inventory.add_item("health_potion_small", 5)
	player.inventory.add_item("mana_potion_small", 3)
	player.inventory.add_item("material_sandalwood", 10)

	# Auto-equip default weapon and armor for current role
	_auto_equip_defaults()


func _ensure_role_starter_items(role_id: int) -> void:
	var role_prefix: String = {
		1: "wukong", 2: "tangseng", 3: "bajie", 4: "shaseng",
	}.get(role_id, "")
	if role_prefix.is_empty():
		return
	for suffix: String in ["weapon_0", "armor_1"]:
		var item_id: String = "equip_%s_%s" % [role_prefix, suffix]
		if not player.item_data.get_item(item_id).is_empty() and not player.inventory.has_item(item_id):
			player.inventory.add_item(item_id, 1)


func _auto_equip_defaults() -> void:
	var role_prefix := ""
	match player.role_id:
		1: role_prefix = "wukong"
		2: role_prefix = "tangseng"
		3: role_prefix = "bajie"
		4: role_prefix = "shaseng"
		_: return

	var weapon_id := "%s_weapon_%d" % [role_prefix, player.weapon_showid]
	var armor_id := "%s_armor_%d" % [role_prefix, player.body_showid]

	if player.equipment_data.get_equipment(weapon_id).is_empty():
		# Fall back to weapon showid 0
		weapon_id = "%s_weapon_0" % role_prefix
	if player.equipment_data.get_equipment(armor_id).is_empty():
		armor_id = "%s_armor_%d" % role_prefix
		if player.equipment_data.get_equipment(armor_id).is_empty():
			# Fall back to armor showid 1 or 0
			armor_id = "%s_armor_1" % role_prefix
			if player.equipment_data.get_equipment(armor_id).is_empty():
				armor_id = "%s_armor_0" % role_prefix

	if not player.equipment_data.get_equipment(weapon_id).is_empty():
		player.equip_item(weapon_id)
	if not player.equipment_data.get_equipment(armor_id).is_empty():
		player.equip_item(armor_id)


func _setup_ui_panels() -> void:
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.setup(player)
	_inventory_panel.equip_requested.connect(_on_inventory_equip)
	_inventory_panel.unequip_requested.connect(_on_inventory_unequip)
	_inventory_panel.use_requested.connect(_on_inventory_use)
	_inventory_panel.sell_requested.connect(_on_inventory_sell)
	add_child(_inventory_panel)

	_stats_panel = StatsPanel.new()
	_stats_panel.setup(player)
	add_child(_stats_panel)


func _toggle_inventory() -> void:
	if _inventory_panel == null:
		return
	var opening := not _inventory_panel.visible
	if opening:
		_inventory_panel.open()
	else:
		_inventory_panel.close()


func _toggle_stats_panel() -> void:
	if _stats_panel == null:
		return
	var opening := not _stats_panel.visible
	if opening:
		_stats_panel.open()
	else:
		_stats_panel.close()


func _on_inventory_equip(item_id: String, _equip_id: String) -> void:
	if not player.equip_inventory_item(item_id):
		hud.show_message("该装备当前无法使用")
	_update_hud_stats()


func _on_inventory_unequip(slot: String) -> void:
	player.unequip_slot(slot)
	_update_hud_stats()


func _on_inventory_use(item_id: String) -> void:
	var item_name: String = player.item_data.get_item_name(item_id)
	if player.use_consumable(item_id):
		hud.show_message("使用: %s" % item_name)
	else:
		hud.show_message("当前无法使用该物品")


func _on_inventory_sell(item_id: String) -> void:
	if player.inventory.has_item(item_id):
		var equip_id: String = player.item_data.get_equip_id(item_id)
		if not equip_id.is_empty() and player.equipped.values().has(equip_id):
			hud.show_message("请先卸下该装备")
			return
		var item_name: String = player.item_data.get_item_name(item_id)
		player.inventory.remove_item(item_id, 1)
		hud.show_message("出售: %s" % item_name)
		_update_hud_stats()


func _draw() -> void:
	# Placeholder art is intentionally procedural. Extracted art will replace this
	# layer without coupling game logic to individual source images.
	draw_rect(Rect2(0, 0, 940, 590), Color("101b31"))
	draw_circle(Vector2(790, 105), 58, Color("f1cf79"))
	draw_circle(Vector2(772, 90), 58, Color("101b31"))

	var far_mountains := PackedVector2Array([
		Vector2(0, 380), Vector2(100, 270), Vector2(190, 360),
		Vector2(310, 235), Vector2(450, 370), Vector2(580, 260),
		Vector2(710, 355), Vector2(840, 245), Vector2(940, 340), Vector2(940, 520), Vector2(0, 520)
	])
	draw_colored_polygon(far_mountains, Color("223858"))

	var near_mountains := PackedVector2Array([
		Vector2(0, 465), Vector2(145, 330), Vector2(260, 450),
		Vector2(410, 315), Vector2(565, 458), Vector2(725, 325),
		Vector2(940, 445), Vector2(940, 540), Vector2(0, 540)
	])
	draw_colored_polygon(near_mountains, Color("172943"))
	draw_rect(Rect2(0, 515, 940, 75), Color("4a3b2c"))
	draw_rect(Rect2(0, 515, 940, 8), Color("95734b"))
	for x in range(0, 940, 55):
		draw_line(Vector2(x, 535), Vector2(x + 25, 585), Color("33291f"), 3)
