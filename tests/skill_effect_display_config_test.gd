extends SceneTree

const CONFIG := preload("res://src/skills/skill_effect_display_config.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_text := FileAccess.get_file_as_string(CONFIG.CONFIG_PATH)
	var test_key := "999/calibrator_test/effect"
	var fallback := Vector2(12, -34)
	_assert(CONFIG.get_offset_by_key(test_key, fallback) == fallback, "Missing override should use fallback.")
	_assert(CONFIG.save_offset_by_key(test_key, Vector2(56, -78)) == OK, "Override should save.")
	CONFIG.reload()
	_assert(
		CONFIG.get_offset_by_key(test_key, Vector2.ZERO) == Vector2(56, -78),
		"Saved override should survive a reload."
	)
	var restore_file := FileAccess.open(CONFIG.CONFIG_PATH, FileAccess.WRITE)
	_assert(restore_file != null, "Original override file should be restorable.")
	if restore_file != null:
		restore_file.store_string(original_text)
		restore_file.close()
	CONFIG.reload()
	if _failed:
		quit(1)
	else:
		print("PASS: skill effect display overrides save, reload, and preserve the project file.")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
