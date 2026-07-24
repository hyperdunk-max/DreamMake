extends SceneTree

const ENEMY_SCENE := preload("res://scenes/enemies/animated_enemy.tscn")
const AURA_PICKUP := preload("res://src/effects/zmxiyou1_aura_pickup.gd")
const WORLD_PICKUP := preload("res://src/effects/zmxiyou1_world_pickup.gd")
const LOOT_CATALOG := preload("res://src/enemies/zmxiyou1_enemy_loot_catalog.gd")
const LOOT_RUNTIME := preload("res://src/enemies/zmxiyou1_enemy_loot_runtime.gd")
const M27_DEFINITION := preload("res://resources/enemies/zmxiyou1_m27_chest.tres")

var _failed := false


class TestPlayer:
	extends CharacterBody2D

	var max_health := 1000
	var max_mana := 600
	var health := 100
	var mana := 50
	var soul := 0
	var score := 0
	var warrior_energy := 0
	var level := 1
	var equipment: Array[StringName] = []

	func heal(amount: int) -> int:
		var previous := health
		health = mini(max_health, health + amount)
		return health - previous

	func restore_mana(amount: int) -> void:
		mana = mini(max_mana, mana + amount)

	func add_source_soul(amount: int) -> void:
		soul += amount
		score += amount

	func add_source_warrior_energy(amount: int) -> bool:
		if warrior_energy + amount > 100:
			return false
		warrior_energy += amount
		return true

	func has_source_equipment(source_name: StringName) -> bool:
		return source_name in equipment

	func try_collect_source_equipment(source_name: StringName) -> bool:
		if equipment.size() >= 25:
			return false
		equipment.append(source_name)
		return true


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_profile_variants()
	await _test_sprite_pack_and_motion()
	await _test_collection_effects()
	await _test_world_pickups()
	await _test_m27_destroy_is_idempotent()
	print("ZMX1 enemy loot test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_profile_variants() -> void:
	var m03 := _profile("zmxiyou1_m03_gorilla_profile.tres")
	var m03_stage_one := LOOT_CATALOG.resolve(m03, 1, 1)
	var m03_other := LOOT_CATALOG.resolve(m03, 1, 2)
	_assert(m03_stage_one.get("exp") == 25, "M03 stage 1-1 EXP should match the source override.")
	_assert(m03_stage_one.get("fall_list", []).is_empty(), "M03 stage 1-1 should have no equipment list.")
	_assert(m03_other.get("exp") == 7, "M03 outside stage 1-1 should use the normal source EXP.")

	var m17 := _profile("zmxiyou1_m17_turtle_profile.tres")
	_assert(LOOT_CATALOG.resolve(m17, 3, 1).get("exp") == 200, "M17 stage 3-1 EXP should match source.")
	_assert(LOOT_CATALOG.resolve(m17, 3, 2).get("exp") == 75, "M17 normal EXP should match source.")

	var m26 := _profile("zmxiyou1_m26_dragon_profile.tres")
	var missing_dhqf := LOOT_CATALOG.resolve(m26, 0, 0, 30, false)
	_assert(missing_dhqf.get("equipment_probability") == 1.0, "M26 should guarantee dhqf when the player does not own it.")
	_assert(missing_dhqf.get("fall_list") == ["dhqf"], "M26 missing-dhqf list should contain only dhqf.")
	var high_level := LOOT_CATALOG.resolve(m26, 0, 0, 21, true)
	_assert(high_level.get("equipment_probability") == 0.1, "M26 level >20 probability should be 10%.")
	_assert(high_level.get("fall_list") == ["qxsh", "jhcz", "ryjgb"], "M26 level >20 list should match source.")
	var low_level := LOOT_CATALOG.resolve(m26, 0, 0, 20, true)
	_assert(low_level.get("equipment_probability") == 0.2, "M26 level <=20 probability should be 20%.")
	_assert(low_level.get("fall_list") == ["zqj", "qld", "bhz", "xwj", "qlp"], "M26 level <=20 list should match source.")

	for file_name: String in ["zmxiyou1_m22_bull_profile.tres", "zmxiyou1_m24_profile.tres"]:
		var data := LOOT_CATALOG.resolve(_profile(file_name), 0, 0)
		_assert(not bool(data.get("drop_aura", true)), "%s should not run BaseMonster.dropAura()." % file_name)


func _test_sprite_pack_and_motion() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var target := TestPlayer.new()
	target.global_position = Vector2(300.0, 0.0)
	world.add_child(target)
	for kind: StringName in [&"red", &"green", &"blue", &"white"]:
		var aura := AURA_PICKUP.new() as Zmxiyou1AuraPickup
		aura.setup(kind, target, 5, 1234)
		world.add_child(aura)
		var sprite := aura.get_node("AnimatedSprite2D") as AnimatedSprite2D
		_assert(sprite != null, "%s aura should create an AnimatedSprite2D." % kind)
		_assert(sprite.sprite_frames.get_frame_count(&"aura") == 19, "%s aura should retain all 19 sprite-pack frames." % kind)
		_assert(sprite.sprite_frames.get_animation_speed(&"aura") == 24.0, "%s aura should animate at the source 24 Hz." % kind)
		aura.queue_free()
	await process_frame

	var aura := AURA_PICKUP.new() as Zmxiyou1AuraPickup
	aura.setup(&"red", target, 5, 4567)
	world.add_child(aura)
	aura.global_position = Vector2.ZERO
	for _tick: int in 20:
		aura.source_tick()
	_assert(aura.get_motion_state_name() == &"wait", "Aura should wait for exactly 20 complete source ticks.")
	_assert(aura.global_position == Vector2.ZERO, "Aura should not move during the 20-tick wait.")
	aura.source_tick()
	_assert(aura.get_motion_state_name() == &"rise", "Aura should begin its source rise on tick 21.")
	for _tick: int in 23:
		aura.source_tick()
	_assert(aura.get_motion_state_name() == &"rise", "Aura rise should last 24 source ticks.")
	_assert(aura.global_position.y < -29.0 and aura.global_position.y > -51.0, "Aura rise should remain within the source 30-50 px range.")
	aura.source_tick()
	_assert(aura.get_motion_state_name() == &"homing", "Aura should home after the 24-tick rise.")
	var speed_before := aura.get_source_speed_px_per_tick()
	aura.source_tick()
	_assert(is_equal_approx(aura.get_source_speed_px_per_tick(), minf(20.0, speed_before + 2.0)), "Aura homing speed should accelerate by 2 px/tick.")
	for _tick: int in 20:
		if not is_instance_valid(aura) or aura.is_queued_for_deletion():
			break
		aura.source_tick()
	if is_instance_valid(aura) and not aura.is_queued_for_deletion():
		_assert(aura.get_source_speed_px_per_tick() <= 20.0, "Aura homing speed should cap at 20 px/tick.")
	world.queue_free()
	await process_frame


func _test_collection_effects() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var target := TestPlayer.new()
	target.global_position = Vector2.ZERO
	world.add_child(target)

	await _collect_immediately(world, target, &"red", 7)
	_assert(target.soul == 7 and target.score == 7, "Red aura should add both source soul and score.")
	await _collect_immediately(world, target, &"green", 50)
	_assert(target.health == 150, "Green aura should heal by its source power.")
	await _collect_immediately(world, target, &"blue", 30)
	_assert(target.mana == 80, "Blue aura should restore mana by its source power.")
	target.warrior_energy = 95
	await _collect_immediately(world, target, &"white", 5)
	_assert(target.warrior_energy == 100, "White aura should add 5 warrior energy up to 100.")
	target.warrior_energy = 98
	await _collect_immediately(world, target, &"white", 5)
	_assert(target.warrior_energy == 98, "White aura should not add energy when the result would exceed 100.")
	world.queue_free()
	await process_frame


func _collect_immediately(world: Node2D, target: TestPlayer, kind: StringName, power: int) -> void:
	var aura := AURA_PICKUP.new() as Zmxiyou1AuraPickup
	aura.setup(kind, target, power, 99)
	world.add_child(aura)
	aura.global_position = target.global_position
	for _tick: int in 100:
		if not is_instance_valid(aura) or aura.is_queued_for_deletion():
			break
		aura.source_tick()
	await process_frame


func _test_m27_destroy_is_idempotent() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var target := TestPlayer.new()
	target.add_to_group(&"players")
	world.add_child(target)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M27_DEFINITION
	enemy.spawn_id = &"loot_idempotence_test"
	world.add_child(enemy)
	await process_frame
	enemy.set_physics_process(false)
	enemy.call(&"_notify_source_before_despawn")
	var first_count := world.get_tree().get_nodes_in_group(&"zmxiyou1_aura_pickups").size()
	enemy.call(&"_notify_source_before_despawn")
	var second_count := world.get_tree().get_nodes_in_group(&"zmxiyou1_aura_pickups").size()
	_assert(enemy.has_spawned_source_loot(), "M27 destroy should trigger its source loot path.")
	_assert(first_count >= 2, "M27 destroy should create the guaranteed 2-4 red auras.")
	_assert(second_count == first_count, "M27 destroy should generate source loot only once.")
	world.queue_free()
	await process_frame


func _test_world_pickups() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var target := TestPlayer.new()
	world.add_child(target)

	var small_hp := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	_assert(small_hp.setup_medicine(&"small_hp"), "SmallHP setup should resolve its source pickup.")
	world.add_child(small_hp)
	small_hp.set_physics_process(false)
	_assert(small_hp.get_source_frame_count() == 1, "Medicine should load its one-frame sprite pack.")
	var initial_y := small_hp.global_position.y
	small_hp.source_tick()
	_assert(is_equal_approx(small_hp.global_position.y, initial_y + 4.0), "World pickup should start at the source 4 px/tick fall speed.")
	_assert(is_equal_approx(small_hp.get_source_vertical_speed_px_per_tick(), 5.5), "World pickup gravity should be 1.5 px/tick squared.")
	_assert(small_hp.try_collect(target), "SmallHP should be collected by a compatible Godot body.")
	_assert(target.health == 200, "SmallHP should restore 100 HP.")
	_assert(small_hp.has_been_collected(), "Collected medicine should enter its 0.8-second source tween.")

	var big_hp := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	big_hp.setup_medicine(&"big_hp")
	world.add_child(big_hp)
	big_hp.set_physics_process(false)
	_assert(big_hp.try_collect(target), "BigHP should collect.")
	_assert(target.health == 400, "BigHP should restore 200 HP.")
	var small_mp := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	small_mp.setup_medicine(&"small_mp")
	world.add_child(small_mp)
	small_mp.set_physics_process(false)
	_assert(small_mp.try_collect(target), "SmallMP should collect.")
	_assert(target.mana == 150, "SmallMP should restore 100 MP.")

	var expiring := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	expiring.setup_equipment(&"ccjs")
	world.add_child(expiring)
	expiring.set_physics_process(false)
	expiring.global_position.y = -100000.0
	for _tick: int in 240:
		expiring.source_tick()
	_assert(not expiring.is_queued_for_deletion(), "Ordinary equipment should remain for 240 complete source ticks.")
	expiring.source_tick()
	_assert(expiring.is_queued_for_deletion(), "Ordinary equipment should expire on the source post-increment tick 241.")

	var persistent_drop := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	persistent_drop.setup_equipment(&"dslj")
	world.add_child(persistent_drop)
	persistent_drop.set_physics_process(false)
	persistent_drop.global_position.y = -100000.0
	for _tick: int in 300:
		persistent_drop.source_tick()
	_assert(persistent_drop.is_source_persistent(), "Source boss-list equipment should be persistent.")
	_assert(not persistent_drop.is_queued_for_deletion(), "Persistent source equipment should not time out.")

	var bag_limited := WORLD_PICKUP.new() as Zmxiyou1WorldPickup
	bag_limited.setup_equipment(&"dhqf")
	world.add_child(bag_limited)
	bag_limited.set_physics_process(false)
	target.equipment.clear()
	for index: int in 25:
		target.equipment.append(StringName("full_%d" % index))
	_assert(not bag_limited.try_collect(target), "A full 25-slot source equipment bag should leave the pickup in the world.")
	_assert(not bag_limited.has_been_collected(), "Rejected equipment must remain collectible.")
	target.equipment.clear()
	_assert(bag_limited.try_collect(target), "Equipment should collect once source bag capacity is available.")
	_assert(target.equipment == [&"dhqf"], "Equipment pickup should retain its source name.")

	var equipment_root := "res://assets/selected/zmxiyou1/monsters/shared/pickups/equipment"
	var equipment_ids := DirAccess.get_directories_at(equipment_root)
	_assert(equipment_ids.size() == 41, "All 41 reviewed source equipment icons should be selected.")
	for equipment_id: String in equipment_ids:
		var atlas_root := "%s/%s" % [equipment_root, equipment_id]
		_assert(FileAccess.file_exists(atlas_root + "/sprite.png"), "%s needs sprite.png." % equipment_id)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(atlas_root + "/sprite.json"))
		_assert(parsed is Dictionary and int(parsed.get("meta", {}).get("frameCount", 0)) == 1, "%s should be a one-frame sprite pack." % equipment_id)

	# Verify a source-special M26 drop reaches the Area2D runtime, not just the catalog.
	var m26_data := LOOT_CATALOG.resolve(_profile("zmxiyou1_m26_dragon_profile.tres"), 0, 0, 30, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13579
	var spawned := LOOT_RUNTIME.spawn_drop_set(world, Vector2.ZERO, target, m26_data, rng)
	var m26_equipment := spawned.get("equipment") as Zmxiyou1WorldPickup
	_assert(m26_equipment != null and m26_equipment.source_name == &"dhqf", "M26 should spawn guaranteed dhqf through the world-pickup runtime.")

	world.queue_free()
	await process_frame


func _profile(file_name: String) -> EnemyAnimationProfile:
	return load("res://resources/enemies/animations/" + file_name) as EnemyAnimationProfile


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
