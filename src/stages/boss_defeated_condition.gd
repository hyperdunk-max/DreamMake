class_name BossDefeatedCondition
extends StageEndCondition

## Current first-stage rule: complete after the configured boss spawn dies.

@export var boss_spawn_id: StringName = &"boss"


func is_satisfied(_active_enemies: Dictionary, defeated_spawn_ids: Array[StringName]) -> bool:
	return defeated_spawn_ids.has(boss_spawn_id)


func get_description() -> String:
	return "击败首领"


func validate(stage: StageDefinition) -> PackedStringArray:
	var errors: PackedStringArray = []
	if boss_spawn_id.is_empty():
		errors.append("Boss end condition needs a spawn id.")
		return errors
	var found: bool = false
	for spawn: EnemySpawnDefinition in stage.enemy_spawns:
		if spawn != null and spawn.spawn_id == boss_spawn_id:
			found = true
			if spawn.enemy == null or not spawn.enemy.is_boss:
				errors.append("End-condition spawn '%s' must use a boss definition." % boss_spawn_id)
			if spawn.count != 1:
				errors.append("Boss end-condition spawn '%s' must have count 1." % boss_spawn_id)
			break
	if not found:
		errors.append("Boss spawn '%s' does not exist in the stage." % boss_spawn_id)
	return errors
