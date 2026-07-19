class_name SandbagEnemy
extends PropertyActor2D

## Configurable, no-AI enemy used for stage and combat validation.

signal health_changed(current: int, maximum: int)
signal hit_received(damage: int)
signal defeated

const GRAVITY: float = 1450.0

@export var definition: EnemyDefinition
@export var spawn_id: StringName = &""

var health: int = 1
var defeated_once: bool = false
var hit_flash_seconds: float = 0.0
var stun_seconds: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if definition == null:
		push_error("SandbagEnemy requires an EnemyDefinition.")
		return
	configure(definition)


func configure(value: EnemyDefinition) -> void:
	definition = value
	if not is_node_ready():
		return
	var errors: PackedStringArray = definition.validate()
	if not errors.is_empty():
		for error: String in errors:
			push_error(error)
		return
	bind_actor_property(definition.property_template, true)
	health = actor_property.get_effective_max_health()
	sprite.texture = definition.texture
	sprite.scale = definition.visual_scale
	sprite.position = definition.visual_offset
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = definition.collision_size
	collision_shape.shape = shape
	collision_shape.position.y = -definition.collision_size.y * 0.5
	add_to_group(&"enemies")
	if definition.is_boss:
		add_to_group(&"bosses")
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	move_and_slide()
	hit_flash_seconds = maxf(0.0, hit_flash_seconds - delta)
	stun_seconds = maxf(0.0, stun_seconds - delta)
	sprite.modulate = Color(1.0, 0.45, 0.45) if hit_flash_seconds > 0.0 else Color.WHITE


func take_hit(damage: int, impulse: Vector2) -> void:
	if health <= 0 or actor_property == null:
		return
	var resolved_damage: int = maxi(1, damage)
	health = maxi(0, health - resolved_damage)
	velocity = impulse
	hit_flash_seconds = 0.09
	hit_received.emit(resolved_damage)
	health_changed.emit(health, actor_property.get_effective_max_health())
	queue_redraw()
	if health == 0 and not defeated_once:
		defeated_once = true
		collision_shape.set_deferred(&"disabled", true)
		defeated.emit()


func get_defense() -> int:
	return get_effective_defense()


func apply_stun(seconds: float) -> void:
	stun_seconds = maxf(stun_seconds, seconds)
	velocity = Vector2.ZERO


func is_boss() -> bool:
	return definition != null and definition.is_boss


func get_display_name() -> String:
	return definition.display_name if definition != null else ""


func _draw() -> void:
	if definition == null or actor_property == null:
		return
	var bar_width: float = 82.0 if definition.is_boss else 54.0
	var y: float = -definition.collision_size.y - 18.0
	draw_rect(Rect2(-bar_width * 0.5, y, bar_width, 7.0), Color(0.12, 0.08, 0.06, 0.9), true)
	var ratio: float = float(health) / float(actor_property.get_effective_max_health())
	draw_rect(Rect2(-bar_width * 0.5 + 1.0, y + 1.0, (bar_width - 2.0) * ratio, 5.0), Color("c94036"), true)
