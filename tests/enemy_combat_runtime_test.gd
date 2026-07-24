extends SceneTree

const ENEMY_SCENE := preload("res://scenes/enemies/animated_enemy.tscn")
const ZMX1_STRATEGY := preload("res://src/enemies/zmxiyou1_enemy_strategy.gd")
const M04_DEFINITION := preload("res://resources/enemies/zmxiyou1_m04_monkey_king.tres")
const M09_DEFINITION := preload("res://resources/enemies/zmxiyou1_m09_peng.tres")
const M10_DEFINITION := preload("res://resources/enemies/zmxiyou1_m10_jiao.tres")
const M13_DEFINITION := preload("res://resources/enemies/zmxiyou1_m13.tres")
const M14_DEFINITION := preload("res://resources/enemies/zmxiyou1_m14.tres")
const M16_DEFINITION := preload("res://resources/enemies/zmxiyou1_m16.tres")
const M18_DEFINITION := preload("res://resources/enemies/zmxiyou1_m18.tres")
const M19_DEFINITION := preload("res://resources/enemies/zmxiyou1_m19_shark.tres")
const M23_DEFINITION := preload("res://resources/enemies/zmxiyou1_m23_bull.tres")
const M26_DEFINITION := preload("res://resources/enemies/zmxiyou1_m26_dragon.tres")

var _failed := false


