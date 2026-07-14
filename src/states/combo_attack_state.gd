class_name ComboAttackState
extends CharacterActionState

const ID := &"combo_attack"

var profile: ComboAttackProfile
var _current_step_index := -1
var _elapsed_ticks := 0
var _tick_accumulator := 0.0
var _last_attack_press_time := -1.0
var _queued_next_attack := false
var _hit_fired := false
var _hit_targets: Dictionary = {}


func configure(combo_profile: ComboAttackProfile) -> void:
	profile = combo_profile
	_current_step_index = -1
	_elapsed_ticks = 0
	_tick_accumulator = 0.0
	_last_attack_press_time = -1.0
	_queued_next_attack = false
	_hit_fired = false
	_hit_targets.clear()


func request_attack() -> bool:
	if profile == null:
		return false
	var now := state_machine.get_elapsed_time_seconds()
	if state_machine.is_in_state(ID):
		_queued_next_attack = true
		_last_attack_press_time = now
		return true
	return state_machine.transition_to(ID, {"pressed_at": now})


func enter(payload: Dictionary = {}) -> void:
	var pressed_at := float(payload.get("pressed_at", state_machine.get_elapsed_time_seconds()))
	if _last_attack_press_time < 0.0 or pressed_at - _last_attack_press_time > profile.combo_window_seconds:
		_current_step_index = 0
	else:
		_current_step_index = (_current_step_index + 1) % profile.get_step_count()
	_last_attack_press_time = pressed_at
	_queued_next_attack = false
	_start_current_step()


func exit() -> void:
	_tick_accumulator = 0.0


func physics_process(delta: float) -> void:
	_tick_accumulator += delta * profile.logical_fps
	var pending_ticks := mini(int(_tick_accumulator), 8)
	_tick_accumulator -= pending_ticks
	for _tick in range(pending_ticks):
		_step_tick()
		if not state_machine.is_in_state(ID):
			break


func blocks_horizontal_movement() -> bool:
	return true


func get_current_step_number() -> int:
	return _current_step_index + 1


func _start_current_step() -> void:
	var step := profile.get_step(_current_step_index)
	_elapsed_ticks = 0
	_hit_fired = false
	_hit_targets.clear()
	animator.play_action(StringName(step["action"]), true)


func _step_tick() -> void:
	var step := profile.get_step(_current_step_index)
	_elapsed_ticks += 1
	var hit_tick := int(step.get("hit_tick", -1))
	if not _hit_fired and hit_tick >= 0 and _elapsed_ticks >= hit_tick:
		_hit_fired = true
		if actor.has_method("perform_combo_hit"):
			actor.perform_combo_hit(step, _hit_targets)
	if _elapsed_ticks < int(step["duration_ticks"]):
		return
	if _queued_next_attack:
		_queued_next_attack = false
		_current_step_index = (_current_step_index + 1) % profile.get_step_count()
		_start_current_step()
	else:
		state_machine.clear_state(self)
