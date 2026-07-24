class_name StageController
extends Node2D

## Spawns configured enemies and evaluates a pluggable end-condition resource.

signal stage_started(stage: StageDefinition)
signal enemy_spawned(enemy: SandbagEnemy, spawn_id: StringName)
signal enemy_defeated(spawn_id: StringName, enemy: SandbagEnemy)
signal boss_spawned(enemy: SandbagEnemy)
signal stage_completed(stage: StageDefinition)
signal transfer_doors_revealed(source_enemy: SandbagEnemy)
signal source_followup_spawned(enemy: SandbagEnemy, source_enemy: SandbagEnemy)
signal source_unique_reward_resolved(source_name: StringName, granted: bool)
signal source_merit_rewarded(amount: int, total: int)
signal source_activity_refresh_requested(total_stage: int)
signal source_ending_requested(source_enemy: SandbagEnemy)
signal source_ending_finished
signal source_reward_message_requested(message: String)
signal source_screen_shake_requested(strength: float, source_enemy: AnimatedEnemy)

const DEFAULT_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/sandbag_enemy.tscn")
const ANIMATED_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/animated_enemy.tscn")
const SOURCE_ENDING_OVERLAY_SCRIPT: Script = preload("res://src/stages/zmxiyou1_ending_overlay.gd")
const SOURCE_TICK_RATE := 24.0

@export var definition: StageDefinition
@export var auto_start: bool = true
@export var enemy_scene: PackedScene = DEFAULT_ENEMY_SCENE
@export var source_progress: Zmxiyou1SourceProgress
@export var source_screen_shake_target_path: NodePath = NodePath("..")

var active_enemies: Dictionary = {}
var defeated_spawn_ids: Array[StringName] = []
var is_running: bool = false
var is_completed: bool = false
var source_ending_active := false
var source_activity_total_stage := 0

var _background: TextureRect
var _ground: TextureRect
var _enemies_root: Node2D
var _pending_source_spawn_ids: Dictionary = {}
var _active_source_chain_ids: Dictionary = {}
var _source_ending_overlay: CanvasLayer
var _source_screen_shake_value := 0.0
var _source_screen_shake_offset_x := 0.0
var _source_screen_shake_tick_accumulator := 0.0
var _source_screen_shake_target: Node2D


func _ready() -> void:
	_build_runtime_nodes()
	if source_progress == null:
		source_progress = Zmxiyou1SourceProgress.new()
	if auto_start:
		call_deferred(&"start_stage")


func _physics_process(delta: float) -> void:
	if is_zero_approx(_source_screen_shake_value):
		_source_screen_shake_tick_accumulator = 0.0
		return
	_source_screen_shake_tick_accumulator += maxf(0.0, delta) * SOURCE_TICK_RATE
	var pending_ticks := int(_source_screen_shake_tick_accumulator)
	_source_screen_shake_tick_accumulator -= pending_ticks
	for _tick: int in pending_ticks:
		_advance_source_screen_shake_tick()


func start_stage() -> bool:
	if is_running or definition == null:
		return false
	var errors: PackedStringArray = definition.validate()
	if not errors.is_empty():
		for error: String in errors:
			push_error(error)
		return false
	clear_stage()
	is_running = true
	is_completed = false
	_apply_art()
	stage_started.emit(definition)
	_spawn_all()
	return true


func clear_stage() -> void:
	_cancel_source_screen_shake()
	if _source_ending_overlay != null and is_instance_valid(_source_ending_overlay):
		_source_ending_overlay.queue_free()
	_source_ending_overlay = null
	_set_source_ending_control_lock(false)
	for child: Node in _enemies_root.get_children():
		child.queue_free()
	active_enemies.clear()
	defeated_spawn_ids.clear()
	_pending_source_spawn_ids.clear()
	_active_source_chain_ids.clear()
	is_running = false
	is_completed = false
	source_ending_active = false
	source_activity_total_stage = 0


func get_enemy(spawn_id: StringName) -> SandbagEnemy:
	return active_enemies.get(spawn_id) as SandbagEnemy


func get_active_enemy_count() -> int:
	return active_enemies.size()


func _build_runtime_nodes() -> void:
	_background = TextureRect.new()
	_background.name = "Background"
	_background.z_index = -100
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_background)
	_ground = TextureRect.new()
	_ground.name = "GroundVisual"
	_ground.z_index = -20
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ground.stretch_mode = TextureRect.STRETCH_TILE
	_ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_ground)
	_enemies_root = Node2D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)


func _apply_art() -> void:
	_background.texture = definition.background_texture
	_background.position = Vector2.ZERO
	_background.size = Vector2(definition.viewport_size.x, definition.floor_y)
	_ground.texture = definition.ground_texture
	_ground.position = Vector2(0.0, definition.floor_y)
	_ground.size = Vector2(definition.viewport_size.x, definition.viewport_size.y - definition.floor_y)