class TestPlayer:
	extends CharacterBody2D

	var hits: Array[Dictionary] = []
	var health := 1000
	var level := 1
	var facing := 1.0
	var control_locked := false
	var visual_hidden := false

	func take_hit(damage: int, impulse: Vector2, damage_kind := &"physical", source: Object = null) -> void:
		health = maxi(0, health - damage)
		hits.append({
			"damage": damage,
			"impulse": impulse,
			"damage_kind": StringName(damage_kind),
			"source": source,
		})

	func set_external_control_locked(_source: Object, locked: bool) -> void:
		control_locked = locked

	func set_external_visual_hidden(_source: Object, hidden: bool) -> void:
		visual_hidden = hidden

	func get_combat_facing() -> int:
		return -1 if facing < 0.0 else 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_source_catalog()
	var world := Node2D.new()
	root.add_child(world)
	var floor := StaticBody2D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(1200, 40)
	floor_shape.shape = floor_rect
	floor.add_child(floor_shape)
	floor.position = Vector2(500, 360)
	world.add_child(floor)

	var player := TestPlayer.new()
	player.add_to_group(&"players")
	player.collision_layer = 2
	player.collision_mask = 1
	var player_shape := CollisionShape2D.new()
	var player_rect := RectangleShape2D.new()
	player_rect.size = Vector2(36, 58)
	player_shape.shape = player_rect
	player_shape.position.y = -29
	player.add_child(player_shape)
	player.position = Vector2(160, 330)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M04_DEFINITION
	enemy.position = Vector2(560, 330)
	world.add_child(enemy)
	await process_frame
	await process_frame
	_assert(enemy.get_current_action() == &"attack3", "M04 should select its reviewed ranged action at 400 px.")
	var attack_spec := enemy.get_current_attack_spec()
	_assert(int(attack_spec.get("damage", -1)) == 20, "M04 attack3 should use source power 20.")
	_assert(StringName(attack_spec.get("damage_kind", &"")) == &"magic", "M04 attack3 should preserve magic damage.")

	for _frame in 12:
		await physics_frame
	var bullet := _find_bullet(world)
	_assert(bullet != null, "M04 source frame 4 should spawn its atlas projectile.")
	if bullet != null:
		var shape := bullet.get_node("CollisionShape2D") as CollisionShape2D
		_assert(shape.shape is RectangleShape2D, "Projectile should expose a Godot rectangle collision shape.")
		if shape.shape is RectangleShape2D:
			var size := (shape.shape as RectangleShape2D).size
			_assert(size.x < 733.0 or size.y < 169.0, "Projectile collision should follow visible pixels, not the full Flash canvas.")
		bullet.queue_free()
	await process_frame
	player.position = Vector2(500, 330)
	player.hits.clear()
	_assert(enemy.force_attack(&"attack1"), "M04 melee attack should be forceable for deterministic collision testing.")
	for _frame in 18:
		await physics_frame
	_assert(
		player.hits.any(func(hit: Dictionary) -> bool: return int(hit["damage"]) == 30 and hit["damage_kind"] == &"physical"),
		"Frame-active Godot melee collision should apply M04 source physical power 30."
	)
	await _test_m13_projectile(world, player)
	await _test_m18_contact_projectile(world, player)
	await _test_canonical_action_transition(world)
	await _test_m19_phase_transition(world)
	await _test_m26_level_variant(world, player)
	await _test_m09_takeoff_invulnerability(world, player)
	await _test_m09_egg_lifecycle(world, player)
	await _test_m10_back_hit(world, player)

	world.queue_free()
	await process_frame
	print("Enemy combat runtime test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_source_catalog() -> void:
	var profile := M04_DEFINITION.animation_profile
	var attack1 := EnemyCombatCatalog.resolve_attack(profile, &"attack1")
	_assert(int(attack1.get("damage", -1)) == 30, "M04 attack1 should resolve source power 30.")
	_assert(int(attack1.get("hit_max_count", -1)) == 2, "M04 attack1 should resolve source two-hit limit.")
	_assert(
		Vector2(attack1.get("knockback_velocity", Vector2.ZERO)).is_equal_approx(Vector2(144, -120)),
		"Flash per-tick knockback should convert to 24 Hz Godot velocity."
	)
	var attack2 := EnemyCombatCatalog.resolve_attack(profile, &"attack2")
	_assert(int(attack2.get("rehit_interval_frames", -1)) == 999, "M04 attack2 should preserve its source hit interval.")
	var m14_attack := EnemyCombatCatalog.resolve_attack(M14_DEFINITION.animation_profile, &"attack1")
	_assert(int(m14_attack.get("damage", -1)) == 30, "M14 projectile should preserve source power 30.")
	_assert(StringName(m14_attack.get("damage_kind", &"")) == &"magic", "M14 projectile should preserve magic damage.")
	_assert(
		StringName(M14_DEFINITION.animation_profile.get_spec(&"attack1").get("projectile_motion", &"")) == &"accelerating",
		"Only the reviewed M14 projectile should opt into code-driven acceleration."
	)
	var m13_attack := EnemyCombatCatalog.resolve_attack(M13_DEFINITION.animation_profile, &"attack2")
	_assert(int(m13_attack.get("damage", -1)) == 60, "M13 flying knife should preserve source power 60.")
	_assert(
		M13_DEFINITION.animation_profile.get_spec(&"attack2").get("projectile_spawn_frame", -1) == 2,
		"M13 hit2 should throw its knife on source frame 3."
	)
	_assert(M13_DEFINITION.property_template.defense == 9, "M13 should preserve source defense 9.")
	_assert(M16_DEFINITION.property_template.defense == 50, "M16 should preserve source defense 50.")
	var m26_attack := EnemyCombatCatalog.resolve_attack(M26_DEFINITION.animation_profile, &"attack4")
	_assert(int(m26_attack.get("damage", -1)) == 150, "M26 normal-mode attack4 should select source power 150.")
	_assert(M26_DEFINITION.animation_profile.actions.has(&"idle"), "M26 should restore its shared idle runtime atlas.")
	_assert(M26_DEFINITION.animation_profile.actions.has(&"move"), "M26 should restore its shared move runtime atlas.")
	_test_source_strategy()


func _test_source_strategy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var m04 := M04_DEFINITION.animation_profile
	var decision: Dictionary = ZMX1_STRATEGY.decide(m04, 400.0, 1, {}, 1, false, rng)
	_assert(decision.get("action", &"") == &"attack3", "M04 should use source ranged skill beyond 150 px.")
	decision = ZMX1_STRATEGY.decide(m04, 100.0, 24, {&"attack2": 1}, 1, false, rng)
	_assert(decision.get("action", &"") == &"attack1", "M04 should fall back to hit1 on its 24-tick decision.")
	_assert(
		ZMX1_STRATEGY.get_cooldown_ticks(m04, &"attack3", 0.0) == 180,
		"M04 ranged cooldown should remain exactly 180 source ticks."
	)
	_assert(
		is_equal_approx(ZMX1_STRATEGY.get_move_speed(m04, 0.0), 72.0),
		"M04 source movement should convert 3 px/tick to 72 px/s."
	)
	var m13 := M13_DEFINITION.animation_profile
	decision = ZMX1_STRATEGY.decide(
		m13, 100.0, 24, {}, 1, false, rng, {"vertical_distance": 0.0}
	)
	_assert(decision.get("action", &"") == &"attack2", "M13 should open with its ready hit2 skill.")
	decision = ZMX1_STRATEGY.decide(
		m13, 100.0, 48, {&"attack2": 1}, 1, false, rng, {"vertical_distance": 0.0}
	)
	_assert(decision.get("action", &"") == &"attack1", "M13 should use hit1 while skill1 is cooling down.")
	_assert(
		ZMX1_STRATEGY.get_cooldown_ticks(m13, &"attack2", 0.0) == 96,
		"M13 skill1 cooldown should remain exactly 96 source ticks."
	)


func _test_canonical_action_transition(world: Node2D) -> void:
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M23_DEFINITION
	enemy.position = Vector2(900, 330)
	world.add_child(enemy)
	await process_frame
	_assert(enemy.force_attack(&"attack5"), "M23 source grab action should be forceable.")
	enemy.call("_on_source_event", &"attack5", {
		"id": &"timeline_branch",
		"frame": 28,
		"types": PackedStringArray(["action_transition"]),
	})
	await process_frame
	_assert(
		enemy.get_current_action() == &"attack5",
		"A conditional timeline_branch must not be treated as an unconditional action transition."
	)
	var player := get_first_node_in_group(&"players") as TestPlayer
	player.position.x = enemy.position.x - 100.0
	enemy.health = enemy.get_effective_max_health() - 1000
	enemy.call("_on_source_event", &"attack5", {
		"id": &"grab_check",
		"frame": 27,
		"types": PackedStringArray(["action_transition", "timeline_control"]),
	})
	_assert(player.control_locked and player.visual_hidden, "M23 grab should lock and hide its source target.")
	var player_health_before := player.health
	var boss_health_before := enemy.health
	enemy.call("_on_source_event", &"attack5", {
		"id": &"life_steal_tick",
		"frame": 36,
		"types": PackedStringArray(["custom_script", "life_steal"]),
	})
	_assert(player.health == player_health_before - 50, "Each M23 source drain tick should deal 50 magic damage.")
	_assert(enemy.health == boss_health_before + 500, "Each M23 source drain tick should heal the boss by 500.")
	enemy.call("_on_source_event", &"attack5", {
		"id": &"action_transition",
		"frame": 99,
		"types": PackedStringArray(["action_transition"]),
	})
	await process_frame
	_assert(
		enemy.get_current_action() != &"attack5",
		"The canonical action_transition event should complete the source action."
	)
	_assert(not player.control_locked and not player.visual_hidden, "M23 action cleanup should restore target control and visibility.")
	enemy.queue_free()
	await process_frame


func _test_m18_contact_projectile(world: Node2D, player: TestPlayer) -> void:
	_clear_bullets(world)
	player.position = Vector2(500, 330)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M18_DEFINITION
	enemy.position = Vector2(500, 330)
	world.add_child(enemy)
	await process_frame
	_clear_bullets(world)
	_assert(enemy.force_attack(&"attack1"), "M18 contact attack should be forceable.")
	for _frame in 3:
		await physics_frame
	var bullet := _find_bullet(world)
	_assert(bullet != null, "M18 hit1 should create Bullet1 only after Godot contact overlap.")
	if bullet != null:
		_assert(
			bullet.global_position.is_equal_approx(player.global_position + Vector2(-100, -100)),
			"M18 Bullet1 should use the source target -100/-100 position."
		)
		bullet.queue_free()
	enemy.queue_free()
	await process_frame


func _test_m13_projectile(world: Node2D, player: TestPlayer) -> void:
	_clear_bullets(world)
	player.position = Vector2(420, 330)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M13_DEFINITION
	enemy.position = Vector2(600, 330)
	world.add_child(enemy)
	await process_frame
	_clear_bullets(world)
	_assert(enemy.force_attack(&"attack2"), "M13 source flying-knife action should be forceable.")
	var bullet: EnemyBullet
	for _frame in 12:
		await physics_frame
		bullet = _find_bullet(world)
		if bullet != null:
			break
	_assert(bullet != null, "M13 hit2 frame 3 should spawn the recovered 27-frame flying knife.")
	if bullet != null:
		_assert(
			bullet.global_position.is_equal_approx(enemy.global_position + Vector2(-20, 0)),
			"M13 left-facing knife should preserve its source -20 px spawn offset."
		)
		var sprite := bullet.get_node("AnimatedSprite2D") as AnimatedSprite2D
		_assert(
			sprite.sprite_frames.get_frame_count(&"projectile") == 27,
			"M13 flying knife should play all 27 source frames."
		)
		bullet.queue_free()
	enemy.queue_free()
	await process_frame


func _test_m19_phase_transition(world: Node2D) -> void:
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M19_DEFINITION
	enemy.spawn_id = &"phase_test"
	enemy.position = Vector2(820, 330)
	world.add_child(enemy)
	await process_frame
	_assert(
		enemy.definition.animation_profile.actions.has(&"attack3_2"),
		"M19 phase two should expose its reviewed hit3-2 atlas."
	)
	enemy.health = floori(enemy.get_effective_max_health() * 0.69)
	enemy.call("_advance_source_tick")
	await process_frame
	_assert(enemy.get_combat_phase() == 2, "M19 should enter phase two below 70 percent health.")
	var summon: AnimatedEnemy
	for candidate: Node in world.get_children():
		if candidate is AnimatedEnemy and candidate != enemy:
			var animated_candidate := candidate as AnimatedEnemy
			if animated_candidate.definition == M18_DEFINITION:
				summon = animated_candidate
				break
	_assert(summon != null, "M19 should create exactly one source M18 summon on its first low-health transition.")
	if summon != null:
		_assert(not summon.is_in_group(&"bosses"), "Source M18 is a flying non-boss summon.")
		summon.queue_free()
	enemy.queue_free()
	await process_frame


func _test_m26_level_variant(world: Node2D, player: TestPlayer) -> void:
	_clear_bullets(world)
	await process_frame
	player.level = 21
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M26_DEFINITION
	enemy.position = Vector2(760, 330)
	world.add_child(enemy)
	await process_frame
	_assert(enemy.get_source_attack_variant() == 0, "M26 should select its high-level source attack variant.")
	_assert(enemy.get_effective_max_health() == 40000, "High-level M26 should use source HP 40000.")
	_assert(enemy.get_defense() == 150, "High-level M26 should use source defense 150.")
	_clear_bullets(world)
	await process_frame
	_assert(enemy.force_attack(&"attack4"), "M26 high-level attack4 should be forceable.")
	_assert(
		int(enemy.get_current_attack_spec().get("damage", 0)) == 300,
		"High-level M26 attack4 should use source power 300."
	)
	var bullet := _find_bullet(world)
	_assert(bullet != null, "M26 hit4 should spawn its atlas projectile immediately.")
	if bullet != null:
		_assert(
			bullet.global_position.is_equal_approx(Vector2(player.global_position.x - 65.0, enemy.global_position.y - 120.0)),
			"M26 hit4 should use target.x-65 and boss.y-120 (actual=%s expected=%s)." % [
				bullet.global_position,
				Vector2(player.global_position.x - 65.0, enemy.global_position.y - 120.0),
			]
		)
		bullet.queue_free()
	enemy.queue_free()
	player.level = 1
	await process_frame


func _test_m09_takeoff_invulnerability(world: Node2D, player: TestPlayer) -> void:
	player.position = Vector2(100, 330)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M09_DEFINITION
	enemy.position = Vector2(900, 330)
	world.add_child(enemy)
	await process_frame
	enemy.set("_peng_floor_ticks", 1)
	enemy.call(&"_advance_source_tick")
	_assert(enemy.is_source_flying(), "M09 should take off when its source floor timer reaches zero.")
	_assert(enemy.get_source_invulnerability_ticks_remaining() == 72, "M09 takeoff should preserve setYourFather(72).")
	var health_before := enemy.health
	enemy.take_hit_from(9999, Vector2.ZERO, &"physical", player)
	_assert(enemy.health == health_before, "M09 should reject hits during its takeoff invulnerability window.")
	for _tick: int in 72:
		enemy.call(&"_advance_source_tick")
	_assert(enemy.get_source_invulnerability_ticks_remaining() == 0, "M09 takeoff invulnerability should end after exactly 72 ticks.")
	enemy.take_hit_from(1, Vector2.ZERO, &"physical", player)
	_assert(enemy.health < health_before, "M09 should accept hits after its takeoff window.")
	enemy.queue_free()
	await process_frame


func _test_m09_egg_lifecycle(world: Node2D, player: TestPlayer) -> void:
	_clear_bullets(world)
	player.position = Vector2(100, 330)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M09_DEFINITION
	enemy.position = Vector2(900, 330)
	world.add_child(enemy)
	await process_frame
	enemy.health = 1
	enemy.take_hit(1, Vector2.ZERO)
	_assert(enemy.get_current_action() == &"egg", "Lethal damage should turn M09 into its source egg action.")
	_assert(enemy.get_peng_egg_hits_remaining() == 5, "Single-player M09 egg should require five distinct hits.")
	for _hit in 4:
		enemy.take_hit(9999, Vector2.ZERO)
	_assert(enemy.get_state_name() != &"death", "M09 egg should survive its first four single-player hits.")
	enemy.take_hit(9999, Vector2.ZERO)
	_assert(enemy.get_state_name() == &"death", "The fifth single-player egg hit should cause real M09 death.")
	enemy.queue_free()
	await process_frame

	var reburn_enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	reburn_enemy.definition = M09_DEFINITION
	reburn_enemy.position = Vector2(900, 330)
	world.add_child(reburn_enemy)
	await process_frame
	reburn_enemy.health = 1
	reburn_enemy.take_hit(1, Vector2.ZERO)
	for _tick in 167:
		reburn_enemy.call(&"_advance_source_tick")
	_assert(reburn_enemy.get_current_action() == &"reburn", "Unbroken M09 egg should reburn after 168 source ticks.")
	_assert(reburn_enemy.health == 10000, "M09 reburn should restore its source HP 10000.")
	_assert(reburn_enemy.get_peng_egg_hits_remaining() == 5, "M09 reburn should reset the egg hit quota.")
	reburn_enemy.queue_free()
	await process_frame


func _test_m10_back_hit(world: Node2D, player: TestPlayer) -> void:
	player.position = Vector2(100, 330)
	player.facing = -1
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M10_DEFINITION
	enemy.position = Vector2(300, 330)
	world.add_child(enemy)
	await process_frame
	var before := enemy.health
	enemy.take_hit_from(500, Vector2.ZERO, &"physical", player)
	_assert(enemy.health == before - 1, "Same-facing M10 back hit should deal exactly one source damage.")
	_assert(enemy.get_node_or_null("M10BackHit") != null, "Physical M10 back hit should play Monster10BeAttack.")
	player.facing = 1
	before = enemy.health
	enemy.take_hit_from(500, Vector2.ZERO, &"physical", player)
	_assert(enemy.health == before - 500, "Opposite-facing M10 hit should use normal resolved damage.")
	enemy.queue_free()
	await process_frame


func _find_bullet(node: Node) -> EnemyBullet:
	for child: Node in node.get_children():
		if child is EnemyBullet:
			return child as EnemyBullet
		var nested := _find_bullet(child)
		if nested != null:
			return nested
	return null


func _clear_bullets(node: Node) -> void:
	for child: Node in node.get_children():
		if child is EnemyBullet:
			child.queue_free()
		else:
			_clear_bullets(child)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
