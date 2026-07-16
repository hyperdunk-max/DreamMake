extends SceneTree

var _failed := false

const ANIMATION_PROFILE: RoleAnimationProfile = preload("res://resources/roles/role_1_wukong.tres")
const COMBO_PROFILE: ComboAttackProfile = preload("res://resources/roles/role_1_wukong_combo.tres")


class MockComboActor extends CharacterBody2D:
	var hit_count := 0

	func perform_combo_hit(_step: Dictionary, _hit_targets: Dictionary) -> void:
		hit_count += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor := MockComboActor.new()
	var animator := _make_animator()
	var machine := CharacterStateMachine.new()
	actor.add_child(animator)
	actor.add_child(machine)
	root.add_child(actor)
	await process_frame

	_assert(animator.register_role(1, ANIMATION_PROFILE, 1, 0), "Animator registration failed.")
	var combo := ComboAttackState.new()
	combo.configure(COMBO_PROFILE)
	combo.setup(ComboAttackState.ID, actor, animator, machine)
	_assert(machine.register_state(combo), "Combo state registration failed.")

	_assert(combo.request_attack(), "First combo request failed.")
	_assert(animator.get_current_action() == &"hit1", "Combo did not start at hit1.")
	_assert(combo.request_attack(), "An attack press during hit1 should be observed.")
	combo.release_attack()
	_advance(machine, 9)
	_assert(not machine.has_active_state(), "A released early tap must not queue the next combo step.")
	_assert(actor.hit_count == 1, "An ignored early tap must not create another hit.")

	_assert(combo.request_attack(), "A press after hit1 should continue within the combo window.")
	_assert(animator.get_current_action() == &"hit2", "A valid follow-up press did not advance to hit2.")
	_assert(combo.request_attack(), "A new press held during hit2 should be observed.")
	_advance(machine, 9)
	_assert(machine.is_in_state(ComboAttackState.ID), "A press held through the action end should continue the combo.")
	_assert(animator.get_current_action() == &"hit3", "A held retry did not advance to hit3.")
	_advance(machine, 15)
	_assert(not machine.has_active_state(), "Combo did not finish after hit3.")
	_assert(actor.hit_count == 3, "Expected one hit event for each accepted combo step.")

	_advance(machine, ceili((COMBO_PROFILE.combo_window_seconds + 0.05) * COMBO_PROFILE.logical_fps))
	combo.request_attack()
	_assert(animator.get_current_action() == &"hit1", "Expired combo window did not reset to hit1.")
	machine.clear_state()
	combo.reset_progress()
	_assert(combo.get_current_step_number() == 0, "Explicit combo reset should clear the stored step.")
	combo.request_attack()
	_assert(animator.get_current_action() == &"hit1", "An air-style combo reset should restart at hit1.")
	if _failed:
		quit(1)
	else:
		print("PASS: combo input ignores released early taps, accepts held retries, and resets after its time window.")
		quit(0)


func _advance(machine: CharacterStateMachine, ticks: int) -> void:
	for _tick in range(ticks):
		machine.physics_process(1.01 / COMBO_PROFILE.logical_fps)


func _make_animator() -> LayeredSpriteAnimator:
	var animator := LayeredSpriteAnimator.new()
	animator.name = "LayeredSpriteAnimator"
	var body := Sprite2D.new()
	body.name = "Body"
	animator.add_child(body)
	var weapon := Sprite2D.new()
	weapon.name = "Weapon"
	animator.add_child(weapon)
	return animator


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
