extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal defeated

const GRAVITY := 1450.0

@export var max_health := 120
var health := max_health
var hit_flash := 0.0
var defeated_once := false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 560.0 * delta)
	move_and_slide()
	global_position.x = clampf(global_position.x, 28.0, 912.0)
	if hit_flash > 0.0:
		hit_flash -= delta
		queue_redraw()


func take_hit(damage: int, impulse: Vector2) -> void:
	if health <= 0:
		return
	health = maxi(0, health - damage)
	velocity = impulse
	hit_flash = 0.09
	health_changed.emit(health, max_health)
	queue_redraw()
	if health == 0 and not defeated_once:
		defeated_once = true
		defeated.emit()


func _draw() -> void:
	var body_color := Color.WHITE if hit_flash > 0.0 else Color("6e8b3d")
	draw_ellipse(Vector2(0, 1), 31.0, 7.0, Color(0.0, 0.0, 0.0, 0.35))
	if health <= 0:
		draw_rect(Rect2(-31, -15, 62, 16), Color("4c382b"), true)
		return
	draw_rect(Rect2(-20, -55, 40, 48), body_color, true)
	draw_circle(Vector2(0, -70), 16, Color("af704b"))
	draw_colored_polygon(
		PackedVector2Array([Vector2(-18, -84), Vector2(-7, -96), Vector2(0, -84), Vector2(10, -98), Vector2(18, -83)]),
		Color("513a26")
	)
	draw_circle(Vector2(-6, -72), 2.5, Color("1a1410"))
	draw_circle(Vector2(6, -72), 2.5, Color("1a1410"))
	draw_line(Vector2(-14, -43), Vector2(-30, -20), Color("af704b"), 7)
	draw_line(Vector2(14, -43), Vector2(30, -20), Color("af704b"), 7)
