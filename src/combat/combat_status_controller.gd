class_name CombatStatusController
extends Node

## Source-tick status component shared by combat actors.
## Visuals are loaded directly from the selected sprite-pack atlases.

const SOURCE_TICK_RATE := 24.0
const ATLAS := preload("res://src/animation/sprite_sheet_atlas.gd")
const VISUALS := {
	&"poison_up": {
		"sheet": "res://assets/selected/zmxiyou1/monsters/shared/effects/poisonUp/sprite.png",
		"json": "res://assets/selected/zmxiyou1/monsters/shared/effects/poisonUp/sprite.json",
		"offset": Vector2(0, -50),
		"loop": false,
	},
	&"poison": {
		"sheet": "res://assets/selected/zmxiyou1/monsters/shared/effects/poisonHead/sprite.png",
		"json": "res://assets/selected/zmxiyou1/monsters/shared/effects/poisonHead/sprite.json",
		"offset": Vector2(0, -70),
		"loop": true,
	},
	&"ice": {
		"sheet": "res://assets/selected/zmxiyou1/monsters/m26_dragon/effects/ice/sprite.png",
		"json": "res://assets/selected/zmxiyou1/monsters/m26_dragon/effects/ice/sprite.json",
		"offset": Vector2(-90, -115),
		"loop": true,
	},
}

static var _frames_cache: Dictionary = {}

var _actor: Node2D
var _statuses: Dictionary = {}
var _visual_nodes: Dictionary = {}
var _tick_accumulator := 0.0


func setup(actor: Node2D) -> void:
	_actor = actor


func apply_status(spec: Dictionary, source: Object = null) -> bool:
	if _actor == null:
		return false
	var status_id := StringName(spec.get("id", &""))
	if status_id not in [&"poison", &"ice"]:
		return false
	var duration_ticks := maxi(1, int(spec.get("duration_ticks", 1)))
	var state: Dictionary = _statuses.get(status_id, {})
	state["remaining_ticks"] = duration_ticks
	state["power"] = maxi(0, int(spec.get("power", 0)))
	state["source"] = weakref(source) if source != null else null
	if status_id == &"poison":
		state["ticks_until_damage"] = mini(24, int(state.get("ticks_until_damage", 24)))
		_spawn_application_visual(&"poison_up")
		_ensure_persistent_visual(&"poison")
	else:
		_ensure_persistent_visual(&"ice")
		if _actor.has_method(&"set_external_control_locked"):
			_actor.call(&"set_external_control_locked", self, true)
		_actor.velocity = Vector2.ZERO
	_statuses[status_id] = state
	return true


func has_status(status_id: StringName) -> bool:
	return _statuses.has(status_id)


func get_remaining_ticks(status_id: StringName) -> int:
	return int((_statuses.get(status_id, {}) as Dictionary).get("remaining_ticks", 0))


func _physics_process(delta: float) -> void:
	_tick_accumulator += delta
	while _tick_accumulator >= 1.0 / SOURCE_TICK_RATE:
		_tick_accumulator -= 1.0 / SOURCE_TICK_RATE
		_advance_source_tick()


func _advance_source_tick() -> void:
	for raw_id: Variant in _statuses.keys():
		var status_id := StringName(raw_id)
		var state: Dictionary = _statuses[raw_id]
		state["remaining_ticks"] = int(state.get("remaining_ticks", 0)) - 1
		if status_id == &"poison":
			state["ticks_until_damage"] = int(state.get("ticks_until_damage", 24)) - 1
			if int(state["ticks_until_damage"]) <= 0:
				state["ticks_until_damage"] = 24
				_apply_poison_damage(state)
		if int(state["remaining_ticks"]) <= 0:
			_remove_status(status_id)
		else:
			_statuses[status_id] = state


func _apply_poison_damage(state: Dictionary) -> void:
	var power := int(state.get("power", 0))
	if power <= 0 or _actor == null:
		return
	var source: Object
	var source_ref: Variant = state.get("source")
	if source_ref is WeakRef:
		source = (source_ref as WeakRef).get_ref()
	if _actor.has_method(&"apply_status_damage"):
		_actor.call(&"apply_status_damage", power, &"poison", source)
	elif _actor.has_method(&"take_hit"):
		_actor.call(&"take_hit", power, Vector2.ZERO, &"magic", source)


func _remove_status(status_id: StringName) -> void:
	_statuses.erase(status_id)
	var visual := _visual_nodes.get(status_id) as AnimatedSprite2D
	if visual != null and is_instance_valid(visual):
		visual.queue_free()
	_visual_nodes.erase(status_id)
	if status_id == &"ice" and _actor != null and _actor.has_method(&"set_external_control_locked"):
		_actor.call(&"set_external_control_locked", self, false)


func _spawn_application_visual(visual_id: StringName) -> void:
	var visual := _make_visual(visual_id)
	if visual == null:
		return
	visual.animation_finished.connect(visual.queue_free, CONNECT_ONE_SHOT)


func _ensure_persistent_visual(visual_id: StringName) -> void:
	var existing := _visual_nodes.get(visual_id) as AnimatedSprite2D
	if existing != null and is_instance_valid(existing):
		return
	var visual := _make_visual(visual_id)
	if visual != null:
		_visual_nodes[visual_id] = visual


func _make_visual(visual_id: StringName) -> AnimatedSprite2D:
	if _actor == null or not VISUALS.has(visual_id):
		return null
	var config: Dictionary = VISUALS[visual_id]
	var frames := _get_visual_frames(visual_id, config)
	if frames == null:
		return null
	var visual := AnimatedSprite2D.new()
	visual.name = "CombatStatus_%s" % visual_id
	visual.sprite_frames = frames
	visual.position = Vector2(config["offset"])
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.z_index = 10
	_actor.add_child(visual)
	visual.play(visual_id)
	return visual


func _get_visual_frames(visual_id: StringName, config: Dictionary) -> SpriteFrames:
	if _frames_cache.has(visual_id):
		return _frames_cache[visual_id] as SpriteFrames
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	if ATLAS.append_animation(
		frames,
		visual_id,
		str(config["sheet"]),
		str(config["json"]),
		SOURCE_TICK_RATE,
		bool(config["loop"])
	) <= 0:
		return null
	_frames_cache[visual_id] = frames
	return frames


func _exit_tree() -> void:
	for raw_id: Variant in _statuses.keys():
		_remove_status(StringName(raw_id))
