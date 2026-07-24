extends SceneTree

const ENEMY_SCENE := preload("res://scenes/enemies/animated_enemy.tscn")
const M24_DEFINITION := preload("res://resources/enemies/zmxiyou1_m24_bull_demon_king.tres")
const M24_CONTROLLER := preload("res://src/enemies/zmxiyou1_m24_controller.gd")

var _failed := false


class TestPlayer:
	extends CharacterBody2D

	var health := 100000
	var hits: Array[Dictionary] = []
	var shape_node: CollisionShape2D

	func take_hit(
		damage: int, impulse: Vector2, damage_kind := &"physical", source: Object = null
	) -> void:
		health = maxi(0, health - damage)
		hits.append({
			"damage": damage,
			"impulse": impulse,
			"damage_kind": StringName(damage_kind),
			"source": source,
		})


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_profile_and_source_values()
	var world := Node2D.new()
	root.add_child(world)
	var player := _create_player(world)
	await _test_heart_window(world, player)
	await _test_hands(world, player)
	await _test_fire(world, player)
	await _test_death_fade(world, player)
	world.queue_free()
	await process_frame
	print("ZMX1 M24 composite boss test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_profile_and_source_values() -> void:
	_assert(M24_DEFINITION.validate().is_empty(), "M24 definition should validate.")
	_assert(M24_DEFINITION.property_template.max_health == 200000, "M24 should preserve source HP 200000.")
	_assert(M24_DEFINITION.property_template.defense == 0, "M24 should preserve source defense 0.")
	var profile := M24_DEFINITION.animation_profile
	for action: StringName in [&"idle", &"eyes", &"background", &"attack1", &"attack2", &"death"]:
		_assert(profile.actions.has(action), "M24 composite profile should expose %s." % action)
	_assert(int(profile.get_spec(&"idle").get("frame_count", 0)) == 23, "M24 Heart should preserve 23 frames.")
	_assert(int(profile.get_spec(&"eyes").get("frame_count", 0)) == 25, "M24 Eyes should preserve 25 frames.")
	_assert(int(profile.get_spec(&"attack2").get("frame_count", 0)) == 40, "M24 Fire should preserve all 40 frames.")
	_assert(
		Vector2i(profile.get_spec(&"attack2").get("hitbox_frame_range", Vector2i.ZERO)) == Vector2i(24, 35),
		"M24 Fire should only collide on source currentFrame 25..36."
	)
	var hand_attack := EnemyCombatCatalog.resolve_attack(profile, &"attack1")
	_assert(int(hand_attack.get("damage", 0)) == 400, "M24 Hands should preserve source power 400.")
	_assert(int(hand_attack.get("hit_max_count", 0)) == 2, "M24 Hands should retain source hitMaxCount 2 metadata.")
	_assert(StringName(hand_attack.get("damage_kind", &"")) == &"magic", "M24 Hands should deal magic damage.")
	var fire_attack := EnemyCombatCatalog.resolve_attack(profile, &"attack2")
	_assert(int(fire_attack.get("damage", 0)) == 300, "M24 Fire should preserve source power 300.")
	_assert(int(fire_attack.get("hit_max_count", 0)) == 30, "M24 Fire should retain source hitMaxCount 30 metadata.")


func _test_heart_window(world: Node2D, player: TestPlayer) -> void:
	player.global_position = Vector2(-2000, -2000)
	var enemy := await _spawn_enemy(world, &"m24_heart", Vector2.ZERO)
	var controller := enemy.get_source_controller() as M24_CONTROLLER
	_assert(controller != null, "M24 should instantiate its source controller.")
	if controller == null:
		enemy.queue_free()
		return
	var hurt_shape := enemy.collision_shape.shape as RectangleShape2D
	_assert(
		hurt_shape != null and hurt_shape.size.is_equal_approx(Vector2(83.226, 159.9527)),
		"M24 should replace its Flash colipse with the reviewed Godot rectangle."
	)
	_assert(
		enemy.collision_shape.position.is_equal_approx(Vector2(18.15, 141.0)),
		"M24 hurtbox should preserve the source colipse transform."
	)
	var health_before := enemy.health
	_assert(controller.get_heart_phase() == &"hidden", "M24 Heart should start hidden.")
	enemy.take_hit_from(500, Vector2.ZERO, &"physical", player)
	_assert(enemy.health == health_before, "Hidden M24 Heart must reject physical and magic hits.")
	var hidden_ticks := 0
	while controller.get_heart_phase() == &"hidden" and hidden_ticks < 9 * 24 + 1:
		controller.source_tick(hidden_ticks)
		hidden_ticks += 1
	_assert(hidden_ticks >= 5 * 24 and hidden_ticks <= 9 * 24, "Initial Heart hide time should be 5..9 source seconds.")
	_assert(controller.get_heart_phase() == &"fading_in", "Heart should enter its source two-second fade-in.")
	for tick in 47:
		controller.source_tick(hidden_ticks + tick)
	_assert(controller.get_heart_phase() == &"fading_in", "Heart must remain invulnerable through fade-in tick 47.")
	_assert(controller.get_heart_alpha() < 1.0, "Heart alpha must stay below one before fade-in completes.")
	controller.source_tick(hidden_ticks + 47)
	_assert(controller.get_heart_phase() == &"vulnerable", "Heart should become vulnerable on fade-in tick 48.")
	_assert(is_equal_approx(controller.get_heart_alpha(), 1.0), "Vulnerable Heart alpha should be exactly one.")
	enemy.take_hit_from(500, Vector2.ZERO, &"physical", player)
	_assert(enemy.health == health_before - 500, "Visible Heart should receive damage normally.")
	_assert(enemy.get_state_name() == &"idle", "M24 should keep its wait state when the Heart is hit.")
	enemy.queue_free()
	await process_frame


func _test_hands(world: Node2D, player: TestPlayer) -> void:
	var player_shape := player.shape_node.shape as RectangleShape2D
	player_shape.size = Vector2(2000, 30)
	player.global_position = Vector2(500, 144)
	player.hits.clear()
	player.health = 100000
	var enemy := await _spawn_enemy(world, &"m24_hands", Vector2(500, 0))
	var controller := enemy.get_source_controller() as M24_CONTROLLER
	for tick in 47:
		controller.source_tick(tick)
	_assert(controller.get_hand_states().is_empty(), "M24 Hands should not exist before the two-second BG intro finishes.")
	controller.source_tick(47)
	var hands := controller.get_hand_states()
	_assert(hands.size() == 2, "M24 should create two independent Hands after the BG intro.")
	if hands.size() == 2:
		_assert(
			is_equal_approx(float(hands[1]["x"]) - float(hands[0]["x"]), 600.0),
			"M24 Hands should retain their source ±300 starting separation."
		)
	var shake_count := [0]
	controller.screen_shake_requested.connect(func(_strength: float) -> void: shake_count[0] += 1)
	var ticks := 0
	while player.hits.is_empty() and ticks < 180:
		controller.source_tick(48 + ticks)
		ticks += 1
	_assert(not player.hits.is_empty(), "A descending Hand should hit through its visible-pixel Godot rectangle.")
	if not player.hits.is_empty():
		_assert(int(player.hits[0]["damage"]) == 400, "Hand collision should deal source power 400.")
		_assert(player.hits[0]["damage_kind"] == &"magic", "Hand collision should remain magic damage.")
		_assert(Vector2(player.hits[0]["impulse"]).y == -120.0, "Hand vertical knockback should convert -5 px/tick to -120 px/s.")
	for tick in 30:
		controller.source_tick(228 + tick)
	_assert(shake_count[0] > 0, "A Hand at y>=126 should request the source strength-10 screen shake.")
	_assert(player.hits.size() == 1, "Both Hands should share the current source attack id for one hit per player.")
	enemy.queue_free()
	await process_frame
	player_shape.size = Vector2(36, 58)


func _test_fire(world: Node2D, player: TestPlayer) -> void:
	player.global_position = Vector2(-2000, -2000)
	player.hits.clear()
	player.health = 100000
	var enemy := await _spawn_enemy(world, &"m24_fire", Vector2.ZERO)
	var controller := enemy.get_source_controller() as M24_CONTROLLER
	var source_frames: Array[int] = []
	controller.hazard_hit.connect(
		func(_target: Node2D, action: StringName, source_frame: int) -> void:
			if action == &"attack2":
				source_frames.append(source_frame)
	)
	var ticks := 0
	while controller.get_fire_spawn_history().is_empty() and ticks < 6 * 24 + 1:
		controller.source_tick(ticks)
		ticks += 1
	_assert(not controller.get_fire_spawn_history().is_empty(), "M24 should spawn its first Fire batch after 2..6 seconds.")
	var fires := controller.get_fire_states()
	_assert(fires.size() == 2, "The first M24 Fire batch should contain exactly two instances.")
	if fires.is_empty():
		enemy.queue_free()
		await process_frame
		return
	var fire_origin := Vector2(fires[0]["global_position"])
	player.global_position = Vector2(fire_origin.x, fire_origin.y - 120.0)
	await physics_frame
	for tick in 24:
		controller.source_tick(ticks + tick)
	_assert(player.hits.is_empty(), "Fire must not hit before source currentFrame 25.")
	controller.source_tick(ticks + 24)
	_assert(not player.hits.is_empty(), "Fire should begin collision on source currentFrame 25.")
	if not player.hits.is_empty():
		_assert(int(player.hits[0]["damage"]) == 300, "Fire collision should deal source power 300.")
		_assert(player.hits[0]["damage_kind"] == &"magic", "Fire collision should remain magic damage.")
		_assert(Vector2(player.hits[0]["impulse"]).y == -240.0, "Fire vertical knockback should convert -10 px/tick to -240 px/s.")
	_assert(source_frames == [24], "The first Fire hit should occur on zero-based frame 24 (source currentFrame 25).")
	for tick in 11:
		controller.source_tick(ticks + 25 + tick)
	_assert(player.hits.size() == 1, "One Fire attack id should not repeatedly hit the same player.")
	player.global_position = Vector2(-2000, -2000)
	while controller.get_fire_spawn_history().size() < 3 and ticks < 20 * 24:
		controller.source_tick(ticks)
		ticks += 1
	_assert(
		controller.get_fire_spawn_history().slice(0, 3) == PackedInt32Array([2, 4, 6]),
		"M24 Fire batch sizes should cycle exactly 2 -> 4 -> 6."
	)
	enemy.queue_free()
	await process_frame


func _test_death_fade(world: Node2D, player: TestPlayer) -> void:
	player.global_position = Vector2(-2000, -2000)
	var enemy := await _spawn_enemy(world, &"m24_death", Vector2.ZERO)
	var controller := enemy.get_source_controller() as M24_CONTROLLER
	var tick := 0
	while controller.get_heart_phase() != &"vulnerable" and tick < 12 * 24:
		controller.source_tick(tick)
		tick += 1
	_assert(controller.get_heart_phase() == &"vulnerable", "Death test should reach a valid Heart damage window.")
	var weak_enemy: WeakRef = weakref(enemy)
	enemy.take_hit_from(999999, Vector2.ZERO, &"magic", player)
	_assert(enemy.get_state_name() == &"death", "Lethal Heart damage should enter source-controlled death.")
	for source_tick in 47:
		controller.source_tick(tick + source_tick)
	_assert(is_instance_valid(enemy), "M24 should remain alive through death fade tick 47.")
	_assert(enemy.modulate.a > 0.0, "M24 alpha should remain above zero before the 48th death tick.")
	controller.source_tick(tick + 47)
	await process_frame
	await process_frame
	_assert(weak_enemy.get_ref() == null, "M24 should clean up after the exact two-second death fade.")


func _spawn_enemy(world: Node2D, spawn_id: StringName, spawn_position: Vector2) -> AnimatedEnemy:
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M24_DEFINITION
	enemy.spawn_id = spawn_id
	enemy.position = spawn_position
	enemy.set_physics_process(false)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	await process_frame
	await physics_frame
	return enemy


func _create_player(world: Node2D) -> TestPlayer:
	var player := TestPlayer.new()
	player.name = "M24TestPlayer"
	player.add_to_group(&"players")
	player.collision_layer = 2
	player.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(36, 58)
	shape_node.shape = shape
	player.shape_node = shape_node
	player.add_child(shape_node)
	world.add_child(player)
	return player


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
