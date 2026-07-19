class_name EnemySpawnDefinition
extends Resource

## One configurable spawn entry. Count and spacing allow simple formations.

@export var spawn_id: StringName = &""
@export var enemy: EnemyDefinition
@export var position: Vector2 = Vector2.ZERO
@export_range(1, 32, 1) var count: int = 1
@export var spacing: Vector2 = Vector2(72.0, 0.0)
@export_range(0.0, 30.0, 0.05) var initial_delay_seconds: float = 0.0


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if spawn_id.is_empty():
		errors.append("Spawn id cannot be empty.")
	if enemy == null:
		errors.append("Spawn '%s' has no enemy definition." % spawn_id)
	else:
		errors.append_array(enemy.validate())
	if count <= 0:
		errors.append("Spawn '%s' count must be positive." % spawn_id)
	return errors
