extends Node2D

@onready var stage_controller: StageController = $StageController
@onready var player: PropertyActor2D = $Player
@onready var hud: CanvasLayer = $HUD

var boss: SandbagEnemy


func _ready() -> void:
	stage_controller.stage_started.connect(_on_stage_started)
	stage_controller.boss_spawned.connect(_on_boss_spawned)
	stage_controller.stage_completed.connect(_on_stage_completed)
	player.health_changed.connect(hud.set_player_health)
	player.mana_changed.connect(hud.set_player_mana)
	player.weapon_changed.connect(hud.set_weapon)
	player.body_changed.connect(hud.set_body)
	player.role_changed.connect(hud.set_role)
	var player_stats: ActorProperty = player.get_actor_property()
	player.health_changed.emit(player.health, player_stats.get_effective_max_health())
	player.mana_changed.emit(player.mana, player_stats.get_effective_max_mana())
	hud.set_weapon(player.weapon_showid, player.get_weapon_name())
	hud.set_body(player.body_showid, player.get_body_name())
	hud.set_role(player.role_id, player.role_definition.display_name)
	hud.set_stats(
		player_stats.get_effective_attack(),
		player_stats.get_effective_defense(),
		player_stats.get_effective_crit_rate(),
		player_stats.get_effective_dodge_rate()
	)
	stage_controller.start_stage()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()


func _on_stage_started(stage: StageDefinition) -> void:
	player.global_position = stage.player_spawn_position
	hud.set_title(stage.display_name)
	hud.show_message("%s · %s" % [stage.display_name, stage.end_condition.get_description()])


func _on_boss_spawned(enemy: SandbagEnemy) -> void:
	boss = enemy
	hud.set_enemy_name(enemy.get_display_name())
	if not boss.health_changed.is_connected(hud.set_enemy_health):
		boss.health_changed.connect(hud.set_enemy_health)
	boss.health_changed.emit(boss.health, boss.get_actor_property().get_effective_max_health())


func _on_stage_completed(stage: StageDefinition) -> void:
	hud.show_message("%s 完成！按 R 重新挑战" % stage.display_name)
