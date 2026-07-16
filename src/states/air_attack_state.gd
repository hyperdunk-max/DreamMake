class_name AirAttackState
extends CharacterActionState

const ID := &"air_attack"

var _step: Dictionary = {}
var _logical_fps := 24.0
var _elapsed_ticks := 0
var _tick_accumulator := 0.0
var _hit_fired := false
var _hit_targets: Dictionary = {}


func configure(step: Dictionary, logical_fps: float) -> void:
	_step = step.duplicate(true)
	_logical_fps = logical_fps
	_elapsed_ticks = 0
	_tick_accumulator = 0.0
	_hit_fired = false
	_hit_targets.clear()


func is_configured() -> bool:
	return not _step.is_empty() and _logical_fps > 0.0


func request_attack() -> bool:
	if not is_configured() or state_machine.has_active_state():
		return false
	return state_machine.transition_to(ID)


func enter(_payload: Dictionary = {}) -> void:
	_elapsed_ticks = 0
	_tick_accumulator = 0.0
	_hit_fired = false
	_hit_targets.clear()
	animator.play_action(StringName(_step["action"]), true)


func exit() -> void:
	_tick_accumulator = 0.0


func physics_process(delta: float) -> void:
	_tick_accumulator += delta * _logical_fps
	var pending_ticks := mini(int(_tick_accumulator), 8)
	_tick_accumulator -= pending_ticks
	for _tick in range(pending_ticks):
		_step_tick()
		if not state_machine.is_in_state(ID):
			break


func get_elapsed_ticks() -> int:
	return _elapsed_ticks


func _step_tick() -> void:
	_elapsed_ticks += 1
	var hit_tick := int(_step.get("hit_tick", -1))
	if not _hit_fired and hit_tick >= 0 and _elapsed_ticks >= hit_tick:
		_hit_fired = true
		if actor.has_method("perform_combo_hit"):
			actor.perform_combo_hit(_step, _hit_targets)
	if _elapsed_ticks >= int(_step["duration_ticks"]):
		state_machine.clear_state(self)
