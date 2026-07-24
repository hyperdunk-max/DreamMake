extends SceneTree

## Synchronize exact addFrameScript events into runtime EnemyAnimationProfile
## resources. Existing action fields are treated as manual configuration and
## must remain byte-for-byte equivalent as Godot Variants after saving.

const EVENT_AUDIT_PATH := "res://sources/manifests/zmxiyou1_monster_events.json"
const SELECTION_AUDIT_PATH := "res://sources/manifests/zmxiyou1_all_monster_animations_selected.json"
const PROFILE_DIRECTORY := "res://resources/enemies/animations"
const SYNC_AUDIT_PATH := "res://sources/manifests/zmxiyou1_monster_event_sync.json"
const GENERATED_KEYS := [
	&"source_action_label",
	&"source_symbol_id",
	&"source_event_symbol_ids",
	&"source_events",
	&"source_event_sync",
]
const SELECTION_SYMBOL_OVERRIDES := {
	"M04/attack2": "元件45ssss_9",
	"M06/attack1": "元件9_23",
	"M06/attack2": "元件12_26",
	"M08/attack1": "character_218",
	"M09/egg": "Timeline_101",
	"M09/attack2": "Timeline_97",
	"M09/reburn": "character_622",
	"M10/attack1": "Timeline_21",
	"M10/attack3": "character_1112",
	"M11/attack2": "Timeline_190",
	"M11/attack3": "character_159",
	"M16/attack2": "Timeline_76",
	"M18/attack2": "Timeline_174",
	"M20/attack1": "Timeline_212",
	"M23/attack2": "Timeline_35",
	"M23/attack3": "Timeline_40",
	"M23/attack4": "Timeline_42",
	"M23/attack5": "Timeline_52",
	"M26/attack2": "Timeline_14",
	"M26/attack3": "Timeline_26",
}

