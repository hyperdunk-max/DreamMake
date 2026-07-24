class_name EnemyDefinition
extends Resource

## Source-agnostic enemy configuration. Art may come from any game version.

@export var enemy_id: StringName = &""
@export var display_name: String = ""
@export var source_game: int = 1
@export var property_template: ActorProperty
@export var texture: Texture2D
@export var animation_profile: EnemyAnimationProfile
@export var source_controller_scene: PackedScene
@export_group("Source Context")
@export_range(1, 99, 1) var source_default_stage: int = 1
@export_range(1, 99, 1) var source_default_level: int = 1
@export_group("Visuals and Collision")
@export var visual_scale: Vector2 = Vector2.ONE
@export var visual_offset: Vector2 = Vector2.ZERO
@export var collision_size: Vector2 = Vector2(42.0, 58.0)
@export var is_boss: bool = false
@export_group("Combat AI")
@export var move_speed: float = 60.0
@export var detection_range: float = 720.0
@export var default_attack_range: float = 78.0
@export var default_attack_cooldown: float = 1.0
@export var melee_hitbox_size: Vector2 = Vector2(72.0, 58.0)
@export var melee_hitbox_offset: Vector2 = Vector2(44.0, -32.0)
@export var death_despawn_delay: float = 0.25
@export_group("Source Runtime Variants")
@export var source_level_threshold: int = -1
@export var source_default_player_level: int = 1
@export var source_low_level_stats: Dictionary = {}
@export var source_high_level_stats: Dictionary = {}
@export_group("Source Stage Effects")
@export var source_death_start_effects: Array[Dictionary] = []
@export var source_despawn_effects: Array[Dictionary] = []


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if enemy_id.is_empty():
		errors.append("Enemy id cannot be empty.")
	if display_name.is_empty():
		errors.append("Enemy '%s' needs a display name." % enemy_id)
	if source_game <= 0:
		errors.append("Enemy '%s' source_game must be positive." % enemy_id)
	if source_default_stage <= 0 or source_default_level <= 0:
		errors.append("Enemy '%s' source stage and level defaults must be positive." % enemy_id)
	if property_template == null:
		errors.append("Enemy '%s' has no property template." % enemy_id)
	else:
		errors.append_array(property_template.validate())
	if texture == null and animation_profile == null:
		errors.append("Enemy '%s' has neither a source texture nor an animation profile." % enemy_id)
	if animation_profile != null:
		errors.append_array(animation_profile.validate())
	if collision_size.x <= 0.0 or collision_size.y <= 0.0:
		errors.append("Enemy '%s' collision size must be positive." % enemy_id)
	if move_speed < 0.0:
		errors.append("Enemy '%s' move_speed cannot be negative." % enemy_id)
	if detection_range <= 0.0 or default_attack_range <= 0.0:
		errors.append("Enemy '%s' detection and attack ranges must be positive." % enemy_id)
	if default_attack_cooldown < 0.0:
		errors.append("Enemy '%s' attack cooldown cannot be negative." % enemy_id)
	if melee_hitbox_size.x <= 0.0 or melee_hitbox_size.y <= 0.0:
		errors.append("Enemy '%s' melee hitbox size must be positive." % enemy_id)
	if death_despawn_delay < 0.0:
		errors.append("Enemy '%s' death despawn delay cannot be negative." % enemy_id)
	if source_level_threshold >= 0:
		if source_default_player_level <= 0:
			errors.append("Enemy '%s' source_default_player_level must be positive." % enemy_id)
		if source_low_level_stats.is_empty() or source_high_level_stats.is_empty():
			errors.append("Enemy '%s' needs both source level variants." % enemy_id)
	for timing: String in ["death_start", "despawn"]:
		var effects := source_death_start_effects if timing == "death_start" else source_despawn_effects
		for effect: Dictionary in effects:
			if str(effect.get("type", "")).is_empty():
				errors.append("Enemy '%s' has a %s stage effect without a type." % [enemy_id, timing])
	return errors