func _spawn_all() -> void:
	for spawn: EnemySpawnDefinition in definition.enemy_spawns:
		if spawn.initial_delay_seconds > 0.0:
			await get_tree().create_timer(spawn.initial_delay_seconds).timeout
			if not is_instance_valid(self) or not is_running:
				return
		for index: int in range(spawn.count):
			_spawn_one(spawn, index)


func _spawn_one(spawn: EnemySpawnDefinition, index: int) -> SandbagEnemy:
	var runtime_id: StringName = spawn.spawn_id
	if spawn.count > 1:
		runtime_id = StringName("%s_%d" % [spawn.spawn_id, index + 1])
	return _spawn_runtime_enemy(
		spawn.enemy,
		runtime_id,
		spawn.position + spawn.spacing * index,
		enemy_scene
	)


func _spawn_runtime_enemy(
	enemy_definition: EnemyDefinition,
	runtime_id: StringName,
	spawn_position: Vector2,
	packed_scene: PackedScene
) -> SandbagEnemy:
	var enemy: SandbagEnemy = packed_scene.instantiate() as SandbagEnemy
	if enemy == null:
		push_error("Stage enemy scene must instantiate SandbagEnemy.")
		return null
	enemy.name = str(runtime_id)
	enemy.spawn_id = runtime_id
	enemy.definition = enemy_definition
	enemy.set_source_stage_context(definition.source_stage, definition.source_level)
	enemy.defeated.connect(_on_enemy_defeated.bind(runtime_id, enemy), CONNECT_ONE_SHOT)
	if enemy is AnimatedEnemy:
		(enemy as AnimatedEnemy).source_stage_effect_requested.connect(_on_source_stage_effect_requested)
		(enemy as AnimatedEnemy).source_screen_shake_requested.connect(
			_on_source_screen_shake_requested.bind(enemy as AnimatedEnemy)
		)
	_enemies_root.add_child(enemy)
	enemy.position = spawn_position
	active_enemies[runtime_id] = enemy
	enemy_spawned.emit(enemy, runtime_id)
	if enemy.is_boss():
		boss_spawned.emit(enemy)
	return enemy


func _on_enemy_defeated(spawn_id: StringName, enemy: SandbagEnemy) -> void:
	if _definition_defers_completion(enemy.definition):
		_pending_source_spawn_ids[spawn_id] = true
	_active_source_chain_ids.erase(spawn_id)
	active_enemies.erase(spawn_id)
	defeated_spawn_ids.append(spawn_id)
	enemy_defeated.emit(spawn_id, enemy)
	_evaluate_end_condition()


func _evaluate_end_condition() -> void:
	if is_completed or definition.end_condition == null:
		return
	if (
		source_ending_active
		or not _pending_source_spawn_ids.is_empty()
		or not _active_source_chain_ids.is_empty()
	):
		return
	if definition.end_condition.is_satisfied(active_enemies, defeated_spawn_ids):
		is_completed = true
		is_running = false
		stage_completed.emit(definition)


func _on_source_stage_effect_requested(effect: Dictionary, source_enemy: AnimatedEnemy) -> void:
	match StringName(effect.get("type", &"")):
		&"reveal_transfer_doors":
			_reveal_transfer_doors(source_enemy)
		&"spawn_monster":
			_spawn_source_followup(effect, source_enemy)
		&"grant_unique_equipment":
			_grant_source_unique_equipment(StringName(effect.get("source_name", &"")))
		&"grant_daily_merit":
			_grant_m24_merit()
		&"refresh_activity_equipment":
			_refresh_source_activity_equipment(effect)
		&"show_ending_stop_controls":
			_show_source_ending(source_enemy)


func _on_source_screen_shake_requested(strength: float, source_enemy: AnimatedEnemy) -> void:
	# ViewControllor.shake() only accepts a request while shakeVal is zero.
	if is_zero_approx(strength) or not is_zero_approx(_source_screen_shake_value):
		return
	_source_screen_shake_target = _resolve_source_screen_shake_target()
	_source_screen_shake_value = strength
	_source_screen_shake_tick_accumulator = 0.0
	source_screen_shake_requested.emit(strength, source_enemy)


func _advance_source_screen_shake_tick() -> void:
	if is_zero_approx(_source_screen_shake_value):
		return
	var tick_offset := _source_screen_shake_value
	if _source_screen_shake_target != null and is_instance_valid(_source_screen_shake_target):
		_source_screen_shake_target.position.x += tick_offset
		_source_screen_shake_offset_x += tick_offset
	if _source_screen_shake_value > 0.0:
		_source_screen_shake_value *= -1.0
	else:
		_source_screen_shake_value = 0.0
		_source_screen_shake_offset_x = 0.0
		_source_screen_shake_target = null


func _resolve_source_screen_shake_target() -> Node2D:
	var configured := get_node_or_null(source_screen_shake_target_path) as Node2D
	return configured if configured != null else self


func _cancel_source_screen_shake() -> void:
	if (
		_source_screen_shake_target != null
		and is_instance_valid(_source_screen_shake_target)
		and not is_zero_approx(_source_screen_shake_offset_x)
	):
		_source_screen_shake_target.position.x -= _source_screen_shake_offset_x
	_source_screen_shake_value = 0.0
	_source_screen_shake_offset_x = 0.0
	_source_screen_shake_tick_accumulator = 0.0
	_source_screen_shake_target = null


