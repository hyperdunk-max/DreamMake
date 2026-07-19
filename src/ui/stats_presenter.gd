class_name StatsPresenter
extends RefCounted

## Event-driven character/equipment snapshot source for StatsPanel.

signal view_changed(snapshot: Dictionary)

const STAT_DEFINITIONS: Array[Dictionary] = [
	{"key": "max_health", "label": "生命", "percent": false},
	{"key": "max_mana", "label": "魔法", "percent": false},
	{"key": "attack", "label": "攻击", "percent": false},
	{"key": "defense", "label": "防御", "percent": false},
	{"key": "crit_rate", "label": "暴击", "percent": true},
	{"key": "dodge_rate", "label": "闪避", "percent": true},
	{"key": "hp_regen", "label": "回血", "percent": false},
	{"key": "mp_regen", "label": "回蓝", "percent": false},
	{"key": "magic_resist", "label": "魔抗", "percent": true},
]

var _player: CharacterBody2D
var _last_snapshot: Dictionary = {}


func setup(owner_player: CharacterBody2D) -> void:
	_player = owner_player
	_connect_domain_events()
	refresh()


func refresh() -> void:
	if _player == null or _player.stats == null:
		return
	var rows: Array[Dictionary] = []
	for definition: Dictionary in STAT_DEFINITIONS:
		var key: String = str(definition["key"])
		var base_value: float = _get_base_value(key)
		var effective_value: float = _get_effective_value(key)
		rows.append({
			"key": key,
			"label": str(definition["label"]),
			"percent": bool(definition["percent"]),
			"base": base_value,
			"bonus": effective_value - base_value,
			"effective": effective_value,
		})
	var profile: RoleAnimationProfile = _player.animation_profile
	var body_atlas: Texture2D
	var weapon_atlas: Texture2D
	var frame_size: Vector2i = Vector2i(200, 200)
	if profile != null:
		body_atlas = profile.get_body_atlas(_player.body_showid, _player.weapon_showid)
		weapon_atlas = profile.get_weapon_atlas(_player.weapon_showid)
		frame_size = profile.frame_size
	_last_snapshot = {
		"role_name": _player.role_definition.display_name if _player.role_definition != null else "",
		"role_id": _player.role_id,
		"health": _player.health,
		"mana": _player.mana,
		"rows": rows,
		"equipment": _get_equipment_summary(),
		"body_atlas": body_atlas,
		"weapon_atlas": weapon_atlas,
		"frame_size": frame_size,
	}
	view_changed.emit(_last_snapshot.duplicate(true))


func get_last_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func _connect_domain_events() -> void:
	if not _player.equipment_changed.is_connected(_on_equipment_changed):
		_player.equipment_changed.connect(_on_equipment_changed)
	if not _player.role_changed.is_connected(_on_role_changed):
		_player.role_changed.connect(_on_role_changed)
	if not _player.health_changed.is_connected(_on_health_changed):
		_player.health_changed.connect(_on_health_changed)
	if not _player.mana_changed.is_connected(_on_mana_changed):
		_player.mana_changed.connect(_on_mana_changed)


func _get_base_value(key: String) -> float:
	match key:
		"max_health": return float(_player.stats.max_health)
		"max_mana": return float(_player.stats.max_mana)
		"attack": return float(_player.stats.attack)
		"defense": return float(_player.stats.defense)
		"crit_rate": return _player.stats.crit_rate
		"dodge_rate": return _player.stats.dodge_rate
		"hp_regen": return float(_player.stats.hp_regen)
		"mp_regen": return float(_player.stats.mp_regen)
		"magic_resist": return _player.stats.magic_resist
		_: return 0.0


func _get_effective_value(key: String) -> float:
	match key:
		"max_health": return float(_player.stats.get_effective_max_health())
		"max_mana": return float(_player.stats.get_effective_max_mana())
		"attack": return float(_player.stats.get_effective_attack())
		"defense": return float(_player.stats.get_effective_defense())
		"crit_rate": return _player.stats.get_effective_crit_rate()
		"dodge_rate": return _player.stats.get_effective_dodge_rate()
		"hp_regen": return float(_player.stats.get_effective_hp_regen())
		"mp_regen": return float(_player.stats.get_effective_mp_regen())
		"magic_resist": return _player.stats.get_effective_magic_resist()
		_: return 0.0


func _get_equipment_summary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slot_labels: Dictionary = {
		"weapon": "武器", "armor": "防具",
		"accessory_1": "饰品一", "accessory_2": "饰品二",
	}
	for slot: String in ["weapon", "armor", "accessory_1", "accessory_2"]:
		var equip_id: String = str(_player.equipped.get(slot, ""))
		var entry: Dictionary = _player.equipment_data.get_equipment(equip_id)
		result.append({
			"slot": slot,
			"slot_label": str(slot_labels[slot]),
			"equip_id": equip_id,
			"name": str(entry.get("name", "未装备")),
			"quality": str(entry.get("quality", "common")),
		})
	return result


func _on_equipment_changed(_slot: String, _equip_id: String) -> void:
	refresh()


func _on_role_changed(_role_id: int, _display_name: String) -> void:
	refresh()


func _on_health_changed(_current: int, _maximum: int) -> void:
	refresh()


func _on_mana_changed(_current: int, _maximum: int) -> void:
	refresh()
