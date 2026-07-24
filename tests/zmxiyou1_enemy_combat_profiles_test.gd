extends SceneTree

const DEFINITION_DIR := "res://resources/enemies"
const EXPECTED_RUNTIME_IDS := [
	"M01", "M02", "M03", "M04", "M06", "M07", "M08", "M09", "M10", "M11",
	"M13", "M14", "M15", "M16", "M17", "M18", "M19", "M20", "M21", "M22",
	"M23", "M24", "M25", "M26", "M27",
]
const SOURCE_NONCOMBAT_IDS := ["M21", "M27"]
const SOURCE_CONTROLLER_DAMAGE_IDS := ["M24"]
const REVIEW_BLOCKED_IDS: Array[String] = []

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var found := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(DEFINITION_DIR):
		if not file_name.begins_with("zmxiyou1_m") or not file_name.ends_with(".tres"):
			continue
		var definition := load(DEFINITION_DIR.path_join(file_name)) as EnemyDefinition
		if definition == null or definition.animation_profile == null:
			continue
		var source_id := str(definition.animation_profile.source_monster_id)
		if source_id.is_empty() or source_id in found:
			continue
		found.append(source_id)
		_assert(definition.validate().is_empty(), "%s should validate as a runtime enemy." % source_id)
		var attacks := EnemyCombatCatalog.get_attack_actions(definition.animation_profile)
		if source_id in SOURCE_NONCOMBAT_IDS:
			_assert(attacks.is_empty(), "%s is a source noncombat object and should not invent attacks." % source_id)
		else:
			_assert(not attacks.is_empty(), "%s should expose at least one source-backed attack." % source_id)
		for action: String in attacks:
			var combat := EnemyCombatCatalog.resolve_attack(definition.animation_profile, StringName(action))
			_assert(int(combat.get("damage", 0)) > 0, "%s/%s should resolve positive source power." % [source_id, action])
			var action_spec := definition.animation_profile.get_spec(StringName(action))
			var has_projectile := not str(action_spec.get("bullet_sprite_sheet", "")).is_empty()
			var has_event_damage := false
			for raw_event: Variant in definition.animation_profile.get_source_events(StringName(action)):
				if raw_event is Dictionary and StringName((raw_event as Dictionary).get("id", &"")) in [
					&"grab_check", &"life_steal_tick"
				]:
					has_event_damage = true
			_assert(
				bool(combat.get("melee_geometry_reviewed", false))
				or has_projectile
				or has_event_damage
				or source_id in SOURCE_CONTROLLER_DAMAGE_IDS,
				"%s/%s must use reviewed stick geometry, an atlas projectile, a typed source event, or its dedicated source controller."
				% [source_id, action]
			)
	found.sort()
	var expected := PackedStringArray(EXPECTED_RUNTIME_IDS)
	expected.sort()
	_assert(found == expected, "Canonical runtime definitions should cover all reviewed IDs except %s." % [REVIEW_BLOCKED_IDS])
	print("ZMX1 enemy combat profile test: %s" % ("FAILED" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
