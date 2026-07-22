extends SceneTree

## Synchronize exact addFrameScript events into runtime EnemyAnimationProfile
## resources. Existing action fields are treated as manual configuration and
## must remain byte-for-byte equivalent as Godot Variants after saving.

const EVENT_AUDIT_PATH := "res://sources/manifests/zmxiyou1_monster_events.json"
const PROFILE_DIRECTORY := "res://resources/enemies/animations"
const SYNC_AUDIT_PATH := "res://sources/manifests/zmxiyou1_monster_event_sync.json"
const GENERATED_KEYS := [&"source_events", &"source_event_sync"]

var _failed := false
var _failure_messages: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest := _read_json(EVENT_AUDIT_PATH)
	if manifest.is_empty():
		_fail("Monster event audit is missing or invalid: %s" % EVENT_AUDIT_PATH)
		_finish([])
		return
	var monsters: Dictionary = manifest.get("monsters", {})
	var sync_rows: Array[Dictionary] = []
	var files := DirAccess.get_files_at(PROFILE_DIRECTORY)
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var profile_path := "%s/%s" % [PROFILE_DIRECTORY, file_name]
		var resource := ResourceLoader.load(profile_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if not resource is EnemyAnimationProfile:
			continue
		var profile := resource as EnemyAnimationProfile
		if profile.source_monster_id == &"":
			continue
		var monster_key := str(profile.source_monster_id)
		if not monsters.has(monster_key):
			_fail("%s refers to unknown source monster %s." % [profile_path, monster_key])
			continue
		var monster: Dictionary = monsters[monster_key]
		if not profile.source_package == StringName(str(monster.get("package", ""))):
			_fail("%s source_package does not match the event audit." % profile_path)
			continue
		var manual_before := _manual_snapshot(profile)
		var synced_actions := 0
		var synced_events := 0
		var skipped_no_op := 0
		for raw_action: Variant in profile.actions:
			var action := StringName(raw_action)
			var spec: Dictionary = profile.actions[raw_action]
			var source_symbol_id := int(spec.get("source_symbol_id", 0))
			var source_action_label := str(spec.get("source_action_label", ""))
			if source_symbol_id <= 0 or source_action_label.is_empty():
				_fail("%s action %s needs source_symbol_id and source_action_label." % [profile_path, action])
				continue
			var provider := _find_provider(monster, source_action_label, source_symbol_id)
			if provider.is_empty():
				_fail(
					"%s action %s cannot find source label %s symbol %d."
					% [profile_path, action, source_action_label, source_symbol_id]
				)
				continue
			var frame_count := int(spec.get("frame_count", 0))
			var compact_events: Array[Dictionary] = []
			for raw_event: Variant in provider.get("frame_events", []):
				if not raw_event is Dictionary:
					continue
				var event := raw_event as Dictionary
				var types := PackedStringArray(event.get("types", []))
				if types == PackedStringArray(["no_op"]):
					skipped_no_op += 1
					continue
				var source_frame := int(event.get("action_frame", event.get("frame", 0)))
				var runtime_frame := source_frame - 1
				if runtime_frame < 0 or runtime_frame >= frame_count:
					_fail(
						"%s action %s event frame %d is outside its %d frames."
						% [profile_path, action, runtime_frame, frame_count]
					)
					continue
				var source_lines: Dictionary = event.get("source_lines", {})
				compact_events.append(
					{
						"frame": runtime_frame,
						"source_frame": source_frame,
						"id": _event_id(event),
						"types": types,
						"method": str(event.get("method", "")),
						"source": str(event.get("source", "")),
						"source_line": int(source_lines.get("start", 0)),
					}
				)
			compact_events.sort_custom(_sort_events)
			var updated_spec := spec.duplicate(true)
			updated_spec["source_events"] = compact_events
			updated_spec["source_event_sync"] = {
				"audit": EVENT_AUDIT_PATH,
				"source_action_label": source_action_label,
				"source_symbol_id": source_symbol_id,
			}
			profile.actions[raw_action] = updated_spec
			synced_actions += 1
			synced_events += compact_events.size()
		if _failed:
			continue
		var manual_after_update := _manual_snapshot(profile)
		if manual_before != manual_after_update:
			_fail("Manual action fields changed in memory before saving %s." % profile_path)
			continue
		profile.source_event_audit = EVENT_AUDIT_PATH
		var save_error := ResourceSaver.save(profile, profile_path)
		if save_error != OK:
			_fail("Failed to save %s: %s" % [profile_path, error_string(save_error)])
			continue
		var reloaded := ResourceLoader.load(profile_path, "", ResourceLoader.CACHE_MODE_REPLACE) as EnemyAnimationProfile
		if reloaded == null:
			_fail("Failed to reload synchronized profile %s." % profile_path)
			continue
		if manual_before != _manual_snapshot(reloaded):
			_fail("Manual action fields changed after saving %s." % profile_path)
			continue
		var validation_errors := reloaded.validate()
		if not validation_errors.is_empty():
			_fail("Synchronized profile %s is invalid: %s" % [profile_path, "; ".join(validation_errors)])
			continue
		sync_rows.append(
			{
				"profile": profile_path.trim_prefix("res://"),
				"monster": monster_key,
				"package": str(profile.source_package),
				"actions": synced_actions,
				"events": synced_events,
				"skipped_no_op": skipped_no_op,
				"manual_fields_preserved": true,
			}
		)
	_finish(sync_rows)


func _find_provider(monster: Dictionary, action_label: String, symbol_id: int) -> Dictionary:
	for raw_action: Variant in monster.get("actions", []):
		if not raw_action is Dictionary:
			continue
		var action := raw_action as Dictionary
		if str(action.get("label", "")) != action_label:
			continue
		for raw_provider: Variant in action.get("providers", []):
			if raw_provider is Dictionary and int((raw_provider as Dictionary).get("symbol_id", 0)) == symbol_id:
				return raw_provider as Dictionary
	return {}


func _manual_snapshot(profile: EnemyAnimationProfile) -> Dictionary:
	var snapshot := {}
	for raw_action: Variant in profile.actions:
		var source_spec: Dictionary = profile.actions[raw_action]
		var manual_spec := {}
		for raw_key: Variant in source_spec:
			var key := StringName(raw_key)
			if key in GENERATED_KEYS:
				continue
			manual_spec[raw_key] = source_spec[raw_key]
		snapshot[raw_action] = manual_spec
	return snapshot


func _event_id(event: Dictionary) -> StringName:
	var code := str(event.get("code", "")).to_lower()
	var types := PackedStringArray(event.get("types", []))
	if "firehit" in code:
		return &"fire_hit"
	if "setyourfather" in code:
		return &"set_invulnerable"
	if "newattackid" in code:
		return &"refresh_attack_id"
	if "getnewobj" in code or "object_spawn" in types:
		return &"spawn_object"
	if "action_transition" in types:
		return &"action_transition"
	if "visibility" in types:
		return &"visibility"
	if "motion" in types:
		return &"motion"
	if "timeline_control" in types:
		return &"timeline_control"
	var method := str(event.get("method", "source_frame_script")).to_snake_case()
	return StringName(method if not method.is_empty() else "source_frame_script")


func _sort_events(left: Dictionary, right: Dictionary) -> bool:
	var left_frame := int(left.get("frame", -1))
	var right_frame := int(right.get("frame", -1))
	if left_frame != right_frame:
		return left_frame < right_frame
	return str(left.get("id", "")) < str(right.get("id", ""))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _fail(message: String) -> void:
	_failed = true
	_failure_messages.append(message)
	push_error(message)


func _finish(rows: Array[Dictionary]) -> void:
	var audit := {
		"generated_at": Time.get_datetime_string_from_system(true, true),
		"source_event_audit": EVENT_AUDIT_PATH.trim_prefix("res://"),
		"source_event_audit_sha256": FileAccess.get_sha256(EVENT_AUDIT_PATH),
		"policy": (
			"Only exact complete-provider frame scripts are synchronized. Existing profile fields are preserved; "
			+ "raw ActionScript is never executed automatically."
		),
		"profiles": rows,
		"counts": {
			"profiles": rows.size(),
			"actions": rows.reduce(func(total: int, row: Dictionary) -> int: return total + int(row["actions"]), 0),
			"events": rows.reduce(func(total: int, row: Dictionary) -> int: return total + int(row["events"]), 0),
		},
		"validation": {
			"status": "fail" if _failed else "pass",
			"manual_fields_preserved": not _failed,
			"errors": _failure_messages,
		},
	}
	var handle := FileAccess.open(SYNC_AUDIT_PATH, FileAccess.WRITE)
	if handle == null:
		push_error("Cannot write sync audit: %s" % SYNC_AUDIT_PATH)
		quit(1)
		return
	handle.store_string(JSON.stringify(audit, "  ") + "\n")
	print(JSON.stringify({"profiles": rows.size(), "failed": _failed, "rows": rows}, "  "))
	quit(1 if _failed else 0)
