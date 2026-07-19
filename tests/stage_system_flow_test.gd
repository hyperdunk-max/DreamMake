extends SceneTree

var _failed: bool = false


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_assert(
		ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/stages/zmxiyou1_stage_1.tscn",
		"The runnable game should open the curated Dream Journey 1 first stage."
	)
	_assert(change_scene_to_file("res://scenes/stages/zmxiyou1_stage_1.tscn") == OK, "Stage scene should load.")
	await process_frame
	await physics_frame

	var stage: StageController = current_scene.get_node("StageController")
	var player: PropertyActor2D = current_scene.get_node("Player")
	_assert(stage != null and player != null, "Stage controller and player should exist.")
	_assert(stage.definition.validate().is_empty(), "Stage resource should validate.")
	_assert(stage.definition.source_game == 1, "The test stage should identify Dream Journey 1 as its art source.")
	_assert(stage.definition.background_texture.resource_path.contains("zmxiyou1/stage_1"), "Stage should use curated game-one map art.")
	_assert(player.get_actor_property() == player.stats, "Player should expose CharacterStats through the shared ActorProperty contract.")
	_assert(player is PropertyActor2D, "Player should inherit the shared property actor base.")

	_assert(stage.get_active_enemy_count() == 3, "Configured two sandbags and one boss should spawn.")
	var bat_one: SandbagEnemy = stage.get_enemy(&"bat_wave_1")
	var bat_two: SandbagEnemy = stage.get_enemy(&"bat_wave_2")
	var boss: SandbagEnemy = stage.get_enemy(&"boss")
	_assert(bat_one != null and bat_two != null and boss != null, "Every configured spawn id should resolve.")
	_assert(bat_one is PropertyActor2D and boss is PropertyActor2D, "Monsters and player should inherit the same property actor base.")
	_assert(bat_one.get_actor_property() is ActorProperty, "Sandbag should receive a duplicated ActorProperty.")
	_assert(bat_one.health == 80 and bat_one.get_defense() == 1, "Sandbag attributes should come from its resource.")
	_assert(boss.health == 600 and boss.get_defense() == 4, "Boss attributes should come from its resource.")
	_assert(bat_one.position.x == 470.0 and bat_two.position.x == 590.0, "Formation count and spacing should control spawn positions.")
	_assert(not bat_one.has_method("request_test_attack"), "The first monster implementation should have no AI attack API.")
	_assert(stage.definition.end_condition is BossDefeatedCondition, "First stage should use the extensible boss condition resource.")

	var completed: Dictionary = {"count": 0}
	stage.stage_completed.connect(func(_definition: StageDefinition) -> void: completed["count"] = int(completed["count"]) + 1)
	bat_one.take_hit(9999, Vector2.ZERO)
	_assert(not stage.is_completed, "Defeating a normal sandbag must not complete the boss stage.")
	boss.take_hit(9999, Vector2.ZERO)
	_assert(stage.is_completed, "Defeating the configured boss should complete the stage.")
	_assert(int(completed["count"]) == 1, "Stage completion should emit exactly once.")
	_assert(stage.defeated_spawn_ids.has(&"boss"), "Runtime completion context should record the boss spawn id.")

	var provenance_text: String = FileAccess.get_file_as_string("res://assets/selected/zmxiyou1/provenance.json")
	var provenance: Variant = JSON.parse_string(provenance_text)
	_assert(provenance is Dictionary, "Curated game-one assets should have a machine-readable provenance manifest.")
	if provenance is Dictionary:
		_assert(Array(provenance.get("selection", [])).size() == 5, "Provenance should cover every selected stage and monster asset.")

	if _failed:
		quit(1)
	else:
		print("PASS: shared properties, configurable spawns, game-one art, and boss completion.")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
