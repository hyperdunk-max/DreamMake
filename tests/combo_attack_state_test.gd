extends SceneTree

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
	combo.request_attack()
	_advance(machine, 9)
	_assert(machine.is_in_state(ComboAttackState.ID), "Buffered attack did not continue the combo.")
	_assert(animator.get_current_action() == &"hit2", "Buffered attack did not advance to hit2.")
	_advance(machine, 9)
	_assert(not machine.has_active_state(), "Combo did not finish after hit2.")
	_assert(actor.hit_count == 2, "Expected one hit event for each combo step.")

	_advance(machine, ceili((COMBO_PROFILE.combo_window_seconds + 0.05) * COMBO_PROFILE.logical_fps))
	combo.request_attack()
	_assert(animator.get_current_action() == &"hit1", "Expired combo window did not reset to hit1.")
	print("PASS: five-step combo state buffers input and resets after its time window.")
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
	push_error(message)
	quit(1)
