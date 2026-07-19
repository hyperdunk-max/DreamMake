class_name StageEndCondition
extends Resource

## Extensible end-condition strategy. Subclasses evaluate stage runtime state.


func is_satisfied(_active_enemies: Dictionary, _defeated_spawn_ids: Array[StringName]) -> bool:
	return false


func get_description() -> String:
	return "未配置结束条件"


func validate(_stage: StageDefinition) -> PackedStringArray:
	return PackedStringArray()
