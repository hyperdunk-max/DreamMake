class_name ShasengVoodooDoll
extends CharacterBody2D

signal expired

const FOLLOW_SPEED := 72.0
const FOLLOW_DISTANCE := 100.0

var health := 9_999_999
var max_health := 9_999_999
var bound_target: Node2D
var source_actor: Node2D
var seconds_left := 10.0


func configure(target: Node2D, source: Node2D, duration_seconds: float) -> void:
	bound_target = target
	source_actor = source
	seconds_left = duration_seconds
	collision_layer = 4
	collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 96)
	collision.shape = shape
	add_child(collision)


func _physics_process(delta: float) -> void:
	seconds_left -= delta
	if seconds_left <= 0.0 or bound_target == null or not is_instance_valid(bound_target):
		expired.emit()
		queue_free()
		return
	var delta_to_target := bound_target.global_position - global_position
	if delta_to_target.length() > FOLLOW_DISTANCE:
		velocity = delta_to_target.normalized() * FOLLOW_SPEED
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func take_hit(damage: int, _impulse: Vector2) -> void:
	if damage <= 0 or bound_target == null or not is_instance_valid(bound_target):
		return
	health = maxi(1, health - damage)
	if bound_target.has_method("take_hit"):
		bound_target.take_hit(damage, Vector2.ZERO)
