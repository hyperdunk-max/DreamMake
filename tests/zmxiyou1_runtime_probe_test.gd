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
	_assert(body.texture.get_size() == Vector2(200, 1600), "Body atlas should use eight 200px action rows.")
	_assert(weapon.texture.get_size() == Vector2(200, 1600), "Weapon atlas should match body layout.")

	var body_texture := body.texture
	_assert(animator.set_body(2), "Second ZMX1 outfit should be selectable.")
	_assert(body.texture != body_texture, "Outfit switching should replace only the body atlas.")
	_assert(animator.get_body_showid() == 2, "Body showid should update.")
	_assert(animator.get_weapon_showid() == 1, "Outfit switching must preserve the weapon showid.")
	_assert(animator.set_body(1), "First ZMX1 outfit should remain selectable.")
	_assert(body.texture == body_texture, "Switching back should restore the first body atlas.")
	var expected_rows := {
		&"idle": 0, &"walk": 1, &"run": 2, &"hit1": 3,
		&"jump_up": 4, &"jump_double": 5, &"jump_fall": 6, &"hurt": 7,
	}
	for action: StringName in expected_rows:
		_assert(animator.play_action(action, true), "Action %s should play." % action)
		_assert(int(body.region_rect.position.y) == int(expected_rows[action]) * 200, "Action %s should select its source row." % action)
		_assert(body.region_rect == weapon.region_rect, "Body and weapon must share the exact action frame.")

	animator.play_action(&"idle", true)
	var first_weapon := weapon.texture
	_assert(animator.set_weapon(2), "Second ZMX1 weapon should be selectable.")
	_assert(weapon.texture != first_weapon, "Weapon switching should replace only the weapon atlas.")
	_assert(body.texture == body_texture, "Weapon switching must preserve the body atlas.")
	_assert(animator.get_body_showid() == 1, "Body showid should remain unchanged.")
	_assert(animator.get_weapon_showid() == 2, "Weapon showid should update.")
	_assert(body.region_rect == weapon.region_rect, "Layers should remain synchronized after switching.")

	animator.queue_free()
	if _failed:
		quit(1)
	else:
		print("PASS: ZMX1 Wukong body and two weapons use the shared layered animator.")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
