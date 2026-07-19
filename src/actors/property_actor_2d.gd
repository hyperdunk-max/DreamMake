class_name PropertyActor2D
extends CharacterBody2D

## Shared actor base that exposes the same ActorProperty contract to players,
## monsters, bosses, pets, and future cross-version actors.

var actor_property: ActorProperty


func bind_actor_property(value: ActorProperty, duplicate_resource: bool = false) -> ActorProperty:
	if value == null:
		actor_property = ActorProperty.new()
	elif duplicate_resource:
		actor_property = value.duplicate(true) as ActorProperty
	else:
		actor_property = value
	return actor_property


func get_actor_property() -> ActorProperty:
	return actor_property


func get_effective_attack() -> int:
	return actor_property.get_effective_attack() if actor_property != null else 0


func get_effective_defense() -> int:
	return actor_property.get_effective_defense() if actor_property != null else 0


func get_effective_max_health() -> int:
	return actor_property.get_effective_max_health() if actor_property != null else 1
