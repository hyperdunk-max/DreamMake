extends SceneTree

const PROFILE: RoleAnimationProfile = preload("res://resources/roles/role_1_wukong.tres")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := _make_animator("FirstRole")
	var second := _make_animator("SecondRole")
	root.add_child(first)
	root.add_child(second)
	await process_frame

	_assert(first.register_role(1, PROFILE, 1, 0), "First role registration failed.")
	_assert(second.register_role(1, PROFILE, 1, 1), "Second role registration failed.")
	first.play_action(&"run", true)
	second.play_action(&"jump_double", true)

	_assert(first.get_weapon_showid() == 0, "First role weapon state leaked.")
	_assert(second.get_weapon_showid() == 1, "Second role weapon state leaked.")
	_assert(first.get_current_action() == &"run", "First role action state leaked.")
	_assert(second.get_current_action() == &"jump_double", "Second role action state leaked.")

	first.unregister_role()
	_assert(not first.is_role_registered(), "First role failed to unregister.")
	_assert(second.is_role_registered(), "Unregistering first role affected second role.")
	print("PASS: role animator instances keep independent registration and playback state.")
	quit(0)


func _make_animator(node_name: String) -> LayeredSpriteAnimator:
	var animator := LayeredSpriteAnimator.new()
	animator.name = node_name
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
