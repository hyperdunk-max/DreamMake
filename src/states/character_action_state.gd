class_name CharacterActionState
extends RefCounted

var state_id: StringName
var actor: CharacterBody2D
var animator: LayeredSpriteAnimator
var state_machine: CharacterStateMachine


func setup(
	id: StringName,
	owner_actor: CharacterBody2D,
	owner_animator: LayeredSpriteAnimator,
	owner_state_machine: CharacterStateMachine
) -> void:
	state_id = id
	actor = owner_actor
	animator = owner_animator
	state_machine = owner_state_machine


func enter(_payload: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func physics_process(_delta: float) -> void:
	pass


func blocks_horizontal_movement() -> bool:
	return false
