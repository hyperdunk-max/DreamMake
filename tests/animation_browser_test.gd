extends SceneTree

const BROWSER_PATH := "res://scenes/debug/animation_browser.tscn"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var load_error := change_scene_to_file(BROWSER_PATH)
	_assert(load_error == OK, "Unified animation browser scene should load.")
	await process_frame
	await process_frame
	var browser := current_scene as AnimationBrowser
	_assert(browser != null, "Animation browser should instantiate its controller.")
	if browser == null:
		quit(1)
		return
	_assert(browser.get_active_mode_id() == "roles", "Browser should open the role animation module by default.")
	_assert(browser.get_active_module() is RoleAnimationPreview, "Role mode should use the normalized role preview module.")
	var role_preview := browser.get_active_module() as RoleAnimationPreview
	if role_preview != null:
		var role_offset := role_preview.get_preview_offset()
		role_preview.set_preview_offset(role_offset + Vector2(3, -2))
		_assert(
			role_preview.get_preview_offset() == role_offset + Vector2(3, -2),
			"Role preview should support coordinate calibration without saving during the test."
		)
		role_preview.call("_reset_offset")
		_assert(role_preview.get_preview_offset() == role_offset, "Role preview should restore its saved coordinate.")

	browser.show_mode_by_id("enemies")
	await process_frame
	_assert(browser.get_active_mode_id() == "enemies", "Browser should switch to the enemy animation module.")
	_assert(browser.get_active_module() is EnemyAnimationPreview, "Enemy mode should reuse the reviewed enemy timeline preview.")
	var enemy_preview := browser.get_active_module() as EnemyAnimationPreview
	if enemy_preview != null:
		var enemy_offset := enemy_preview.get_preview_offset()
		enemy_preview.set_preview_offset(enemy_offset + Vector2(-4, 5))
		_assert(
			enemy_preview.get_preview_offset() == enemy_offset + Vector2(-4, 5),
			"Enemy preview should support per-action coordinate calibration without saving during the test."
		)
		enemy_preview.call("_reset_offset")
		_assert(enemy_preview.get_preview_offset() == enemy_offset, "Enemy preview should restore its saved action coordinate.")

	browser.show_mode_by_id("skills")
	await process_frame
	_assert(browser.get_active_mode_id() == "skills", "Browser should switch to the skill effect module.")
	_assert(browser.get_active_module() is SkillEffectCalibrator, "Skill mode should reuse the effect calibrator.")

	print("Animation browser test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
