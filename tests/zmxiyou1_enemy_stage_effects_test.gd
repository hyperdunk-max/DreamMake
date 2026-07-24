extends SceneTree

const ANIMATED_ENEMY_SCENE := preload("res://scenes/enemies/animated_enemy.tscn")
const M03 := preload("res://resources/enemies/zmxiyou1_m03_gorilla.tres")
const M04 := preload("res://resources/enemies/zmxiyou1_m04_monkey_king.tres")
const M22 := preload("res://resources/enemies/zmxiyou1_m22_bull.tres")
const M24 := preload("res://resources/enemies/zmxiyou1_m24_bull_demon_king.tres")
const M27 := preload("res://resources/enemies/zmxiyou1_m27_chest.tres")

var _failed := false


class TestPlayer:
	extends CharacterBody2D

	var source_equipment_inventory: Array[StringName] = []
	var source_activity_equipment_stage := 0
	var external_locked := false

	func has_source_equipment(source_name: StringName) -> bool:
		return source_name in source_equipment_inventory

	func try_collect_source_equipment(source_name: StringName) -> bool:
		if source_equipment_inventory.size() >= 25:
			return false
		source_equipment_inventory.append(source_name)
		return true

	func initialize_source_activity_equipment(total_stage: int) -> void:
		source_activity_equipment_stage = total_stage

	func set_external_control_locked(_source: Object, locked: bool) -> void:
		external_locked = locked


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_transfer_doors()
	await _test_source_screen_shake()
	await _test_bull_phase_chain()
	await _test_m24_rewards_and_ending()
	await _test_m27_activity_refresh()
	print("ZMX1 enemy stage effects test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _new_controller(source_stage := 1, source_level := 1) -> StageController:
	var controller := StageController.new()
	controller.auto_start = false
	var stage := StageDefinition.new()
	stage.source_stage = source_stage
	stage.source_level = source_level
	controller.definition = stage
	root.add_child(controller)
	return controller


func _spawn(controller: StageController, definition: EnemyDefinition, spawn_id: StringName) -> AnimatedEnemy:
	return controller.call(
		&"_spawn_runtime_enemy", definition, spawn_id, Vector2.ZERO, ANIMATED_ENEMY_SCENE
	) as AnimatedEnemy


func _test_transfer_doors() -> void:
	var controller := _new_controller(1, 1)
	var door := Node2D.new()
	door.visible = false
	door.add_to_group(&"transfer_doors")
	controller.add_child(door)
	var enemy := _spawn(controller, M03, &"m03")
	await process_frame
	enemy.call(&"_notify_source_before_despawn")
	_assert(door.visible, "Boss M03 despawn should reveal StageController transfer doors.")
	controller.queue_free()
	await process_frame


func _test_source_screen_shake() -> void:
	var world := Node2D.new()
	world.position = Vector2(37.0, 19.0)
	root.add_child(world)
	var controller := StageController.new()
	controller.auto_start = false
	controller.definition = StageDefinition.new()
	world.add_child(controller)
	controller.set_physics_process(false)
	var enemy := _spawn(controller, M04, &"m04_shake")
	await process_frame
	_assert(bool(enemy.call(&"_start_attack", &"attack2")), "M04 attack2 should start for source shake replay.")
	var observed_frames := PackedInt32Array()
	var observed_strengths := PackedFloat32Array()
	var current_source_frame := [-1]
	enemy.source_screen_shake_requested.connect(
		func(strength: float) -> void:
			observed_frames.append(current_source_frame[0])
			observed_strengths.append(strength)
	)
	var accepted_strengths := PackedFloat32Array()
	controller.source_screen_shake_requested.connect(
		func(strength: float, _source_enemy: AnimatedEnemy) -> void:
			accepted_strengths.append(strength)
	)
	var baseline := world.position
	for raw_event: Variant in M04.animation_profile.get_source_events(&"attack2"):
		if not raw_event is Dictionary:
			continue
		var event := raw_event as Dictionary
		if "vControllor.shake(" not in str(event.get("source_code", "")):
			continue
		current_source_frame[0] = int(event.get("source_frame", -1))
		enemy.call(&"_on_source_event", &"attack2", event)
		var strength := observed_strengths[-1]
		_assert(world.position.is_equal_approx(baseline), "A source shake request should wait for the next 24 Hz world tick.")
		if observed_frames.size() == 1:
			controller.call(&"_on_source_screen_shake_requested", 99.0, enemy)
		controller.call(&"_advance_source_screen_shake_tick")
		_assert(
			world.position.is_equal_approx(baseline + Vector2(strength, 0.0)),
			"Source shake tick one should shift the whole world right by its exact strength."
		)
		controller.call(&"_advance_source_screen_shake_tick")
		_assert(world.position.is_equal_approx(baseline), "Source shake tick two should restore the exact world baseline.")
	var expected_frames := PackedInt32Array([5, 8, 11, 13, 16, 20, 22, 25, 30, 32, 35, 41, 46, 52, 58, 65])
	var expected_strengths := PackedFloat32Array([5, 5, 5, 5, 10, 10, 10, 10, 10, 10, 15, 15, 15, 15, 15, 15])
	_assert(observed_frames == expected_frames, "M04 attack2 should emit all 16 shakes on the exact ActionScript source frames.")
	_assert(observed_strengths == expected_strengths, "M04 attack2 should preserve source shake strengths 5/10/15.")
	_assert(accepted_strengths == expected_strengths, "StageController should accept each idle M04 shake exactly once.")

	var m24 := _spawn(controller, M24, &"m24_shake")
	await process_frame
	var m24_controller := m24.get_source_controller()
	_assert(m24_controller != null, "M24 should expose its source composite controller for shake forwarding.")
	if m24_controller != null:
		m24_controller.emit_signal(&"screen_shake_requested", 10.0)
		_assert(accepted_strengths[-1] == 10.0, "M24 hand shake should use the same StageController world-shake path.")
		controller.call(&"_advance_source_screen_shake_tick")
		_assert(world.position.is_equal_approx(baseline + Vector2(10.0, 0.0)), "M24 shake should move the same world root.")
		controller.call(&"_advance_source_screen_shake_tick")
		_assert(world.position.is_equal_approx(baseline), "M24 shake should restore the world after two source ticks.")
		controller.call(&"_on_source_screen_shake_requested", 6.0, m24)
		controller.call(&"_advance_source_screen_shake_tick")
		controller.clear_stage()
		_assert(world.position.is_equal_approx(baseline), "Stage cleanup should restore an outstanding additive shake offset.")
	world.queue_free()
	await process_frame


func _test_bull_phase_chain() -> void:
	var controller := _new_controller(4, 1)
	var m22 := _spawn(controller, M22, &"bull")
	await process_frame
	m22.call(&"_notify_source_before_despawn")
	var m23 := controller.get_enemy(&"bull_phase2") as AnimatedEnemy
	_assert(m23 != null, "StageController should create M23 from M22's source despawn effect.")
	if m23 != null:
		_assert(m23.definition.animation_profile.source_monster_id == &"M23", "Bull phase two should use M23.")
		_assert(m23.position.is_equal_approx(Vector2(1500.0, 450.0)), "M23 position should match source.")
		m23.call(&"_notify_source_before_despawn")
	var m24 := controller.get_enemy(&"bull_phase2_phase3") as AnimatedEnemy
	_assert(m24 != null, "StageController should create M24 from M23's source despawn effect.")
	if m24 != null:
		_assert(m24.definition.animation_profile.source_monster_id == &"M24", "Bull phase three should use M24.")
		_assert(m24.position.is_equal_approx(Vector2(1350.0, 300.0)), "M24 position should match source.")
	controller.queue_free()
	await process_frame


func _test_m24_rewards_and_ending() -> void:
	var controller := _new_controller(4, 1)
	var condition := BossDefeatedCondition.new()
	condition.boss_spawn_id = &"m24"
	controller.definition.end_condition = condition
	var player := TestPlayer.new()
	player.add_to_group(&"players")
	controller.add_child(player)
	var m24 := _spawn(controller, M24, &"m24")
	await process_frame
	m24.health = 0
	m24.call(&"_switch_state", 4)
	_assert(player.source_equipment_inventory == [&"jgz"], "First M24 kill should directly grant unique jgz to player one.")
	_assert(controller.source_progress.merit == 50, "First daily M24 kill should grant source merit 50.")
	_assert(controller.source_progress.m24_reward_times == 1, "M24 daily reward count should increment once.")
	m24.defeated.emit()
	_assert(not controller.is_completed, "M24 defeat should wait for the source Ending before stage completion.")
	m24.call(&"_notify_source_before_despawn")
	_assert(controller.source_ending_active, "M24 despawn should request the source Ending sequence.")
	_assert(player.external_locked, "M24 Ending should stop player controls through the existing external lock.")
	_assert(not controller.is_completed, "The active source Ending should keep stage completion deferred.")
	var ending := controller.get_node_or_null("SourceEnding")
	_assert(ending != null, "M24 despawn should create the original Ending renderer.")
	if ending != null:
		_assert(
			is_equal_approx(float(ending.call(&"get_source_duration_seconds")), 50.125),
			"Ending duration should match frame 1204 at source 24 Hz."
		)
		var clip_rect := ending.call(&"get_clip_rect") as Rect2
		_assert(
			clip_rect.is_equal_approx(Rect2(35.15, 112.65, 385.75, 340.45)),
			"Ending should preserve the source credit mask inside the 940x590 canvas."
		)
		var title_at_start: Dictionary = ending.call(&"get_track_state", &"title")
		_assert(
			Vector2(title_at_start.get("size", Vector2.ZERO)).is_equal_approx(Vector2(304.0, 24.0)),
			"Ending title should load from its one-frame sprite pack."
		)
		_assert(
			Vector2(title_at_start.get("position", Vector2.ZERO)).is_equal_approx(Vector2(27.5, 413.55)),
			"Ending title registration should match source frame one."
		)
		ending.call(&"seek_source_frame", 48)
		var title_at_48: Dictionary = ending.call(&"get_track_state", &"title")
		_assert(
			Vector2(title_at_48.get("position", Vector2.ZERO)).is_equal_approx(Vector2(27.5, 269.35)),
			"Ending title should enter the mask at the exact source frame-48 position."
		)
		ending.call(&"seek_source_frame", 86)
		var story_at_86: Dictionary = ending.call(&"get_track_state", &"story")
		_assert(bool(story_at_86.get("visible", false)), "Ending story track should begin on source frame 86.")
		_assert(
			Vector2(story_at_86.get("size", Vector2.ZERO)).is_equal_approx(Vector2(325.0, 559.0)),
			"Ending story should load from its one-frame sprite pack."
		)
		_assert(
			Vector2(story_at_86.get("position", Vector2.ZERO)).is_equal_approx(Vector2(9.1, 371.15)),
			"Ending story registration should match source frame 86."
		)

	var second := _spawn(controller, M24, &"m24_again")
	await process_frame
	second.health = 0
	second.call(&"_switch_state", 4)
	_assert(player.source_equipment_inventory == [&"jgz"], "M24 unique jgz should not duplicate across players or kills.")
	_assert(controller.source_progress.merit == 50, "M24 merit should respect the one-reward-per-day source limit.")
	if ending != null:
		ending.call(&"seek_source_frame", 1204)
	_assert(not controller.source_ending_active, "Source frame 1204 should destroy Ending like the Flash frame script.")
	_assert(not player.external_locked, "Ending teardown should release its scoped external-control lock.")
	_assert(controller.is_completed, "Stage completion should emit after the source Ending is destroyed.")
	controller.queue_free()
	await process_frame


func _test_m27_activity_refresh() -> void:
	var controller := _new_controller(4, 3)
	var player := TestPlayer.new()
	player.add_to_group(&"players")
	controller.add_child(player)
	var m27 := _spawn(controller, M27, &"m27")
	await process_frame
	m27.call(&"_notify_source_before_despawn")
	_assert(controller.source_activity_total_stage == 10, "M27 should preserve source totalStage=10 for stage four.")
	_assert(player.source_activity_equipment_stage == 10, "M27 activity refresh should reach the player inventory boundary.")
	controller.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
