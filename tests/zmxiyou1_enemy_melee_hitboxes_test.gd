extends SceneTree

const ENEMY_SCENE := preload("res://scenes/enemies/animated_enemy.tscn")
const M01_DEFINITION := preload("res://resources/enemies/zmxiyou1_m01.tres")
const M13_DEFINITION := preload("res://resources/enemies/zmxiyou1_m13.tres")
const M22_DEFINITION := preload("res://resources/enemies/zmxiyou1_m22_bull.tres")
const M23_DEFINITION := preload("res://resources/enemies/zmxiyou1_m23_bull.tres")

var _failed := false


class TestPlayer:
	extends CharacterBody2D

	var hits := 0

	func take_hit(
		_damage: int, _impulse: Vector2, _damage_kind := &"physical", _source: Object = null
	) -> void:
		hits += 1


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_catalog_geometry()
	await _test_runtime_mapping_and_collision()
	print("ZMX1 enemy melee hitbox test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_catalog_geometry() -> void:
	var m01 := EnemyCombatCatalog.resolve_attack(M01_DEFINITION.animation_profile, &"attack1")
	_assert(bool(m01.get("melee_geometry_reviewed", false)), "M01 attack1 must use reviewed SWF stick geometry.")
	var m01_frames := m01.get("melee_frame_hitboxes", []) as Array
	_assert(m01_frames.size() == 24, "M01 attack1 must preserve all 24 source geometry frames.")
	_assert((m01_frames[0] as Array).is_empty(), "M01 attack1 frame 1 must not attack before stick exists.")
	_assert((m01_frames[12] as Array).is_empty(), "M01 attack1 frame 13 must still be inactive.")
	_assert((m01_frames[13] as Array).size() == 1, "M01 attack1 source frame 14 must expose stick.")

	var m13 := EnemyCombatCatalog.resolve_attack(M13_DEFINITION.animation_profile, &"attack1")
	var m13_frames := m13.get("melee_frame_hitboxes", []) as Array
	_assert((m13_frames[4] as Array).size() == 2, "M13 attack1 frame 5 must preserve two simultaneous stick pieces.")
	_assert((m13_frames[5] as Array).size() == 2, "M13 attack1 frame 6 must preserve two simultaneous stick pieces.")

	var m22 := EnemyCombatCatalog.resolve_attack(M22_DEFINITION.animation_profile, &"move")
	var m22_frames := m22.get("melee_frame_hitboxes", []) as Array
	_assert(m22_frames.size() == 110, "M22 run contact must preserve all 110 source frames.")
	_assert(
		m22_frames.all(func(frame_boxes: Variant) -> bool: return frame_boxes is Array and (frame_boxes as Array).size() == 1),
		"Every M22 run frame must retain its source contact stick."
	)

	var m23 := EnemyCombatCatalog.resolve_attack(M23_DEFINITION.animation_profile, &"attack3")
	var m23_frames := m23.get("melee_frame_hitboxes", []) as Array
	_assert((m23_frames[61] as Array).size() == 1, "M23 attack3 must retain its final pre-stop stick frame.")
	_assert((m23_frames[62] as Array).is_empty(), "M23 nested stop() must prevent stick from looping back after frame 62.")


func _test_runtime_mapping_and_collision() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as AnimatedEnemy
	enemy.definition = M01_DEFINITION
	enemy.position = Vector2(300.0, 300.0)
	world.add_child(enemy)
	var player := TestPlayer.new()
	player.add_to_group(&"players")
	player.collision_layer = 2
	player.collision_mask = 0
	var player_shape := CollisionShape2D.new()
	var player_rect := RectangleShape2D.new()
	player_rect.size = Vector2(8.0, 8.0)
	player_shape.shape = player_rect
	player.add_child(player_shape)
	world.add_child(player)
	await process_frame
	await physics_frame

	_assert(enemy.force_attack(&"attack1"), "M01 attack1 must be forceable for geometry testing.")
	var early_boxes := enemy.call(&"_melee_hitboxes_for_frame", 0) as Array
	_assert(early_boxes.is_empty(), "Reviewed inactive frames must not fall back to the generic 72x58 box.")
	var left_boxes := enemy.call(&"_melee_hitboxes_for_frame", 13) as Array
	_assert(left_boxes.size() == 1, "M01 active frame must produce exactly one Godot rectangle.")
	if left_boxes.size() == 1:
		var left_box := Rect2(left_boxes[0])
		_assert(left_box.size.is_equal_approx(Vector2(52.4991, 92.9988)), "M01 source stick size must apply visual_scale exactly.")
		_assert(left_box.get_center().is_equal_approx(Vector2(-22.425, -55.0)), "M01 stick registration must map through atlas center and sprite_offset.")
		enemy.set("_facing", 1)
		(enemy.get_node("AnimatedSprite2D") as AnimatedSprite2D).flip_h = true
		var right_boxes := enemy.call(&"_melee_hitboxes_for_frame", 13) as Array
		var right_box := Rect2(right_boxes[0])
		_assert(right_box.get_center().is_equal_approx(Vector2(22.425, -55.0)), "Right-facing stick must mirror around AnimatedSprite2D.position.")
		_assert(right_box.size.is_equal_approx(left_box.size), "Facing mirror must not change source stick size.")

	# Return to the source-default left facing. x=45 is still inside the full
	# 106.5 px-wide rendered frame but outside the real stick rectangle.
	enemy.set("_facing", -1)
	(enemy.get_node("AnimatedSprite2D") as AnimatedSprite2D).flip_h = false
	player.position = enemy.position + Vector2(45.0, -55.0)
	await physics_frame
	enemy.call(&"_perform_melee_hits", 13)
	_assert(player.hits == 0, "Visible animation pixels outside body.stick must not damage the player.")
	player.position = enemy.position + Vector2(-22.425, -55.0)
	await physics_frame
	enemy.call(&"_perform_melee_hits", 13)
	_assert(player.hits == 1, "Godot physics overlap inside the reviewed source stick must damage once.")

	world.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
