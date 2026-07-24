class_name Zmxiyou1M22Controller
extends Node

## Source controller for Monster22, the invulnerable running first bull phase.
##
## Flash keeps the bull invulnerable while it crosses the viewport and uses
## the `walk` attack profile for contact damage. At either source boundary it
## stops, becomes vulnerable, waits 24 ticks on the first turn and 72 ticks on
## later turns, then reverses. Its death creates Monster23 before the old body
## completes the one-second BaseMonster fade. StageController owns creation of
## the next phase through EnemyDefinition.source_despawn_effects.

const FIRST_WAIT_TICKS := 25
const LATER_WAIT_TICKS := 73
const LEFT_SCREEN_BOUND := -360.0
const RIGHT_SCREEN_BOUND := 400.0
var _host: AnimatedEnemy
var _direction := -1
var _last_direction := -1
var _running := true
var _wait_elapsed := 0
var _wait_target := FIRST_WAIT_TICKS


# AnimatedEnemy source-controller contract

func setup(host: AnimatedEnemy) -> void:
	_host = host
	_host.source_refresh_attack_id()
	_host.source_set_move_direction(_direction)


func source_tick(_source_tick: int) -> void:
	if _host == null or not is_instance_valid(_host) or _host.get_state_name() == &"death":
		return
	if _running:
		_host.source_set_move_direction(_direction)
		var screen_x := _host.global_position.x - _viewport_center_x()
		if _has_crossed_screen_boundary(screen_x):
			_last_direction = _direction
			_running = false
			_wait_elapsed = 0
			_host.source_set_idle()
		return
	_host.source_set_idle()
	_wait_elapsed += 1
	if _wait_elapsed < _wait_target:
		return
	_direction = -_last_direction
	_running = true
	_wait_elapsed = 0
	_wait_target = LATER_WAIT_TICKS
	_host.source_refresh_attack_id()
	_host.source_set_move_direction(_direction)


func blocks_host_ai() -> bool:
	return true


func can_receive_hit() -> bool:
	return not _running


func keeps_idle_on_hit() -> bool:
	return true


func before_despawn() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	var fade := _host.create_tween()
	if fade != null:
		fade.tween_property(_host, ^"modulate:a", 0.0, 1.0)


# Test/debug inspection API

func is_running() -> bool:
	return _running


func get_direction() -> int:
	return _direction


func get_wait_elapsed() -> int:
	return _wait_elapsed


func _has_crossed_screen_boundary(screen_x: float) -> bool:
	return (
		(_direction < 0 and screen_x < LEFT_SCREEN_BOUND)
		or (_direction > 0 and screen_x > RIGHT_SCREEN_BOUND)
	)


func _viewport_center_x() -> float:
	# Flash boundaries are screen-relative, so a scrolling Godot camera must be
	# removed from the world-space host position before applying them.
	if _host == null or not is_instance_valid(_host):
		return 0.0
	var camera := _host.get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position().x
	return _host.get_viewport_rect().get_center().x
