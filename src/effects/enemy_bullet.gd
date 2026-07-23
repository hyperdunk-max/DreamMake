class_name EnemyBullet
extends Area2D

## Enemy bullet: plays sprite sheet animation, hits player, self-destructs.
## Parameters are set via configure() using per-action bullet specs from the animation profile.

signal bullet_destroyed

var _damage: int = 20
var _knockback_x: float = 100.0
var _knockback_y: float = -80.0
var _max_hits: int = 40

var _hits: int = 0
var _hit_targets: Array = []
var _anim_frames: SpriteFrames
var _bullet_name: String = ""

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func configure(sprite_frames: SpriteFrames, bullet_name: String, facing: int, damage: int = 20, knockback: Vector2 = Vector2(100, -80), max_hits: int = 40, collision_size: Vector2 = Vector2(80, 80)) -> void:
	_bullet_name = bullet_name
	_damage = damage
	_knockback_x = abs(knockback.x) * facing
	_knockback_y = knockback.y
	_max_hits = max_hits
	anim.sprite_frames = sprite_frames
	anim.play(bullet_name)
	# Flip bullet based on enemy facing (-1 = left, 1 = right)
	anim.flip_h = facing < 0
	# Set collision shape to match bullet frame dimensions.
	var rect := RectangleShape2D.new()
	rect.size = collision_size
	collision_shape.shape = rect
	anim.animation_finished.connect(_on_anim_finished)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("players"):
		return
	if body in _hit_targets:
		return
	_hit_targets.append(body)
	if body.has_method("take_hit"):
		body.take_hit(_damage, Vector2(_knockback_x, _knockback_y))
	_hits += 1
	if _hits >= _max_hits:
		queue_free()


func _on_anim_finished() -> void:
	queue_free()


func _exit_tree() -> void:
	bullet_destroyed.emit()
