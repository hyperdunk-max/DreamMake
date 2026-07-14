class_name CharacterStateMachine
extends Node

signal state_changed(previous: StringName, current: StringName)

var _states: Dictionary = {}
var _current_state: CharacterActionState
var _elapsed_time_seconds := 0.0


func register_state(state: CharacterActionState) -> bool:
	if state == null or state.state_id.is_empty():
		return false
	if _states.has(state.state_id):
		push_error("State '%s' is already registered on this character." % state.state_id)
		return false
	_states[state.state_id] = state
	return true


func transition_to(state_id: StringName, payload: Dictionary = {}) -> bool:
	var next_state: CharacterActionState = _states.get(state_id)
	if next_state == null:
		push_error("State '%s' is not registered on this character." % state_id)
		return false
	var previous_id := get_current_state_id()
	if _current_state != null and _current_state != next_state:
		_current_state.exit()
	_current_state = next_state
	_current_state.enter(payload)
	state_changed.emit(previous_id, state_id)
	return true


func clear_state(expected_state: CharacterActionState = null) -> void:
	if _current_state == null:
		return
	if expected_state != null and _current_state != expected_state:
		return
	var previous_id := _current_state.state_id
	_current_state.exit()
	_current_state = null
	state_changed.emit(previous_id, &"")


func physics_process(delta: float) -> void:
	_elapsed_time_seconds += delta
	if _current_state != null:
		_current_state.physics_process(delta)


func has_active_state() -> bool:
	return _current_state != null


func is_in_state(state_id: StringName) -> bool:
	return _current_state != null and _current_state.state_id == state_id


func get_current_state_id() -> StringName:
	return _current_state.state_id if _current_state != null else &""


func get_elapsed_time_seconds() -> float:
	return _elapsed_time_seconds


func blocks_horizontal_movement() -> bool:
	return _current_state != null and _current_state.blocks_horizontal_movement()