func _exit_tree() -> void:
	_cancel_source_screen_shake()


func _reveal_transfer_doors(source_enemy: SandbagEnemy) -> void:
	for door: Node in get_tree().get_nodes_in_group(&"transfer_doors"):
		if door is CanvasItem:
			(door as CanvasItem).visible = true
		if door.has_method(&"set_source_enabled"):
			door.call(&"set_source_enabled", true)
	transfer_doors_revealed.emit(source_enemy)


func _spawn_source_followup(effect: Dictionary, source_enemy: AnimatedEnemy) -> void:
	var definition_path := str(effect.get("definition_path", ""))
	var followup_definition := load(definition_path) as EnemyDefinition
	if followup_definition == null:
		push_error("Cannot load source follow-up enemy: %s" % definition_path)
		return
	var suffix := str(effect.get("spawn_id_suffix", "followup"))
	var runtime_id := StringName("%s_%s" % [source_enemy.spawn_id, suffix])
	var serial := 2
	while active_enemies.has(runtime_id):
		runtime_id = StringName("%s_%s_%d" % [source_enemy.spawn_id, suffix, serial])
		serial += 1
	var spawn_position := Vector2(effect.get("position", source_enemy.global_position))
	var scene := ANIMATED_ENEMY_SCENE if followup_definition.animation_profile != null else enemy_scene
	var followup := _spawn_runtime_enemy(followup_definition, runtime_id, spawn_position, scene)
	if followup == null:
		return
	_pending_source_spawn_ids.erase(source_enemy.spawn_id)
	_active_source_chain_ids[runtime_id] = true
	source_followup_spawned.emit(followup, source_enemy)
	_evaluate_end_condition()


func _grant_source_unique_equipment(source_name: StringName) -> void:
	var players := get_tree().get_nodes_in_group(&"players")
	var already_owned := false
	for player: Node in players:
		if player.has_method(&"has_source_equipment") and bool(player.call(&"has_source_equipment", source_name)):
			already_owned = true
			break
	var granted := already_owned
	if not already_owned and not players.is_empty():
		var first_player := players[0]
		if first_player.has_method(&"try_collect_source_equipment"):
			granted = bool(first_player.call(&"try_collect_source_equipment", source_name))
	source_unique_reward_resolved.emit(source_name, granted)
	if already_owned:
		return
	if granted:
		source_reward_message_requested.emit("获得 金刚琢")
	else:
		source_reward_message_requested.emit("背包已满，无法获得 金刚琢")


func _grant_m24_merit() -> void:
	if source_progress == null:
		source_progress = Zmxiyou1SourceProgress.new()
	var amount := source_progress.grant_m24_daily_reward()
	if amount <= 0:
		return
	source_merit_rewarded.emit(amount, source_progress.merit)
	source_reward_message_requested.emit("获得 战功 + %d" % amount)


func _refresh_source_activity_equipment(effect: Dictionary) -> void:
	var stage := int(effect.get("source_stage", definition.source_stage))
	var level := int(effect.get("source_level", definition.source_level))
	source_activity_total_stage = (stage - 1) * 3 + level if stage < 4 else 10
	for player: Node in get_tree().get_nodes_in_group(&"players"):
		if player.has_method(&"initialize_source_activity_equipment"):
			player.call(&"initialize_source_activity_equipment", source_activity_total_stage)
	source_activity_refresh_requested.emit(source_activity_total_stage)


func _show_source_ending(source_enemy: SandbagEnemy) -> void:
	if source_ending_active:
		return
	_pending_source_spawn_ids.erase(source_enemy.spawn_id)
	source_ending_active = true
	_set_source_ending_control_lock(true)
	_source_ending_overlay = SOURCE_ENDING_OVERLAY_SCRIPT.new() as CanvasLayer
	_source_ending_overlay.name = "SourceEnding"
	_source_ending_overlay.connect(&"finished", _on_source_ending_finished, CONNECT_ONE_SHOT)
	add_child(_source_ending_overlay)
	source_ending_requested.emit(source_enemy)


func _on_source_ending_finished() -> void:
	_source_ending_overlay = null
	source_ending_active = false
	_set_source_ending_control_lock(false)
	source_ending_finished.emit()
	_evaluate_end_condition()


func _set_source_ending_control_lock(locked: bool) -> void:
	for player: Node in get_tree().get_nodes_in_group(&"players"):
		if player.has_method(&"set_external_control_locked"):
			player.call(&"set_external_control_locked", self, locked)


func _definition_defers_completion(enemy_definition: EnemyDefinition) -> bool:
	if enemy_definition == null:
		return false
	for effect: Dictionary in enemy_definition.source_despawn_effects:
		if StringName(effect.get("type", &"")) in [&"spawn_monster", &"show_ending_stop_controls"]:
			return true
	return false
