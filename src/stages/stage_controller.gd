class_name StageController
extends Node2D

## Spawns configured enemies and evaluates a pluggable end-condition resource.

signal stage_started(stage: StageDefinition)
signal enemy_spawned(enemy: SandbagEnemy, spawn_id: StringName)
signal enemy_defeated(spawn_id: StringName, enemy: SandbagEnemy)
signal boss_spawned(enemy: SandbagEnemy)
signal stage_completed(stage: StageDefinition)

const DEFAULT_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/sandbag_enemy.tscn")

@export var definition: StageDefinition
@export var auto_start: bool = true
@export var enemy_scene: PackedScene = DEFAULT_ENEMY_SCENE

var active_enemies: Dictionary = {}
var defeated_spawn_ids: Array[StringName] = []
var is_running: bool = false
var is_completed: bool = false

var _background: TextureRect
var _ground: TextureRect
var _enemies_root: Node2D


func _ready() -> void:
	_build_runtime_nodes()
	if auto_start:
		call_deferred(&"start_stage")


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
	for child: Node in _enemies_root.get_children():
		child.queue_free()
	active_enemies.clear()
	defeated_spawn_ids.clear()
	is_running = false
	is_completed = false


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
	var enemy: SandbagEnemy = enemy_scene.instantiate() as SandbagEnemy
	if enemy == null:
		push_error("Stage enemy scene must instantiate SandbagEnemy.")
		return null
	var runtime_id: StringName = spawn.spawn_id
	if spawn.count > 1:
		runtime_id = StringName("%s_%d" % [spawn.spawn_id, index + 1])
	enemy.name = str(runtime_id)
	enemy.spawn_id = runtime_id
	enemy.definition = spawn.enemy
	_enemies_root.add_child(enemy)
	enemy.position = spawn.position + spawn.spacing * index
	enemy.defeated.connect(_on_enemy_defeated.bind(runtime_id, enemy), CONNECT_ONE_SHOT)
	active_enemies[runtime_id] = enemy
	enemy_spawned.emit(enemy, runtime_id)
	if enemy.is_boss():
		boss_spawned.emit(enemy)
	return enemy


func _on_enemy_defeated(spawn_id: StringName, enemy: SandbagEnemy) -> void:
	active_enemies.erase(spawn_id)
	defeated_spawn_ids.append(spawn_id)
	enemy_defeated.emit(spawn_id, enemy)
	_evaluate_end_condition()


func _evaluate_end_condition() -> void:
	if is_completed or definition.end_condition == null:
		return
	if definition.end_condition.is_satisfied(active_enemies, defeated_spawn_ids):
		is_completed = true
		is_running = false
		stage_completed.emit(definition)
