extends SceneTree

const ENEMY_SCENE := preload("res://scenes/enemies/animated_enemy.tscn")
const STRATEGY := preload("res://src/enemies/zmxiyou1_enemy_strategy.gd")
const M06_DEFINITION := preload("res://resources/enemies/zmxiyou1_m06_yu_rong.tres")
const M22_DEFINITION := preload("res://resources/enemies/zmxiyou1_m22_bull.tres")
const M26_DEFINITION := preload("res://resources/enemies/zmxiyou1_m26_dragon.tres")

const PROFILE_FILES := [
	"zmxiyou1_m01_profile.tres",
	"zmxiyou1_m02_profile.tres",
	"zmxiyou1_m03_gorilla_profile.tres",
	"zmxiyou1_m04_monkey_king_profile.tres",
	"zmxiyou1_m06_yu_rong_profile.tres",
	"zmxiyou1_m07_profile.tres",
	"zmxiyou1_m08_profile.tres",
	"zmxiyou1_m09_peng_demon_king_profile.tres",
	"zmxiyou1_m09_peng_profile.tres",
	"zmxiyou1_m10_jiao_profile.tres",
	"zmxiyou1_m11_lion_profile.tres",
	"zmxiyou1_m13_profile.tres",
	"zmxiyou1_m14_profile.tres",
	"zmxiyou1_m15_profile.tres",
	"zmxiyou1_m16_profile.tres",
	"zmxiyou1_m17_turtle_profile.tres",
	"zmxiyou1_m18_profile.tres",
	"zmxiyou1_m19_shark_profile.tres",
	"zmxiyou1_m20_profile.tres",
	"zmxiyou1_m21_bat_profile.tres",
	"zmxiyou1_m22_bull_profile.tres",
	"zmxiyou1_m23_bull_demon_king_profile.tres",
	"zmxiyou1_m23_bull_profile.tres",
	"zmxiyou1_m24_profile.tres",
	"zmxiyou1_m25_profile.tres",
	"zmxiyou1_m26_dragon_profile.tres",
	"zmxiyou1_m27_chest_profile.tres",
]

const SOURCE_DEFINITION_EXPECTATIONS := {
	"zmxiyou1_m01.tres": [50, 5, 0, false, 72.0, 300.0, 80.0],
	"zmxiyou1_m02.tres": [100, 12, 1, false, 72.0, 300.0, 110.0],
	"zmxiyou1_m03_gorilla.tres": [900, 20, 5, true, 72.0, 300.0, 150.0],
	"zmxiyou1_m06_yu_rong.tres": [3000, 40, 6, true, 96.0, 300.0, 450.0],
	"zmxiyou1_m07.tres": [600, 35, 8, false, 72.0, 300.0, 110.0],
	"zmxiyou1_m08.tres": [500, 25, 7, false, 72.0, 300.0, 450.0],
	"zmxiyou1_m14.tres": [1000, 30, 25, false, 120.0, 300.0, 450.0],
	"zmxiyou1_m15.tres": [800, 55, 10, false, 72.0, 300.0, 450.0],
	"zmxiyou1_m17_turtle.tres": [4800, 110, 70, true, 72.0, 300.0, 400.0],
	"zmxiyou1_m20.tres": [1400, 100, 30, false, 72.0, 400.0, 200.0],
	"zmxiyou1_m21_bat.tres": [6000, 0, 25, true, 0.0, 300.0, 150.0],
	"zmxiyou1_m22_bull.tres": [40000, 300, 100, true, 312.0, 300.0, 450.0],
	"zmxiyou1_m25.tres": [5000, 200, 120, false, 72.0, 300.0, 110.0],
	"zmxiyou1_m27_chest.tres": [22100, 0, 25, false, 0.0, 300.0, 150.0],
}

var _failed := false


