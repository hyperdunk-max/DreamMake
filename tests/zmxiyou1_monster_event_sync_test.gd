extends SceneTree

const PROFILE_DIRECTORY := "res://resources/enemies/animations"
const SYNC_MANIFEST := "res://sources/manifests/zmxiyou1_monster_event_sync.json"

var _failed := false


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var profile_count := 0
	var action_count := 0
	var runtime_component_count := 0
	for file_name: String in DirAccess.get_files_at(PROFILE_DIRECTORY):
		if not file_name.begins_with("zmxiyou1_") or not file_name.ends_with("_profile.tres"):
			continue
		var profile := load(PROFILE_DIRECTORY.path_join(file_name)) as EnemyAnimationProfile
		if profile == null or profile.source_monster_id == &"":
			continue
		profile_count += 1
		for raw_action: Variant in profile.actions:
			var action := StringName(raw_action)
			var spec := profile.get_spec(action)
			action_count += 1
			var sync: Dictionary = spec.get("source_event_sync", {})
			if bool(spec.get("runtime_component", false)):
				runtime_component_count += 1
				_assert(
					str(sync.get("mode", "")) == "runtime_component",
					"%s/%s should declare runtime-component event mode." % [file_name, action]
				)
				_assert(
					str(sync.get("audit", ""))
					== "res://sources/manifests/zmxiyou1_enemy_combat_runtime_assets.json",
					"%s/%s should point at the runtime-component audit." % [file_name, action]
				)
				_assert(
					int(spec.get("source_symbol_id", 0)) > 0,
					"%s/%s should preserve its reviewed source symbol." % [file_name, action]
				)
				_assert(
					profile.get_source_events(action).is_empty(),
					"%s/%s runtime component should not invent root timeline events."
					% [file_name, action]
				)
			else:
				_assert(
					not str(spec.get("source_action_label", "")).is_empty(),
					"%s/%s needs a source label." % [file_name, action]
				)
				_assert(
					str(sync.get("audit", ""))
					== "res://sources/manifests/zmxiyou1_monster_events.json",
					"%s/%s should point at the canonical event audit." % [file_name, action]
				)
			for raw_event: Variant in profile.get_source_events(action):
				var event := raw_event as Dictionary
				var frame := int(event.get("frame", -1))
				_assert(frame >= 0 and frame < int(spec.get("frame_count", 0)), "%s/%s event frame must remain inside the atlas." % [file_name, action])
				_assert(not str(event.get("source_code", "")).is_empty(), "%s/%s event should preserve source code evidence." % [file_name, action])
	_assert(profile_count == 27, "Event sync should cover 27 reviewed runtime profiles.")
	_assert(action_count == 165, "Event sync should cover all 165 selected atlas actions.")
	_assert(runtime_component_count == 4, "Event sync should cover all four M24 runtime components.")
	_test_boss_event_contracts()
	_test_sync_manifest(profile_count, action_count)
	print("ZMX1 monster event sync test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _test_boss_event_contracts() -> void:
	var m19 := load("res://resources/enemies/animations/zmxiyou1_m19_shark_profile.tres") as EnemyAnimationProfile
	var stage2 := m19.get_spec(&"attack3_2")
	_assert(int(stage2.get("source_symbol_id", 0)) == 399, "M19 hit3-2 should use reviewed symbol 399.")
	_assert(_event_ids(m19, &"attack3_2") == PackedStringArray(["projectile_warning", "action_transition"]), "M19 hit3-2 should retain warning and completion events.")

	var m23 := load("res://resources/enemies/animations/zmxiyou1_m23_bull_profile.tres") as EnemyAnimationProfile
	var ids := _event_ids(m23, &"attack5")
	_assert(&"grab_check" in ids, "M23 attack5 should retain its conditional grab event.")
	_assert(ids.count(&"life_steal_tick") == 5, "M23 attack5 should retain five source drain events.")
	_assert(&"action_transition" in ids, "M23 attack5 should retain its cleanup transition.")


func _test_sync_manifest(profile_count: int, action_count: int) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SYNC_MANIFEST))
	_assert(parsed is Dictionary, "Event sync manifest should remain valid JSON.")
	if not parsed is Dictionary:
		return
	var counts: Dictionary = (parsed as Dictionary).get("counts", {})
	_assert(int(counts.get("profiles", 0)) == profile_count, "Sync manifest profile count should match runtime.")
	_assert(int(counts.get("actions", 0)) == action_count, "Sync manifest action count should match runtime.")
	_assert(str((parsed as Dictionary).get("validation", {}).get("status", "")) == "pass", "Sync manifest validation should pass.")


func _event_ids(profile: EnemyAnimationProfile, action: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_event: Variant in profile.get_source_events(action):
		result.append(str((raw_event as Dictionary).get("id", &"")))
	return result


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
