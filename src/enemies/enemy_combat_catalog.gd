class_name EnemyCombatCatalog
extends RefCounted

## Read-only adapter from the reviewed ActionScript audit to runtime combat data.
##
## Animation profiles remain the authority for visuals. This catalog only
## resolves source attack fields (power, attack kind, hit limits, intervals,
## and knockback) so gameplay does not duplicate or guess those values.

const DEFAULT_AUDIT_PATH := "res://sources/manifests/zmxiyou1_monster_events.json"
const DEFAULT_MELEE_HITBOX_AUDIT_PATH := "res://sources/manifests/zmxiyou1_enemy_melee_hitboxes.json"
const SOURCE_TICK_RATE := 24.0

static var _audit_cache: Dictionary = {}
static var _melee_hitbox_audit_cache: Dictionary = {}


# Public attack queries

# The returned dictionary is the runtime contract shared by melee attacks and
# bullets: normalized damage, hit cadence, px/s knockback, active frames,
# optional status effects, and source traceability. Atlas paths stay in the
# animation profile and are never duplicated here.
static func resolve_attack(
	profile: EnemyAnimationProfile, action: StringName, variant_override: int = -1
) -> Dictionary:
	if profile == null or profile.source_monster_id == &"":
		return {}
	var audit_path := profile.source_event_audit
	if audit_path.is_empty():
		audit_path = DEFAULT_AUDIT_PATH
	var audit := _load_audit(audit_path)
	var monsters: Dictionary = audit.get("monsters", {})
	var monster: Dictionary = monsters.get(str(profile.source_monster_id), {})
	if monster.is_empty():
		return {}
	var attack_profiles: Dictionary = monster.get("attack_profiles", {})
	var action_spec := profile.get_spec(action)
	var source_action := str(action_spec.get("source_action_label", ""))
	if source_action.is_empty():
		source_action = infer_source_action(action)
	if not attack_profiles.has(source_action):
		return {}

	var raw_variants: Variant = attack_profiles[source_action]
	var variants: Array = raw_variants if raw_variants is Array else [raw_variants]
	if variants.is_empty():
		return {}
	var variant_index := (
		variant_override
		if variant_override >= 0
		else int(action_spec.get("source_attack_variant", variants.size() - 1))
	)
	variant_index = clampi(variant_index, 0, variants.size() - 1)
	var source_entry: Dictionary = variants[variant_index]
	var fields: Dictionary = source_entry.get("fields", {})
	var source_knockback := _parse_vector2(fields.get("attackBackSpeed", "[0,0]"))
	var source_fps := float(action_spec.get("source_fps", SOURCE_TICK_RATE))
	var frame_count := int(action_spec.get("frame_count", 1))
	var active_frames := Vector2i(action_spec.get("hitbox_frame_range", Vector2i(-1, -1)))
	if active_frames.x < 0:
		active_frames = _default_active_frames(frame_count)

	var result := {
		"runtime_action": action,
		"source_action": source_action,
		"source_monster_id": profile.source_monster_id,
		"damage": int(fields.get("power", 0)),
		# Flash names physical damage "physics". Runtime role skills use the
		# canonical Godot-facing name "physical" (magic already matches).
		"damage_kind": _normalize_damage_kind(fields.get("attackKind", "physics")),
		"hit_max_count": maxi(1, int(fields.get("hitMaxCount", 1))),
		"rehit_interval_frames": maxi(1, int(fields.get("attackInterval", 999))),
		"source_knockback": source_knockback,
		"knockback_velocity": source_knockback * source_fps,
		"active_frame_range": active_frames,
		"variant_index": variant_index,
		"source": str(source_entry.get("source", "")),
		"source_lines": Dictionary(source_entry.get("source_lines", {})),
		"status_effects": _parse_status_effects(source_entry),
	}
	result.merge(
		_resolve_melee_geometry(profile.source_monster_id, action, StringName(source_action)), true
	)
	return result


static func get_attack_actions(profile: EnemyAnimationProfile) -> PackedStringArray:
	var result := PackedStringArray()
	if profile == null:
		return result
	for raw_action: Variant in profile.actions:
		var action := StringName(raw_action)
		if not resolve_attack(profile, action).is_empty():
			result.append(str(action))
	result.sort()
	return result


static func infer_source_action(action: StringName) -> String:
	var runtime_name := str(action)
	if runtime_name.begins_with("attack"):
		var suffix := runtime_name.trim_prefix("attack")
		var parts := suffix.split("_", false)
		if parts.size() >= 2:
			return "hit%s-%s" % [parts[0], parts[1]]
		return "hit%s" % suffix
	if runtime_name == "move":
		return "walk"
	return runtime_name


