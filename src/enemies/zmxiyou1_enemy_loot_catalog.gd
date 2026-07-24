class_name Zmxiyou1EnemyLootCatalog
extends RefCounted

## Read-only adapter for the reviewed ActionScript death-loot audit.
## Visuals remain sprite-pack assets; this class only resolves source values
## and preserves the original non-uniform Math.round equipment selection.

const DEFAULT_AUDIT_PATH := "res://sources/manifests/zmxiyou1_enemy_loot_audit.json"

static var _audit_cache: Dictionary = {}


static func resolve(
	profile: EnemyAnimationProfile,
	source_stage: int,
	source_level: int,
	player_level: int = 1,
	owns_dhqf: bool = false
) -> Dictionary:
	if profile == null or profile.source_monster_id == &"":
		return {}
	var audit := _load_audit(DEFAULT_AUDIT_PATH)
	var profiles: Dictionary = audit.get("profiles", {})
	var source_id := str(profile.source_monster_id)
	var raw: Dictionary = profiles.get(source_id, {})
	if raw.is_empty():
		return {}
	var result := raw.duplicate(true)
	if source_id == "M03":
		result = _resolve_named_variant(raw, "stage_1_level_1" if source_stage == 1 and source_level == 1 else "other")
	elif source_id == "M17":
		result = _resolve_named_variant(raw, "stage_3_level_1" if source_stage == 3 and source_level == 1 else "other")
	elif source_id == "M26":
		var combat_variant := (
			"owns_dhqf_level_above_20" if player_level > 20
			else "owns_dhqf_level_at_most_20"
		)
		result = _resolve_named_variant(raw, combat_variant)
		if not owns_dhqf:
			var guaranteed := _resolve_named_variant(raw, "missing_dhqf")
			result["equipment_probability"] = guaranteed.get("equipment_probability", 1.0)
			result["fall_list"] = guaranteed.get("fall_list", ["dhqf"])
	result["source_monster_id"] = StringName(source_id)
	result["drop_aura"] = bool(result.get("drop_aura", true))
	result["equipment_probability"] = float(result.get("equipment_probability", 0.15))
	result["fall_list"] = Array(result.get("fall_list", [])).duplicate()
	return result


static func roll_bonus_count(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < 0.04:
		return 3
	if roll < 0.08:
		return 2
	if roll < 0.12:
		return 1
	return 0


static func roll_medicine(rng: RandomNumberGenerator) -> StringName:
	# Preserve the two independent Math.random() calls in BaseMonster.addMedicine.
	if rng.randf() >= 0.5:
		var health_roll := rng.randf()
		if health_roll <= 0.05:
			return &"small_hp" if rng.randf() >= 0.5 else &"big_hp"
		if health_roll <= 0.1:
			return &"small_hp"
	elif rng.randf() <= 0.1:
		return &"small_mp"
	return &""


static func roll_equipment(profile_data: Dictionary, rng: RandomNumberGenerator) -> StringName:
	if rng.randf() > float(profile_data.get("equipment_probability", 0.15)):
		return &""
	# Source consumes the Math.random used by Math.round even when a malformed
	# or empty fallList later produces no object. Keep the aura RNG sequence.
	var selection_roll := rng.randf()
	var fall_list: Array = profile_data.get("fall_list", [])
	if fall_list.is_empty():
		return &""
	# ActionScript uses Math.round rather than floor, so the first and last
	# entries have half the selection width of interior entries.
	var index := roundi(selection_roll * float(fall_list.size() - 1))
	return StringName(str(fall_list[clampi(index, 0, fall_list.size() - 1)]))


static func clear_cache() -> void:
	_audit_cache.clear()


static func _resolve_named_variant(raw: Dictionary, variant_name: String) -> Dictionary:
	var variants: Dictionary = raw.get("variants", {})
	return Dictionary(variants.get(variant_name, {})).duplicate(true)


static func _load_audit(path: String) -> Dictionary:
	if _audit_cache.has(path):
		return _audit_cache[path]
	if not FileAccess.file_exists(path):
		push_error("ZMX1 enemy loot audit is missing: %s" % path)
		_audit_cache[path] = {}
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("ZMX1 enemy loot audit is invalid JSON: %s" % path)
		_audit_cache[path] = {}
		return {}
	_audit_cache[path] = parsed
	return parsed
