extends SceneTree

const PROFILE_PATH := "res://resources/roles/zmxiyou1/role_1_wukong_runtime_probe.tres"

var _failed := false


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var profile := load(PROFILE_PATH) as RoleAnimationProfile
	_assert(profile != null, "ZMX1 Wukong probe profile should load.")
	if profile == null:
		quit(1)
		return

	var animator := LayeredSpriteAnimator.new()
	var body := Sprite2D.new()
	body.name = "Body"
	animator.add_child(body)
	var weapon := Sprite2D.new()
	weapon.name = "Weapon"
	animator.add_child(weapon)
	root.add_child(animator)
	await process_frame

	_assert(animator.register_role(1, profile, 1, 1), "Probe should register through the shared animator.")
	_assert(weapon.z_index < body.z_index, "ZMX1 Wukong weapon should render behind the body.")
	_assert(body.texture != null, "Probe body atlas should load.")
	_assert(weapon.texture != null, "Probe weapon atlas should load.")
	_assert(body.texture.get_size() == Vector2(1200, 6200), "Body atlas should use the six-column 159-frame layout.")
	_assert(weapon.texture.get_size() == Vector2(1200, 6200), "Weapon atlas should match the body layout.")
	var expected_frame_counts := {
		&"idle": 100, &"walk": 16, &"run": 8, &"hit1": 8,
		&"jump_up": 1, &"jump_double": 10, &"jump_fall": 1, &"hurt": 15,
	}
	var compiled := profile.compile_animations(1)
	for action: StringName in expected_frame_counts:
		_assert(compiled.has(action), "Full action %s should compile." % action)
		_assert(compiled[action]["frames"].size() == expected_frame_counts[action], "Action %s should contain every Flash frame." % action)

	var body_texture := body.texture
	for showid in range(1, 7):
		_assert(animator.set_body(showid), "Body showid %d should be selectable." % showid)
		_assert(body.texture != null and body.texture.get_size() == Vector2(1200, 6200), "Body showid %d should load its complete atlas." % showid)
		_assert(animator.get_body_showid() == showid, "Body showid %d should update." % showid)
		_assert(animator.get_weapon_showid() == 1, "Body switching must preserve the weapon showid.")
	_assert(animator.set_body(1), "First ZMX1 outfit should remain selectable.")
	_assert(body.texture == body_texture, "Switching back should restore the first body atlas.")
	var expected_cells := {
		&"idle": Vector2i(0, 0), &"walk": Vector2i(0, 17), &"run": Vector2i(0, 20), &"hit1": Vector2i(0, 22),
		&"jump_up": Vector2i(0, 24), &"jump_double": Vector2i(0, 25), &"jump_fall": Vector2i(0, 27), &"hurt": Vector2i(0, 28),
	}
	for action: StringName in expected_cells:
		_assert(animator.play_action(action, true), "Action %s should play." % action)
		var cell: Vector2i = expected_cells[action]
		_assert(body.region_rect.position == Vector2(cell) * 200, "Action %s should select its source cell." % action)
		_assert(body.region_rect == weapon.region_rect, "Body and weapon must share the exact action frame.")

	animator.play_action(&"idle", true)
	for showid in range(1, 9):
		_assert(animator.set_weapon(showid), "Weapon showid %d should be selectable." % showid)
		_assert(weapon.texture != null and weapon.texture.get_size() == Vector2(1200, 6200), "Weapon showid %d should load its complete atlas." % showid)
		_assert(animator.get_body_showid() == 1, "Weapon switching must preserve the body showid.")
		_assert(animator.get_weapon_showid() == showid, "Weapon showid %d should update." % showid)
		_assert(body.region_rect == weapon.region_rect, "Layers should remain synchronized after switching.")

	animator.queue_free()
	if _failed:
		quit(1)
	else:
		print("PASS: ZMX1 Wukong all six bodies and eight weapons use the shared layered animator.")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
