extends SceneTree

const STATUS_CONTROLLER := preload("res://src/combat/combat_status_controller.gd")
const M11_DEFINITION := preload("res://resources/enemies/zmxiyou1_m11_lion.tres")
const M26_DEFINITION := preload("res://resources/enemies/zmxiyou1_m26_dragon.tres")

var _failed := false


class StatusTarget:
	extends CharacterBody2D

	var health := 1000
	var locked := false

	func set_external_control_locked(_source: Object, value: bool) -> void:
		locked = value

	func apply_status_damage(amount: int, _status_id: StringName, _source: Object = null) -> void:
		health = maxi(0, health - amount)


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var poison_spec := _first_status(EnemyCombatCatalog.resolve_attack(
		M11_DEFINITION.animation_profile, &"attack3"
	))
	_assert(poison_spec.get("id", &"") == &"poison", "M11 hit3 should expose its source poison status.")
	_assert(int(poison_spec.get("duration_ticks", 0)) == 240, "M11 poison should last 240 source ticks.")
	_assert(int(poison_spec.get("power", 0)) == 20, "M11 poison should deal 20 per tick.")

	var low_ice := _first_status(EnemyCombatCatalog.resolve_attack(
		M26_DEFINITION.animation_profile, &"attack3", 1
	))
	var high_ice := _first_status(EnemyCombatCatalog.resolve_attack(
		M26_DEFINITION.animation_profile, &"attack3", 0
	))
	_assert(int(low_ice.get("duration_ticks", 0)) == 48, "Low-level M26 ice should last 48 source ticks.")
	_assert(int(high_ice.get("duration_ticks", 0)) == 120, "High-level M26 ice should last 120 source ticks.")

	var world := Node2D.new()
	root.add_child(world)
	var target := StatusTarget.new()
	world.add_child(target)
	var controller := STATUS_CONTROLLER.new()
	target.add_child(controller)
	controller.call(&"setup", target)
	_assert(bool(controller.call(&"apply_status", poison_spec, null)), "Poison status should apply.")
	var poison_head := target.get_node_or_null("CombatStatus_poison") as AnimatedSprite2D
	var poison_up := target.get_node_or_null("CombatStatus_poison_up") as AnimatedSprite2D
	_assert(poison_head != null and poison_head.position == Vector2(0, -70), "poisonHead should use source y=-70.")
	_assert(poison_up != null and poison_up.position == Vector2(0, -50), "poisonUp should use source y=-50.")
	for _tick in 23:
		controller.call(&"_advance_source_tick")
	_assert(target.health == 1000, "Poison should not damage before its 24-tick interval.")
	controller.call(&"_advance_source_tick")
	_assert(target.health == 980, "Poison should deal source power on tick 24.")

	_assert(bool(controller.call(&"apply_status", high_ice, null)), "Ice status should apply.")
	var ice := target.get_node_or_null("CombatStatus_ice") as AnimatedSprite2D
	_assert(ice != null and ice.position == Vector2(-90, -115), "Ice should use source x=-90/y=-115.")
	_assert(target.locked, "Ice should lock player control immediately.")
	for _tick in 120:
		controller.call(&"_advance_source_tick")
	await process_frame
	_assert(not target.locked, "Ice should release control after its source duration.")
	_assert(not bool(controller.call(&"has_status", &"ice")), "Expired ice should leave the status set.")

	world.queue_free()
	await process_frame
	print("Enemy status effects test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _first_status(attack_spec: Dictionary) -> Dictionary:
	var statuses: Array = attack_spec.get("status_effects", [])
	return statuses[0] as Dictionary if not statuses.is_empty() else {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
