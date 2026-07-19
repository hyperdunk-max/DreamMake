class_name ActorProperty
extends Resource

## Shared property model for every combat actor, regardless of source game.
## CharacterStats remains a compatibility subtype for existing role resources.

@export_group("Vitals")
@export var max_health: int = 100
@export var max_mana: int = 0
@export var hp_regen: int = 0
@export var mp_regen: int = 0

@export_group("Combat")
@export var attack: int = 10
@export var defense: int = 0
@export_range(0.0, 1.0, 0.001) var crit_rate: float = 0.0
@export_range(0.0, 1.0, 0.001) var dodge_rate: float = 0.0
@export_range(0.0, 1.0, 0.001) var magic_resist: float = 0.0

@export_group("Movement")
@export var move_speed_bonus: int = 0

const BONUS_KEYS: Array[StringName] = [
	&"max_health", &"max_mana", &"attack", &"defense",
	&"crit_rate", &"dodge_rate", &"hp_regen", &"mp_regen",
	&"magic_resist", &"move_speed_bonus",
]

var _bonus: Dictionary = {}


func get_effective_attack() -> int:
	return attack + int(_bonus.get(&"attack", 0))


func get_effective_defense() -> int:
	return defense + int(_bonus.get(&"defense", 0))


func get_effective_max_health() -> int:
	return max_health + int(_bonus.get(&"max_health", 0))


func get_effective_max_mana() -> int:
	return max_mana + int(_bonus.get(&"max_mana", 0))


func get_effective_crit_rate() -> float:
	return crit_rate + float(_bonus.get(&"crit_rate", 0.0))


func get_effective_dodge_rate() -> float:
	return dodge_rate + float(_bonus.get(&"dodge_rate", 0.0))


func get_effective_hp_regen() -> int:
	return hp_regen + int(_bonus.get(&"hp_regen", 0))


func get_effective_mp_regen() -> int:
	return mp_regen + int(_bonus.get(&"mp_regen", 0))


func get_effective_magic_resist() -> float:
	return magic_resist + float(_bonus.get(&"magic_resist", 0.0))


func get_effective_move_speed_bonus() -> int:
	return move_speed_bonus + int(_bonus.get(&"move_speed_bonus", 0))


func apply_bonus(bonus: Dictionary) -> void:
	for key: StringName in BONUS_KEYS:
		if bonus.has(key):
			_bonus[key] = _bonus.get(key, 0) + bonus[key]


func remove_bonus(bonus: Dictionary) -> void:
	for key: StringName in BONUS_KEYS:
		if bonus.has(key):
			_bonus[key] = _bonus.get(key, 0) - bonus[key]


func reset_bonuses() -> void:
	_bonus.clear()


func get_bonuses() -> Dictionary:
	return _bonus.duplicate()


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if max_health <= 0:
		errors.append("max_health must be positive.")
	if max_mana < 0:
		errors.append("max_mana cannot be negative.")
	if attack < 0 or defense < 0:
		errors.append("attack and defense cannot be negative.")
	if crit_rate < 0.0 or crit_rate > 1.0:
		errors.append("crit_rate must be between 0 and 1.")
	if dodge_rate < 0.0 or dodge_rate > 1.0:
		errors.append("dodge_rate must be between 0 and 1.")
	if magic_resist < 0.0 or magic_resist > 1.0:
		errors.append("magic_resist must be between 0 and 1.")
	return errors


static func calculate_physical_damage(raw_damage: int, target_defense: int) -> int:
	return maxi(1, raw_damage - target_defense)


static func calculate_magic_damage(raw_damage: int, target_magic_resist: float) -> int:
	var reduction: int = clampi(roundi(raw_damage * target_magic_resist), 0, raw_damage - 1)
	return maxi(1, raw_damage - reduction)


func roll_crit() -> bool:
	return randf() < get_effective_crit_rate()


func roll_dodge() -> bool:
	return randf() < get_effective_dodge_rate()
