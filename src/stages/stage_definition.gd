class_name StageDefinition
extends Resource

## Complete data definition for a stage. Runtime code contains no hard-coded
## monster positions or completion rules.

@export var stage_id: StringName = &""
@export var display_name: String = ""
@export var source_game: int = 1
@export_group("Source Context")
@export_range(1, 99, 1) var source_stage: int = 1
@export_range(1, 99, 1) var source_level: int = 1
@export_group("Presentation and Layout")
@export var background_texture: Texture2D
@export var ground_texture: Texture2D
@export var viewport_size: Vector2 = Vector2(940.0, 590.0)
@export var floor_y: float = 515.0
@export var player_spawn_position: Vector2 = Vector2(160.0, 515.0)
@export var enemy_spawns: Array[EnemySpawnDefinition] = []
@export var end_condition: StageEndCondition


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if stage_id.is_empty():
		errors.append("Stage id cannot be empty.")
	if display_name.is_empty():
		errors.append("Stage '%s' needs a display name." % stage_id)
	if source_game <= 0:
		errors.append("Stage '%s' source_game must be positive." % stage_id)
	if source_stage <= 0 or source_level <= 0:
		errors.append("Stage '%s' source stage and level must be positive." % stage_id)
	if background_texture == null:
		errors.append("Stage '%s' needs a background texture." % stage_id)
	if ground_texture == null:
		errors.append("Stage '%s' needs a ground texture." % stage_id)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		errors.append("Stage '%s' viewport size must be positive." % stage_id)
	var spawn_ids: Dictionary = {}
	for spawn: EnemySpawnDefinition in enemy_spawns:
		if spawn == null:
			errors.append("Stage '%s' contains a null spawn." % stage_id)
			continue
		errors.append_array(spawn.validate())
		if spawn_ids.has(spawn.spawn_id):
			errors.append("Stage '%s' repeats spawn id '%s'." % [stage_id, spawn.spawn_id])
		spawn_ids[spawn.spawn_id] = true
	if end_condition == null:
		errors.append("Stage '%s' has no end condition." % stage_id)
	else:
		errors.append_array(end_condition.validate(self))
	return errors
