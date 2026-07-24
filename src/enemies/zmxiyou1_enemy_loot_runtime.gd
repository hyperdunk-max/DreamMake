class_name Zmxiyou1EnemyLootRuntime
extends RefCounted

const AURA_PICKUP := preload("res://src/effects/zmxiyou1_aura_pickup.gd")
const WORLD_PICKUP := preload("res://src/effects/zmxiyou1_world_pickup.gd")


static func spawn_drop_set(
	parent: Node,
	origin: Vector2,
	target: Node2D,
	profile_data: Dictionary,
	rng: RandomNumberGenerator,
	equipment_origin_y_offset := -60.0
) -> Dictionary:
	var result := {"medicine": null, "equipment": null, "auras": []}
	if parent == null or target == null:
		return result
	# BaseMonster.dropAura() calls these in this exact order.
	var medicine_kind := Zmxiyou1EnemyLootCatalog.roll_medicine(rng)
	if medicine_kind != &"":
		var medicine := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
		if medicine.setup_medicine(medicine_kind):
			parent.add_child(medicine)
			medicine.global_position = origin - Vector2(0.0, medicine.get_visual_size().y)
			result["medicine"] = medicine

	var equipment_name := Zmxiyou1EnemyLootCatalog.roll_equipment(profile_data, rng)
	if equipment_name != &"":
		var equipment := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
		if equipment.setup_equipment(equipment_name):
			parent.add_child(equipment)
			equipment.global_position = origin + Vector2(0.0, equipment_origin_y_offset)
			result["equipment"] = equipment

	result["auras"] = spawn_aura_set(parent, origin, target, profile_data, rng)
	return result


static func spawn_equipment(
	parent: Node,
	origin: Vector2,
	source_name: StringName,
	force_persistent := false
) -> Zmxiyou1WorldPickup:
	if parent == null or source_name == &"":
		return null
	var pickup := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	if not pickup.setup_equipment(source_name, force_persistent):
		return null
	parent.add_child(pickup)
	pickup.global_position = origin
	return pickup


static func spawn_aura_set(
	parent: Node,
	origin: Vector2,
	target: Node2D,
	profile_data: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Zmxiyou1AuraPickup]:
	var result: Array[Zmxiyou1AuraPickup] = []
	if parent == null or target == null or not bool(profile_data.get("drop_aura", true)):
		return result
	_spawn_kind(result, parent, origin, target, &"red", rng.randi_range(2, 4), 10.0, int(profile_data.get("gxp", 0)), rng)
	_spawn_kind(
		result, parent, origin, target, &"green",
		Zmxiyou1EnemyLootCatalog.roll_bonus_count(rng), 20.0,
		maxi(10, _target_maximum(target, &"health") / 20), rng
	)
	_spawn_kind(
		result, parent, origin, target, &"blue",
		Zmxiyou1EnemyLootCatalog.roll_bonus_count(rng), 30.0,
		maxi(10, _target_maximum(target, &"mana") / 20), rng
	)
	_spawn_kind(
		result, parent, origin, target, &"white",
		Zmxiyou1EnemyLootCatalog.roll_bonus_count(rng), 40.0, 5, rng
	)
	return result


static func _spawn_kind(
	result: Array[Zmxiyou1AuraPickup],
	parent: Node,
	origin: Vector2,
	target: Node2D,
	kind: StringName,
	count: int,
	spread: float,
	power: int,
	rng: RandomNumberGenerator
) -> void:
	for _index: int in count:
		var pickup := AURA_PICKUP.new() as Zmxiyou1AuraPickup
		pickup.setup(kind, target, power, rng.randi())
		parent.add_child(pickup)
		pickup.global_position = origin + Vector2(
			(rng.randf() - 0.5) * spread,
			(rng.randf() - 0.5) * spread
		)
		result.append(pickup)


static func _target_maximum(target: Node, kind: StringName) -> int:
	var stats: Variant = target.get("stats")
	if stats != null:
		var method := &"get_effective_max_health" if kind == &"health" else &"get_effective_max_mana"
		if stats.has_method(method):
			return int(stats.call(method))
	var property_name := &"max_health" if kind == &"health" else &"max_mana"
	var value: Variant = target.get(property_name)
	return int(value) if value != null else 0
