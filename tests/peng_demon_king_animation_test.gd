extends SceneTree

const DEFINITION_PATH := "res://resources/enemies/zmxiyou1_peng_demon_king.tres"
const PREVIEW_PATH := "res://scenes/debug/enemy_animation_preview.tscn"
const EVENT_DISPATCHER_SCRIPT := preload("res://src/enemies/enemy_animation_event_dispatcher.gd")
const EXPECTED_COUNTS := {
	&"move": 16, &"fly": 9, &"attack1": 24, &"attack2": 41,
	&"attack3": 25, &"attack4": 15, &"egg": 25, &"reburn": 30,
	&"hurt": 6, &"idle": 15, &"death": 25,
}
const EXPECTED_OFFSETS := {
	&"move": Vector2(-13, -60), &"fly": Vector2(0, -57),
	&"attack1": Vector2(0, -93), &"attack2": Vector2(0, -122.5),
	&"attack3": Vector2(0, -102.5), &"attack4": Vector2(-56, -91),
	&"egg": Vector2(1, -55), &"reburn": Vector2(0, -65),
	&"hurt": Vector2(8, -57), &"idle": Vector2(-5, -57),
	&"death": Vector2(0, -59),
}

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := load(DEFINITION_PATH) as EnemyDefinition
	_assert(definition != null, "Peng Demon King definition should load.")
	if definition == null:
		quit(1)
		return
	_assert(definition.validate().is_empty(), "Peng Demon King definition should validate.")
	var profile := definition.animation_profile
	_assert(profile != null, "Peng Demon King should have an animation profile.")
	_assert(profile.actions.size() == EXPECTED_COUNTS.size(), "All reviewed Peng Demon King actions should be configured.")
	var frames := profile.build_sprite_frames()
	for action: StringName in EXPECTED_COUNTS:
		var expected := int(EXPECTED_COUNTS[action])
		_assert(frames.has_animation(action), "Animation '%s' should exist." % action)
		_assert(frames.get_frame_count(action) == expected, "Animation '%s' should contain %d frames." % [action, expected])
		_assert(
			profile.get_offset(action).is_equal_approx(EXPECTED_OFFSETS[action]),
			"Animation '%s' should preserve its manually saved sprite_offset." % action,
		)
	_assert(profile.get_event_frames(&"attack1") == PackedInt32Array([8]), "Attack1 should preserve its source frame-9 fire event.")
	_assert(profile.get_event_frames(&"attack2") == PackedInt32Array([0, 16]), "Attack2 should preserve its source control frames.")
	_assert(profile.get_event_frames(&"attack3") == PackedInt32Array([14]), "Attack3 should preserve its source frame-15 fire event.")
	_assert(profile.source_monster_id == &"M09", "Peng Demon King profile should identify its source monster.")
	_assert(profile.source_package == &"Monster2_v4", "Peng Demon King profile should identify its source package.")
	_assert(profile.get_source_event_frames(&"attack1") == PackedInt32Array([8, 23]), "Attack1 should synchronize fire and completion source events.")
	_assert(_has_source_event(profile, &"attack1", 8, &"fire_hit"), "Attack1 frame 9 should synchronize fire_hit.")
	_assert(_has_source_event(profile, &"attack2", 0, &"set_invulnerable"), "Attack2 frame 1 should synchronize its invulnerability call.")
	_assert(_has_source_event(profile, &"attack2", 16, &"refresh_attack_id"), "Attack2 frame 17 should synchronize its attack-id refresh.")
	_assert(_has_source_event(profile, &"attack3", 14, &"fire_hit"), "Attack3 frame 15 should synchronize fire_hit.")
	_assert(profile.is_source_hitbox_active(&"attack1", 6), "Attack1 stick should activate on source frame 7.")
	_assert(not profile.is_source_hitbox_active(&"attack1", 8), "Attack1 stick should be removed after source frame 8.")
	_assert(profile.is_source_hitbox_active(&"attack2", 40), "Attack2 dynamic stick should remain active through its root timeline.")
	_assert(profile.is_source_hitbox_active(&"attack4", 2), "Attack4 stick should activate on source frame 3.")
	_assert(not profile.is_source_hitbox_active(&"attack4", 14), "Attack4 stick should be removed on source frame 15.")

	var load_error := change_scene_to_file(PREVIEW_PATH)
	_assert(load_error == OK, "Peng Demon King preview scene should load.")
	await process_frame
	await process_frame
	var preview := current_scene as EnemyAnimationPreview
	_assert(preview != null, "Preview scene should instantiate its controller.")
	if preview != null:
		var sprite := preview.get_node("PreviewWorld/AnimatedSprite2D") as AnimatedSprite2D
		_assert(sprite != null and sprite.animation == &"attack1", "Preview should start by playing attack1.")
		_assert(sprite != null and sprite.sprite_frames.get_frame_count(&"attack1") == 24, "Preview should use the complete 24-frame attack1 timeline.")

	var dispatcher_sprite := AnimatedSprite2D.new()
	dispatcher_sprite.sprite_frames = frames
	root.add_child(dispatcher_sprite)
	var dispatcher := EVENT_DISPATCHER_SCRIPT.new()
	root.add_child(dispatcher)
	var dispatched: Array[Dictionary] = []
	dispatcher.source_event.connect(
		func(action: StringName, event: Dictionary) -> void:
			if action == &"attack1":
				dispatched.append(event)
	)
	dispatcher.bind(dispatcher_sprite, profile)
	dispatcher_sprite.animation = &"attack1"
	dispatcher_sprite.frame = 8
	dispatcher.emit_current_frame(true)
	_assert(
		dispatched.any(func(event: Dictionary) -> bool: return StringName(event.get("id", "")) == &"fire_hit"),
		"EnemyAnimationEventDispatcher should emit synchronized fire_hit events.",
	)
	dispatcher.queue_free()
	dispatcher_sprite.queue_free()
	print("Peng Demon King animation test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _has_source_event(profile: EnemyAnimationProfile, action: StringName, frame: int, event_id: StringName) -> bool:
	return profile.get_source_events_at_frame(action, frame).any(
		func(event: Dictionary) -> bool: return StringName(event.get("id", "")) == event_id
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