class TestPlayer:
	extends CharacterBody2D

	var health := 10000
	var hits: Array[Dictionary] = []


	func take_hit(
		damage: int, impulse: Vector2, damage_kind := &"physical", source: Object = null
	) -> void:
		health -= damage
		hits.append({
			"damage": damage,
			"impulse": impulse,
			"damage_kind": StringName(damage_kind),
			"source": source,
		})


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_reviewed_coverage()
	_test_source_definitions()
	_test_source_decisions()
	_test_source_context_formulas()
	await _test_source_context_runtime()
	await _test_invulnerability_timer()
	await _test_death_event_delivery()
	await _test_m22_controller()
	print("ZMX1 enemy strategy coverage test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_reviewed_coverage() -> void:
	var source_ids: Dictionary = {}
	for file_name: String in PROFILE_FILES:
		var profile := load("res://resources/enemies/animations/" + file_name) as EnemyAnimationProfile
		_assert(profile != null, "%s should load." % file_name)
		if profile == null:
			continue
		source_ids[profile.source_monster_id] = true
		_assert(STRATEGY.has_reviewed_strategy(profile), "%s needs a reviewed source strategy." % file_name)
	_assert(source_ids.size() == 25, "The canonical runtime profiles should cover 25 source monster ids.")


func _test_source_definitions() -> void:
	for file_name: String in SOURCE_DEFINITION_EXPECTATIONS:
		var definition := load("res://resources/enemies/" + file_name) as EnemyDefinition
		var expected: Array = SOURCE_DEFINITION_EXPECTATIONS[file_name]
		_assert(definition != null, "%s should load." % file_name)
		if definition == null:
			continue
		_assert(definition.property_template.max_health == expected[0], "%s HP should match source." % file_name)
		_assert(definition.property_template.attack == expected[1], "%s representative power should match source." % file_name)
		_assert(definition.property_template.defense == expected[2], "%s defense should match source." % file_name)
		_assert(definition.is_boss == expected[3], "%s boss flag should match the selected source variant." % file_name)
		_assert(is_equal_approx(definition.move_speed, expected[4]), "%s movement should use 24 Hz source speed." % file_name)
		_assert(is_equal_approx(definition.detection_range, expected[5]), "%s sight should match source mysee." % file_name)
		_assert(is_equal_approx(definition.default_attack_range, expected[6]), "%s range should match source attackRange." % file_name)


func _test_source_decisions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var m01 := _profile("zmxiyou1_m01_profile.tres")
	var decision := STRATEGY.decide(
		m01, 60.0, 36, {}, 1, false, rng,
		{"target_acquired": true, "provoked": false, "vertical_distance": 0.0}
	)
	_assert(bool(decision.get("patrol", false)), "M01 must remain passive until actually hit.")
	decision = STRATEGY.decide(
		m01, 120.0, 36, {}, 1, false, rng,
		{"target_acquired": true, "provoked": true, "vertical_distance": 0.0}
	)
	_assert(bool(decision.get("move", false)), "Provoked M01 should follow beyond its source 80 px range.")

	var m06 := _profile("zmxiyou1_m06_yu_rong_profile.tres")
	decision = STRATEGY.decide(
		m06, 100.0, 24, {}, 1, false, rng,
		{"target_acquired": true, "vertical_distance": 0.0}
	)
	_assert(decision.get("action", &"") == &"attack2", "M06 should open with hit2 when skillCD1 is ready.")
	decision = STRATEGY.decide(
		m06, 100.0, 48, {&"attack2": 1}, 1, false, rng,
		{"target_acquired": true, "vertical_distance": 0.0}
	)
	_assert(decision.get("action", &"") == &"attack1", "M06 should use hit1 while hit2 cools down.")
	_assert(STRATEGY.get_invulnerability_ticks(m06, &"attack2") == 48, "M06 hit2 should preserve setYourFather(48).")

	var m08 := _profile("zmxiyou1_m08_profile.tres")
	decision = STRATEGY.decide(
		m08, 180.0, 1, {}, 1, false, rng,
		{"target_acquired": true, "vertical_distance": 120.0, "vertical_delta": 120.0}
	)
	_assert(bool(decision.get("move", false)), "M08 should follow outside 140x90 source tolerance.")
	_assert(is_equal_approx(float(decision.get("flight_vertical_target_delta", 0.0)), 30.0), "M08 should track 90 px above its target.")

	var m14 := _profile("zmxiyou1_m14_profile.tres")
	decision = STRATEGY.decide(
		m14, 180.0, 1, {}, 1, false, rng, {"target_acquired": true}
	)
	_assert(bool(decision.get("move_away", false)), "M14 should retreat at 200 px or nearer.")
	decision = STRATEGY.decide(
		m14, 360.0, 1, {}, 1, false, rng, {"target_acquired": true}
	)
	_assert(bool(decision.get("move", false)) and not bool(decision.get("move_away", false)), "M14 should close beyond 350 px.")

	for stationary_file: String in ["zmxiyou1_m21_bat_profile.tres", "zmxiyou1_m27_chest_profile.tres"]:
		decision = STRATEGY.decide(
			_profile(stationary_file), 10.0, 36, {}, 1, false, rng, {"target_acquired": true}
		)
		_assert(bool(decision.get("reviewed", false)) and not bool(decision.get("move", true)), "%s should remain a non-attacking stationary object." % stationary_file)


func _test_m22_controller() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player := TestPlayer.new()
	player.add_to_group(&"players")
	player.collision_layer = 2
	player.collision_mask = 0
	var player_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(40.0, 70.0)
	player_shape.shape = rectangle
	player.add_child(player_shape)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M22_DEFINITION
	enemy.spawn_id = &"m22_source_test"
	enemy.position = Vector2(470.0, 300.0)
	world.add_child(enemy)
	await process_frame
	await physics_frame
	var controller: Node = enemy.get_source_controller()
	_assert(controller != null, "M22 should attach its source controller.")
	if controller == null:
		world.queue_free()
		await process_frame
		return
	_assert(bool(controller.call(&"is_running")), "M22 should begin by running left.")
	_assert(int(controller.call(&"get_direction")) == -1, "M22 first run direction should be left.")
	_assert(enemy.get_state_name() == &"walk", "M22 source controller should own the walk state.")
	_assert(not bool(controller.call(&"can_receive_hit")), "Running M22 should preserve source invulnerability.")

	enemy.global_position.x = enemy.get_viewport_rect().get_center().x - 361.0
	controller.call(&"source_tick", 0)
	_assert(not bool(controller.call(&"is_running")), "M22 should stop just beyond the left source boundary.")
	_assert(bool(controller.call(&"can_receive_hit")), "Stopped M22 should become vulnerable.")
	var health_before := enemy.health
	enemy.take_hit_from(10, Vector2.ZERO, &"physical", player)
	_assert(enemy.health < health_before, "Stopped M22 should accept Godot collision damage.")
	_assert(enemy.get_state_name() == &"idle", "M22 should not enter a generic hurt animation when stopped.")

	for tick in 24:
		controller.call(&"source_tick", tick + 1)
	_assert(not bool(controller.call(&"is_running")), "M22 first stop should last through source tick 24.")
	controller.call(&"source_tick", 25)
	_assert(bool(controller.call(&"is_running")), "M22 should reverse on the 25th stopped source tick.")
	_assert(int(controller.call(&"get_direction")) == 1, "M22 should reverse to the right.")

	var walk_attack := EnemyCombatCatalog.resolve_attack(M22_DEFINITION.animation_profile, &"move")
	_assert(int(walk_attack.get("damage", 0)) == 300, "M22 move atlas should resolve the source walk attack.")
	_assert(StringName(enemy.get("_contact_action")) == &"move", "M22 walk should be registered as its contact action.")
	enemy.set_physics_process(false)
	player.global_position = enemy.global_position + Vector2(44.0, -32.0)
	await physics_frame
	var overlap_shape := RectangleShape2D.new()
	overlap_shape.size = Vector2(72.0, 58.0)
	var overlap_query := PhysicsShapeQueryParameters2D.new()
	overlap_query.shape = overlap_shape
	overlap_query.transform = Transform2D(0.0, enemy.global_position + Vector2(44.0, -32.0))
	overlap_query.collision_mask = 2
	var overlaps := world.get_world_2d().direct_space_state.intersect_shape(overlap_query, 16)
	_assert(not overlaps.is_empty(), "M22 test player should overlap the Godot contact query.")
	enemy.call(&"_process_contact_attack")
	_assert(not player.hits.is_empty(), "Running M22 should use a Godot contact shape in place of Flash hit testing.")
	if not player.hits.is_empty():
		_assert(int(player.hits[0]["damage"]) == 300, "M22 walk contact should preserve source power 300.")

	var stage_effects: Array[Dictionary] = []
	enemy.source_stage_effect_requested.connect(
		func(effect: Dictionary, _source_enemy: AnimatedEnemy) -> void: stage_effects.append(effect)
	)
	enemy.call(&"_notify_source_before_despawn")
	_assert(stage_effects.size() == 1, "M22 death should request one StageController follow-up effect.")
	if not stage_effects.is_empty():
		_assert(StringName(stage_effects[0].get("type", &"")) == &"spawn_monster", "M22 should request a data-driven follow-up spawn.")
		_assert(Vector2(stage_effects[0].get("position", Vector2.ZERO)).is_equal_approx(Vector2(1500.0, 450.0)), "M23 should retain the source 1500,450 spawn point.")
	_assert(world.get_child_count() == 2, "M22's controller should leave stage-owned spawning to StageController.")
	world.queue_free()
	await process_frame


func _test_source_context_formulas() -> void:
	var m03 := _profile("zmxiyou1_m03_gorilla_profile.tres")
	var stats := STRATEGY.get_source_context_stats(m03, 1, 1)
	_assert(int(stats.get("max_health", 0)) == 900 and bool(stats.get("is_boss", false)), "M03 should be the 900 HP boss only at source stage 1 level 1.")
	stats = STRATEGY.get_source_context_stats(m03, 1, 2)
	_assert(int(stats.get("max_health", 0)) == 300 and not bool(stats.get("is_boss", true)), "M03 should use its 300 HP non-boss source variant elsewhere.")

	var m17 := _profile("zmxiyou1_m17_turtle_profile.tres")
	stats = STRATEGY.get_source_context_stats(m17, 3, 1)
	_assert(int(stats.get("max_health", 0)) == 4800 and bool(stats.get("is_boss", false)), "M17 should be the boss at source stage 3 level 1.")
	stats = STRATEGY.get_source_context_stats(m17, 2, 1)
	_assert(int(stats.get("max_health", 0)) == 1600 and not bool(stats.get("is_boss", true)), "M17 should use its non-boss source variant elsewhere.")

	var m27 := _profile("zmxiyou1_m27_chest_profile.tres")
	stats = STRATEGY.get_source_context_stats(m27, 1, 1)
	_assert(int(stats.get("total_stage", 0)) == 1 and int(stats.get("max_health", 0)) == 140, "M27 stage 1 level 1 HP formula should produce 140.")
	stats = STRATEGY.get_source_context_stats(m27, 2, 3)
	_assert(int(stats.get("total_stage", 0)) == 6 and int(stats.get("max_health", 0)) == 5140, "M27 stage 2 level 3 HP formula should produce 5140.")
	stats = STRATEGY.get_source_context_stats(m27, 4, 1)
	_assert(int(stats.get("total_stage", 0)) == 10 and int(stats.get("max_health", 0)) == 22100, "M27 stage 4+ should clamp to source totalStage 10.")


func _test_source_context_runtime() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var m17_definition := load("res://resources/enemies/zmxiyou1_m17_turtle.tres") as EnemyDefinition
	var normal_m17 := ENEMY_SCENE.instantiate() as AnimatedEnemy
	normal_m17.definition = m17_definition
	normal_m17.spawn_id = &"m17_normal_context"
	normal_m17.set_source_stage_context(2, 1)
	world.add_child(normal_m17)
	await process_frame
	_assert(normal_m17.health == 1600 and not normal_m17.is_boss(), "Injected stage context should select the non-boss M17 runtime stats.")

	var m27_definition := load("res://resources/enemies/zmxiyou1_m27_chest.tres") as EnemyDefinition
	var early_chest := ENEMY_SCENE.instantiate() as AnimatedEnemy
	early_chest.definition = m27_definition
	early_chest.spawn_id = &"m27_early_context"
	early_chest.set_source_stage_context(1, 1)
	world.add_child(early_chest)
	await process_frame
	_assert(early_chest.health == 140, "Injected stage context should apply the M27 cubic source HP formula.")
	world.queue_free()
	await process_frame


func _test_invulnerability_timer() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M06_DEFINITION
	enemy.spawn_id = &"m06_invulnerability_test"
	world.add_child(enemy)
	await process_frame
	await physics_frame
	enemy.set_physics_process(false)
	_assert(enemy.force_attack(&"attack2"), "M06 hit2 should be forceable.")
	_assert(enemy.get_source_invulnerability_ticks_remaining() == 48, "M06 hit2 should begin with 48 invulnerable source ticks.")
	var health_before := enemy.health
	enemy.take_hit_from(1000, Vector2.ZERO, &"physical", null)
	_assert(enemy.health == health_before, "M06 should reject damage during setYourFather(48).")
	for tick in 47:
		enemy.call(&"_advance_source_tick")
	_assert(enemy.get_source_invulnerability_ticks_remaining() == 1, "M06 invulnerability should remain on tick 47.")
	enemy.call(&"_advance_source_tick")
	_assert(enemy.get_source_invulnerability_ticks_remaining() == 0, "M06 invulnerability should end on tick 48.")
	enemy.take_hit_from(1000, Vector2.ZERO, &"physical", null)
	_assert(enemy.health < health_before, "M06 should accept damage after the exact source window.")
	world.queue_free()
	await process_frame


func _test_death_event_delivery() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var m06 := ENEMY_SCENE.instantiate() as AnimatedEnemy
	m06.definition = M06_DEFINITION
	m06.spawn_id = &"m06_death_event_test"
	world.add_child(m06)
	await process_frame
	m06.set_physics_process(false)
	m06.take_hit_from(999999, Vector2.ZERO, &"physical", null)
	var false_events := M06_DEFINITION.animation_profile.get_source_events_at_frame(&"death", 0)
	_assert(not false_events.is_empty(), "M06 death should retain its first visibility event.")
	if not false_events.is_empty():
		m06.call(&"_on_source_event", &"death", false_events[0])
		_assert(not m06.animated_sprite.visible, "Source death visibility=false should hide the runtime sprite.")
	var true_events := M06_DEFINITION.animation_profile.get_source_events_at_frame(&"death", 2)
	if not true_events.is_empty():
		m06.call(&"_on_source_event", &"death", true_events[0])
		_assert(m06.animated_sprite.visible, "Source death visibility=true should restore the runtime sprite.")
	var spawn_events := M06_DEFINITION.animation_profile.get_source_events_at_frame(&"death", 24)
	for event: Dictionary in spawn_events:
		if StringName(event.get("id", &"")) == &"spawn_object":
			m06.call(&"_on_source_event", &"death", event)
	_assert(m06.has_spawned_source_boss_dead_effect(), "M06 should create BossDead only from its source frame event.")

	var m26 := ENEMY_SCENE.instantiate() as AnimatedEnemy
	m26.definition = M26_DEFINITION
	m26.spawn_id = &"m26_death_event_test"
	world.add_child(m26)
	await process_frame
	m26.set_physics_process(false)
	m26.take_hit_from(999999, Vector2.ZERO, &"physical", null)
	_assert(not m26.has_spawned_source_boss_dead_effect(), "M26 should not invent BossDead when its death timeline only drops aura and destroys.")
	world.queue_free()
	await process_frame


func _profile(file_name: String) -> EnemyAnimationProfile:
	return load("res://resources/enemies/animations/" + file_name) as EnemyAnimationProfile


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