var _failed := false
var _failure_messages: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest := _read_json(EVENT_AUDIT_PATH)
	var selection_manifest := _read_json(SELECTION_AUDIT_PATH)
	if manifest.is_empty() or selection_manifest.is_empty():
		_fail(
			"Monster event or selection audit is missing/invalid: %s, %s"
			% [EVENT_AUDIT_PATH, SELECTION_AUDIT_PATH]
		)
		_finish([])
		return
	var monsters: Dictionary = manifest.get("monsters", {})
	var selected_monsters: Dictionary = selection_manifest.get("monsters", {})
	var sync_rows: Array[Dictionary] = []
	var files := DirAccess.get_files_at(PROFILE_DIRECTORY)
	files.sort()
	for file_name: String in files:
		if not file_name.begins_with("zmxiyou1_") or not file_name.ends_with(".tres"):
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
		if not selected_monsters.has(monster_key):
			_fail("%s has no reviewed animation selection for %s." % [profile_path, monster_key])
			continue
		var monster: Dictionary = monsters[monster_key]
		var selected_monster: Dictionary = selected_monsters[monster_key]
		var reviewed_package := StringName(str(monster.get("package", "")))
		profile.source_package = reviewed_package
		var manual_before := _manual_snapshot(profile)
		var synced_actions := 0
		var synced_events := 0
		var skipped_no_op := 0
		for raw_action: Variant in profile.actions:
			var action := StringName(raw_action)
			var spec: Dictionary = profile.actions[raw_action]
			# Program-controlled composite parts (M24 Hands/Fire/BG/Eyes) are
			# reviewed source symbols but are not root action atlas rows. They
			# intentionally carry no addFrameScript events; their 24 Hz behavior
			# lives in the audited source controller instead.
			if bool(spec.get("runtime_component", false)):
				var component_spec := spec.duplicate(true)
				component_spec["source_event_symbol_ids"] = PackedInt32Array()
				component_spec["source_events"] = []
				component_spec["source_event_sync"] = {
					"mode": "runtime_component",
					"audit": "res://sources/manifests/zmxiyou1_enemy_combat_runtime_assets.json",
					"source_symbol_id": int(spec.get("source_symbol_id", 0)),
				}
				profile.actions[raw_action] = component_spec
				synced_actions += 1
				continue
			var selection := _find_selected_action(selected_monster, str(action))
			if selection.is_empty():
				_fail("%s action %s has no reviewed selected-atlas row." % [profile_path, action])
				continue
			var source_action_label := str(selection.get("source_action_label", ""))
			var source_action := _find_source_action(monster, source_action_label)
			var source_symbol_id := _resolve_source_symbol_id(
				monster_key, str(action), source_action, int(selection.get("source_symbol_id", 0))
			)
			var provider := _find_provider(monster, source_action_label, source_symbol_id)
			if provider.is_empty() and not Array(source_action.get("providers", [])).is_empty():
				_fail(
					"%s action %s cannot find source label %s symbol %d."
					% [profile_path, action, source_action_label, source_symbol_id]
				)
				continue
			var frame_count := int(spec.get("frame_count", 0))
			var compact_events: Array[Dictionary] = []
			var event_symbol_ids := PackedInt32Array()
			for raw_event_provider: Variant in source_action.get("providers", []):
				if not raw_event_provider is Dictionary:
					continue
				var event_provider := raw_event_provider as Dictionary
				var event_symbol_id := int(event_provider.get("symbol_id", 0))
				if int(event_provider.get("frame_count", 0)) > frame_count:
					continue
				for raw_event: Variant in event_provider.get("frame_events", []):
					if not raw_event is Dictionary:
						continue
					var event := raw_event as Dictionary
					var source_types := PackedStringArray(event.get("types", []))
					if source_types == PackedStringArray(["no_op"]):
						skipped_no_op += 1
						continue
					var source_frame := int(event.get("action_frame", event.get("frame", 0)))
					var runtime_frame := source_frame - 1
					if runtime_frame < 0 or runtime_frame >= frame_count:
						_fail(
							"%s action %s event frame %d from symbol %d is outside its %d frames."
							% [profile_path, action, runtime_frame, event_symbol_id, frame_count]
						)
						continue
					var source_lines: Dictionary = event.get("source_lines", {})
					var event_id := _event_id(event)
					compact_events.append(
						{
							"frame": runtime_frame,
							"source_frame": source_frame,
							"id": event_id,
							"types": _runtime_event_types(event, event_id),
							"source_types": source_types,
							"method": str(event.get("method", "")),
							"source": str(event.get("source", "")),
							"source_line": int(source_lines.get("start", 0)),
							"source_symbol_id": event_symbol_id,
							"source_code": str(event.get("code", "")),
						}
					)
					if event_symbol_id not in event_symbol_ids:
						event_symbol_ids.append(event_symbol_id)
			compact_events.sort_custom(_sort_events)
			var updated_spec := spec.duplicate(true)
			updated_spec["source_action_label"] = source_action_label
			updated_spec["source_symbol_id"] = source_symbol_id
			updated_spec["source_event_symbol_ids"] = event_symbol_ids
			updated_spec["source_events"] = compact_events
			updated_spec["source_event_sync"] = {
				"audit": EVENT_AUDIT_PATH,
				"selection_audit": SELECTION_AUDIT_PATH,
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


func _find_source_action(monster: Dictionary, action_label: String) -> Dictionary:
	for raw_action: Variant in monster.get("actions", []):
		if raw_action is Dictionary and str((raw_action as Dictionary).get("label", "")) == action_label:
			return raw_action as Dictionary
	return {}


func _find_selected_action(selected_monster: Dictionary, runtime_action: String) -> Dictionary:
	for raw_action: Variant in selected_monster.get("actions", []):
		if raw_action is Dictionary and str((raw_action as Dictionary).get("runtime_action", "")) == runtime_action:
			return raw_action as Dictionary
	var expected_label := _runtime_source_label(runtime_action)
	for raw_action: Variant in selected_monster.get("actions", []):
		if raw_action is Dictionary and str((raw_action as Dictionary).get("source_action_label", "")) == expected_label:
			return raw_action as Dictionary
	return {}


func _runtime_source_label(runtime_action: String) -> String:
	if runtime_action.begins_with("attack"):
		return "hit%s" % runtime_action.trim_prefix("attack").replace("_", "-")
	if runtime_action.begins_with("idle"):
		return "wait%s" % runtime_action.trim_prefix("idle")
	if runtime_action.begins_with("move"):
		return "walk%s" % runtime_action.trim_prefix("move")
	match runtime_action:
		"death":
			return "dead"
		"recover":
			return "afterHurt"
		"egg":
			return "turnToEgg"
		"reburn":
			return "reBurn"
	return runtime_action


func _resolve_source_symbol_id(
	monster_key: String, runtime_action: String, source_action: Dictionary, fallback: int
) -> int:
	var override_key := "%s/%s" % [monster_key, runtime_action]
	var symbol_suffix := str(SELECTION_SYMBOL_OVERRIDES.get(override_key, ""))
	if symbol_suffix.is_empty():
		return fallback
	for raw_provider: Variant in source_action.get("providers", []):
		if not raw_provider is Dictionary:
			continue
		var provider := raw_provider as Dictionary
		if str(provider.get("symbol_name", "")).ends_with(symbol_suffix):
			return int(provider.get("symbol_id", fallback))
	return fallback


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
	if "checkdohit5" in code:
		return &"grab_check"
	if "reducehp" in code and "curehp" in code:
		return &"life_steal_tick"
	if "dohit2pre" in code or "dohit3pre" in code:
		return &"projectile_warning"
	if "throwknife" in code:
		return &"projectile_spawn"
	if "dohit" in code and "();" in code:
		return &"projectile_spawn"
	if "firehit" in code:
		return &"fire_hit"
	if "setyourfather" in code:
		return &"set_invulnerable"
	if "newattackid" in code:
		return &"refresh_attack_id"
	if "getnewobj" in code or "object_spawn" in types:
		return &"spawn_object"
	if "action_transition" in types and "curaction" in code:
		return &"action_transition"
	if "action_transition" in types:
		return &"timeline_branch"
	if "visibility" in types:
		return &"visibility"
	if "motion" in types:
		return &"motion"
	if "timeline_control" in types:
		return &"timeline_control"
	var method := str(event.get("method", "source_frame_script")).to_snake_case()
	return StringName(method if not method.is_empty() else "source_frame_script")


func _runtime_event_types(event: Dictionary, event_id: StringName) -> PackedStringArray:
	var result := PackedStringArray(event.get("types", []))
	match event_id:
		&"projectile_spawn", &"fire_hit":
			if "bullet_spawn" not in result:
				result.append("bullet_spawn")
		&"projectile_warning":
			if "bullet_warning" not in result:
				result.append("bullet_warning")
		&"refresh_attack_id":
			if "attack_refresh" not in result:
				result.append("attack_refresh")
		&"life_steal_tick":
			if "life_steal" not in result:
				result.append("life_steal")
	return result


func _sort_events(left: Dictionary, right: Dictionary) -> bool:
	var left_frame := int(left.get("frame", -1))
	var right_frame := int(right.get("frame", -1))
	if left_frame != right_frame:
		return left_frame < right_frame
	var left_symbol := int(left.get("source_symbol_id", 0))
	var right_symbol := int(right.get("source_symbol_id", 0))
	if left_symbol != right_symbol:
		return left_symbol < right_symbol
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
		"selection_audit": SELECTION_AUDIT_PATH.trim_prefix("res://"),
		"selection_audit_sha256": FileAccess.get_sha256(SELECTION_AUDIT_PATH),
		"policy": (
			"Selected-atlas symbols provide visual provenance; all audited provider frame scripts for the same "
			+ "source action are synchronized as inert typed events. Existing gameplay/visual fields are preserved "
			+ "and raw ActionScript is never executed automatically."
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
