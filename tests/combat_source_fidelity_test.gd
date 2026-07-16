extends SceneTree

var _failed := false

const WUKONG: ComboAttackProfile = preload("res://resources/roles/role_1_wukong_combo.tres")
const TANGSENG: ComboAttackProfile = preload("res://resources/roles/role_2_tangseng_combo.tres")
const BAJIE: ComboAttackProfile = preload("res://resources/roles/role_3_bajie_combo.tres")
const SHASENG: ComboAttackProfile = preload("res://resources/roles/role_4_shaseng_combo.tres")
const SHASENG_ARROW: ComboAttackProfile = preload("res://resources/roles/role_4_shaseng_arrow_combo.tres")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_profile(
		WUKONG,
		[9, 9, 9, 15, 15],
		[5, 5, 1, 1, 5],
		[Vector2(120, -45), Vector2(120, -45), Vector2(30, -160), Vector2(160, -60), Vector2(165, -70)]
	)
	_verify_profile(TANGSENG, [18], [7], [Vector2(50, -40)])
	_verify_profile(
		BAJIE,
		[13, 13, 13],
		[4, 4, 6],
		[Vector2(140, -80), Vector2(130, -122), Vector2(180, -190)]
	)
	_verify_profile(
		SHASENG,
		[13, 13, 15],
		[4, 4, 1],
		[Vector2(20, -20), Vector2(15, -50), Vector2(0, -50)]
	)
	_verify_profile(
		SHASENG_ARROW,
		[18, 18, 20],
		[5, 5, 3],
		[Vector2(90, -50), Vector2(90, -50), Vector2(115, -70)]
	)
	_assert(StringName(TANGSENG.steps[0]["delivery"]) == &"projectile", "Tangseng hit1 should use its source projectile delivery.")
	_assert(TANGSENG.steps[0]["projectile_frame_hitboxes"].size() == 24, "Tangseng projectile should track all 24 source frames.")
	_assert(StringName(SHASENG_ARROW.steps[2]["delivery"]) == &"projectile", "Shaseng bow finisher should use Role4BulletArrow2 delivery.")
	_assert(SHASENG_ARROW.steps[2]["projectile_frame_hitboxes"][4].size() == 3, "Shaseng bow finisher should expose three separate arrow hitboxes.")
	_assert(int(SHASENG_ARROW.steps[2]["projectile_rehit_interval_frames"]) == 5, "Shaseng Role4BulletArrow2 should preserve its 5-frame attack interval.")
	_assert(float(SHASENG.steps[2]["move_speed"]) == 192.0, "Shaseng shovel finisher should preserve source 8px/tick lunge.")
	_assert(int(SHASENG.steps[2]["duration_ticks"]) == 15, "Shaseng shovel finisher should move until its source animation clears velocity on tick 15.")
	_assert(Vector2(WUKONG.steps[0]["knockback"]) == Vector2(48, -72), "Wukong hit1 knockback should map source 2,-3 px/tick to 24Hz velocity.")
	_assert(Vector2(WUKONG.steps[4]["knockback"]) == Vector2(360, -48), "Wukong hit5 knockback should map source 15,-2 px/tick to 24Hz velocity.")
	if _failed:
		quit(1)
	else:
		print("PASS: source attack timers, hit callbacks, registration points, and knockback mapping.")
		quit(0)


func _verify_profile(
	profile: ComboAttackProfile,
	durations: Array,
	hit_ticks: Array,
	effect_offsets: Array
) -> void:
	_assert(profile.steps.size() == durations.size(), "Role %d source step count mismatch." % profile.role_id)
	for index in range(profile.steps.size()):
		var step: Dictionary = profile.steps[index]
		_assert(int(step["duration_ticks"]) == durations[index], "Role %d step %d duration mismatch." % [profile.role_id, index + 1])
		_assert(int(step["hit_tick"]) == hit_ticks[index], "Role %d step %d hit callback mismatch." % [profile.role_id, index + 1])
		_assert(Vector2(step["effect_offset"]) == effect_offsets[index], "Role %d step %d Flash registration point mismatch." % [profile.role_id, index + 1])
		_assert(step.has("effect_sprite_offset"), "Role %d step %d should preserve PNG registration anchor." % [profile.role_id, index + 1])


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
