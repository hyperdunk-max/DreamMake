extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal defeated
signal attack_started

const GRAVITY := 1450.0
const ATTACK_WINDUP := 0.32
const ATTACK_RECOVERY := 0.28
const ATTACK_RANGE := 145.0

@export var max_health := 600
var health := max_health
var hit_flash := 0.0
var defeated_once := false
var attack_target: CharacterBody2D
var attack_time := 0.0
var attack_has_fired := false
var stun_time := 0.0


func _physics_process(delta: float) -> void:
	stun_time = maxf(0.0, stun_time - delta)
	if stun_time > 0.0:
		attack_time = 0.0
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return
	if attack_time > 0.0:
		attack_time = maxf(0.0, attack_time - delta)
		if not attack_has_fired and attack_time <= ATTACK_RECOVERY:
			attack_has_fired = true
			_fire_test_attack()
		queue_redraw()
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 560.0 * delta)
	move_and_slide()
	global_position.x = clampf(global_position.x, 28.0, 912.0)
	if hit_flash > 0.0:
		hit_flash -= delta
		queue_redraw()


func set_attack_target(target: CharacterBody2D) -> void:
	attack_target = target


func request_test_attack() -> bool:
	if health <= 0 or attack_time > 0.0 or attack_target == null:
		return false
	attack_time = ATTACK_WINDUP + ATTACK_RECOVERY
	attack_has_fired = false
	attack_started.emit()
	queue_redraw()
	return true


func _fire_test_attack() -> void:
	if attack_target == null or not is_instance_valid(attack_target):
		return
	var delta_to_player := attack_target.global_position - global_position
	if absf(delta_to_player.x) > ATTACK_RANGE or absf(delta_to_player.y) > 85.0:
		return
	var attack_direction := 1.0 if delta_to_player.x >= 0.0 else -1.0
	attack_target.take_hit(12, Vector2(260.0 * attack_direction, -180.0), &"physical", self)


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


func apply_stun(seconds: float) -> void:
	stun_time = maxf(stun_time, seconds)
	velocity = Vector2.ZERO


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
	if attack_time > 0.0 and not attack_has_fired:
		var direction := 1.0
		if attack_target != null and attack_target.global_position.x < global_position.x:
			direction = -1.0
		var warning_rect := Rect2(
			Vector2(0.0 if direction > 0.0 else -ATTACK_RANGE, -58.0),
			Vector2(ATTACK_RANGE, 58.0)
		)
		draw_rect(warning_rect, Color(1.0, 0.18, 0.08, 0.24), true)
		draw_rect(warning_rect, Color(1.0, 0.45, 0.18, 0.9), false, 2.0)
