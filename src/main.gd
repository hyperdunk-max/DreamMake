extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $TrainingEnemy
@onready var hud: CanvasLayer = $HUD

@export var playable_roles: Array[Resource] = []

var _roles_by_id: Dictionary = {}


func _ready() -> void:
	for role_resource in playable_roles:
		var definition := role_resource as RoleDefinition
		if definition != null:
			_roles_by_id[definition.role_id] = definition
	player.health_changed.connect(hud.set_player_health)
	player.mana_changed.connect(hud.set_player_mana)
	player.weapon_changed.connect(hud.set_weapon)
	player.body_changed.connect(hud.set_body)
	player.role_changed.connect(hud.set_role)
	enemy.health_changed.connect(hud.set_enemy_health)
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.set_attack_target(player)
	player.health_changed.emit(player.health, player.max_health)
	player.mana_changed.emit(player.mana, player.max_mana)
	hud.set_weapon(player.weapon_showid, player.get_weapon_name())
	hud.set_body(player.body_showid, player.get_body_name())
	hud.set_role(player.role_id, player.role_definition.display_name)
	enemy.health_changed.emit(enemy.health, enemy.max_health)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("test_enemy_attack"):
		if not enemy.request_test_attack():
			hud.show_message("请等待训练木妖完成当前攻击")
	else:
		for role_number in range(1, 5):
			if event.is_action_pressed("role_%d" % role_number):
				_switch_role(role_number)
				break


func _switch_role(role_id: int) -> void:
	var definition: RoleDefinition = _roles_by_id.get(role_id)
	if definition == null:
		return
	if player.configure_role(definition):
		hud.show_message("已切换：%s" % definition.display_name)


func _on_enemy_defeated() -> void:
	hud.show_message("训练完成！按 R 重新挑战")


func _draw() -> void:
	# Placeholder art is intentionally procedural. Extracted art will replace this
	# layer without coupling game logic to individual source images.
	draw_rect(Rect2(0, 0, 940, 590), Color("101b31"))
	draw_circle(Vector2(790, 105), 58, Color("f1cf79"))
	draw_circle(Vector2(772, 90), 58, Color("101b31"))

	var far_mountains := PackedVector2Array([
		Vector2(0, 380), Vector2(100, 270), Vector2(190, 360),
		Vector2(310, 235), Vector2(450, 370), Vector2(580, 260),
		Vector2(710, 355), Vector2(840, 245), Vector2(940, 340), Vector2(940, 520), Vector2(0, 520)
	])
	draw_colored_polygon(far_mountains, Color("223858"))

	var near_mountains := PackedVector2Array([
		Vector2(0, 465), Vector2(145, 330), Vector2(260, 450),
		Vector2(410, 315), Vector2(565, 458), Vector2(725, 325),
		Vector2(940, 445), Vector2(940, 540), Vector2(0, 540)
	])
	draw_colored_polygon(near_mountains, Color("172943"))
	draw_rect(Rect2(0, 515, 940, 75), Color("4a3b2c"))
	draw_rect(Rect2(0, 515, 940, 8), Color("95734b"))
	for x in range(0, 940, 55):
		draw_line(Vector2(x, 535), Vector2(x + 25, 585), Color("33291f"), 3)