static func clear_cache() -> void:
	_audit_cache.clear()
	_melee_hitbox_audit_cache.clear()


# Reviewed melee geometry

static func _resolve_melee_geometry(
	monster_id: StringName, action: StringName, source_action: StringName
) -> Dictionary:
	var audit := _load_melee_hitbox_audit(DEFAULT_MELEE_HITBOX_AUDIT_PATH)
	var monster: Dictionary = Dictionary(audit.get("monsters", {})).get(str(monster_id), {})
	var actions := Dictionary(monster.get("actions", {}))
	var action_entry: Dictionary = actions.get(str(action), {})
	if action_entry.is_empty():
		for raw_entry: Variant in actions.values():
			if (
				raw_entry is Dictionary
				and StringName((raw_entry as Dictionary).get("source_action_label", &""))
				== source_action
			):
				action_entry = raw_entry as Dictionary
				break
	if action_entry.is_empty():
		return {}
	var frames: Variant = action_entry.get("frames", [])
	if not frames is Array:
		return {}
	var active_raw: Array = Array(action_entry.get("active_frame_range", [-1, -1]))
	var active_frames := Vector2i(-1, -1)
	if active_raw.size() >= 2:
		active_frames = Vector2i(int(active_raw[0]), int(active_raw[1]))
	return {
		"melee_geometry_reviewed": true,
		"melee_frame_hitboxes": frames,
		"melee_registration_to_atlas_center": _parse_vector2(
			action_entry.get("registration_to_atlas_center", [0.0, 0.0])
		),
		"melee_source_canvas": _parse_vector2(action_entry.get("source_canvas", [0.0, 0.0])),
		"active_frame_range": active_frames,
		"melee_geometry_source": DEFAULT_MELEE_HITBOX_AUDIT_PATH,
	}


# JSON audit caches

static func _load_audit(path: String) -> Dictionary:
	if _audit_cache.has(path):
		return _audit_cache[path]
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Enemy combat source audit is missing: %s" % path)
		_audit_cache[path] = {}
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Enemy combat source audit is invalid JSON: %s" % path)
		_audit_cache[path] = {}
		return {}
	_audit_cache[path] = parsed
	return parsed


static func _load_melee_hitbox_audit(path: String) -> Dictionary:
	if _melee_hitbox_audit_cache.has(path):
		return _melee_hitbox_audit_cache[path]
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Enemy melee hitbox source audit is missing: %s" % path)
		_melee_hitbox_audit_cache[path] = {}
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Enemy melee hitbox source audit is invalid JSON: %s" % path)
		_melee_hitbox_audit_cache[path] = {}
		return {}
	_melee_hitbox_audit_cache[path] = parsed
	return parsed


# Source value parsing

static func _parse_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		var array := value as Array
		if array.size() >= 2:
			return Vector2(float(array[0]), float(array[1]))
	var text := str(value).strip_edges().trim_prefix("[").trim_suffix("]")
	var parts := text.split(",", false)
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))


static func _normalize_damage_kind(value: Variant) -> StringName:
	var source_kind := StringName(str(value).to_lower())
	return &"physical" if source_kind == &"physics" else source_kind


static func _parse_status_effects(source_entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source_code := str(source_entry.get("code", ""))
	if source_code.is_empty() or "addEffect" not in source_code:
		return result
	var expression := RegEx.new()
	var pattern := "\"name\"\\s*:\\s*\"([^\"]+)\"\\s*,\\s*\"time\"\\s*:\\s*(\\d+)(?:\\s*\\*\\s*(\\d+))?\\s*,\\s*\"power\"\\s*:\\s*(\\d+)"
	if expression.compile(pattern) != OK:
		return result
	for match_result: RegExMatch in expression.search_all(source_code):
		var factor_a := int(match_result.get_string(2))
		var factor_b_text := match_result.get_string(3)
		var factor_b := int(factor_b_text) if not factor_b_text.is_empty() else 1
		result.append({
			"id": StringName(match_result.get_string(1)),
			"duration_ticks": factor_a * factor_b,
			"power": int(match_result.get_string(4)),
		})
	return result


static func _default_active_frames(frame_count: int) -> Vector2i:
	if frame_count <= 1:
		return Vector2i(0, 0)
	var start := clampi(floori(frame_count * 0.35), 0, frame_count - 1)
	var finish := clampi(ceili(frame_count * 0.65), start, frame_count - 1)
	return Vector2i(start, finish)
