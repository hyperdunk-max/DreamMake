class_name EnemyDefinition
extends Resource

## Source-agnostic enemy configuration. Art may come from any game version.

@export var enemy_id: StringName = &""
@export var display_name: String = ""
@export var source_game: int = 1
@export var property_template: ActorProperty
@export var texture: Texture2D
@export var animation_profile: EnemyAnimationProfile
@export var visual_scale: Vector2 = Vector2.ONE
@export var visual_offset: Vector2 = Vector2.ZERO
@export var collision_size: Vector2 = Vector2(42.0, 58.0)
@export var is_boss: bool = false


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if enemy_id.is_empty():
		errors.append("Enemy id cannot be empty.")
	if display_name.is_empty():
		errors.append("Enemy '%s' needs a display name." % enemy_id)
	if source_game <= 0:
		errors.append("Enemy '%s' source_game must be positive." % enemy_id)
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
	return errors
