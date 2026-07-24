class_name Zmxiyou1WorldPickup
extends Area2D

## Source-timed medicine/equipment drop with modern Godot collision.
## Visuals always come from the project's sprite.png + sprite.json contract.

signal collected(kind: StringName, source_name: StringName, target: Node2D)

enum PickupKind { MEDICINE, EQUIPMENT }

const SOURCE_TICK_RATE := 24.0
const SOURCE_GRAVITY_PX_PER_TICK := 1.5
const SOURCE_INITIAL_FALL_SPEED_PX_PER_TICK := 4.0
const SOURCE_LIFETIME_TICKS := 240
const COLLECT_TWEEN_SECONDS := 0.8
const COLLECT_RISE_PX := 100.0
const WORLD_COLLISION_MASK := 1
const PLAYER_COLLISION_MASK := 2
const DESPAWN_Y := 1500.0
const ATLAS_ROOT := "res://assets/selected/zmxiyou1/monsters/shared/pickups"
const MEDICINE_POWER := {
	&"small_hp": 100,
	&"big_hp": 200,
	&"small_mp": 100,
}
const SOURCE_PERSISTENT_EQUIPMENT := [
	&"dslj", &"dsyj", &"dsqz", &"tsgl", &"tsyp", &"tsyj", &"xhyk",
	&"xhxh", &"xhmj", &"qxsh", &"jhcz", &"ryjgb", &"zljs", &"dszk",
	&"bhz", &"qld", &"xwj", &"qlp", &"zqj", &"jcsz", &"jcbj", &"jcys",
]

static var _visual_cache: Dictionary = {}

var pickup_kind := PickupKind.MEDICINE
var source_name: StringName = &"small_hp"
var persistent := false

var _source_tick_accumulator := 0.0
var _source_age_ticks := 0
var _vertical_speed_px_per_tick := SOURCE_INITIAL_FALL_SPEED_PX_PER_TICK
var _collected := false
var _grounded := false
var _sprite: AnimatedSprite2D
var _pickup_shape: CollisionShape2D


func setup_medicine(kind: StringName) -> bool:
	if not MEDICINE_POWER.has(kind):
		push_error("Unknown ZMX1 medicine pickup: %s" % kind)
		return false
	pickup_kind = PickupKind.MEDICINE
	source_name = kind
	persistent = false
	return true


func setup_equipment(equipment_source_name: StringName, force_persistent := false) -> bool:
	if equipment_source_name == &"":
		return false
	pickup_kind = PickupKind.EQUIPMENT
	source_name = equipment_source_name
	persistent = force_persistent or equipment_source_name in SOURCE_PERSISTENT_EQUIPMENT
	return true


func _ready() -> void:
	add_to_group(&"zmxiyou1_world_pickups")
	collision_layer = 0
	collision_mask = PLAYER_COLLISION_MASK
	monitoring = true
	monitorable = false
	_build_visual_and_shape()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_source_tick_accumulator += delta
	while _source_tick_accumulator >= 1.0 / SOURCE_TICK_RATE:
		_source_tick_accumulator -= 1.0 / SOURCE_TICK_RATE
		source_tick()


func source_tick() -> void:
	if _collected or is_queued_for_deletion():
		return
	_apply_source_fall_tick()
	_source_age_ticks += 1
	# ActionScript uses `if (tcount++ >= 240)`, so a non-persistent pickup
	# remains present for 240 full ticks and is removed on the 241st.
	if not persistent and _source_age_ticks > SOURCE_LIFETIME_TICKS:
		queue_free()
	elif global_position.y >= DESPAWN_Y:
		queue_free()


func try_collect(target: Node2D) -> bool:
	if _collected or target == null or not is_instance_valid(target):
		return false
	var applied := false
	if pickup_kind == PickupKind.MEDICINE:
		var power := int(MEDICINE_POWER.get(source_name, 0))
		if source_name == &"small_mp":
			if target.has_method(&"restore_mana"):
				target.call(&"restore_mana", power)
				applied = true
		elif target.has_method(&"heal"):
			target.call(&"heal", power)
			applied = true
	else:
		if target.has_method(&"try_collect_source_equipment"):
			applied = bool(target.call(&"try_collect_source_equipment", source_name))
	if not applied:
		return false
	_begin_collect_tween(target)
	return true


func get_source_age_ticks() -> int:
	return _source_age_ticks


func get_source_vertical_speed_px_per_tick() -> float:
	return _vertical_speed_px_per_tick


func is_source_persistent() -> bool:
	return persistent


func has_been_collected() -> bool:
	return _collected


func get_source_frame_count() -> int:
	if _sprite == null or _sprite.sprite_frames == null:
		return 0
	return _sprite.sprite_frames.get_frame_count(&"pickup")


func get_visual_size() -> Vector2:
	if _pickup_shape == null or _pickup_shape.shape == null:
		return Vector2.ZERO
	if _pickup_shape.shape is RectangleShape2D:
		return (_pickup_shape.shape as RectangleShape2D).size
	return Vector2.ZERO


func _build_visual_and_shape() -> void:
	var cache_key := "%d:%s" % [pickup_kind, source_name]
	var visual: Dictionary = _visual_cache.get(cache_key, {})
	if visual.is_empty():
		visual = _load_visual()
		if not visual.is_empty():
			_visual_cache[cache_key] = visual
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "AnimatedSprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 7
	_sprite.sprite_frames = visual.get("frames") as SpriteFrames
	add_child(_sprite)
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"pickup"):
		_sprite.play(&"pickup")

	var bounds: Rect2 = visual.get("bounds", Rect2(Vector2(-8.0, -8.0), Vector2(16.0, 16.0)))
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(maxf(8.0, bounds.size.x), maxf(8.0, bounds.size.y))
	_pickup_shape = CollisionShape2D.new()
	_pickup_shape.name = "CollisionShape2D"
	_pickup_shape.position = bounds.get_center()
	_pickup_shape.shape = rectangle
	add_child(_pickup_shape)


func _load_visual() -> Dictionary:
	var relative := (
		"medicine/%s" % source_name
		if pickup_kind == PickupKind.MEDICINE
		else "equipment/%s" % source_name
	)
	var sheet_path := "%s/%s/sprite.png" % [ATLAS_ROOT, relative]
	var json_path := "%s/%s/sprite.json" % [ATLAS_ROOT, relative]
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var count := SpriteSheetAtlas.append_animation(
		frames, &"pickup", sheet_path, json_path, SOURCE_TICK_RATE, false
	)
	if count <= 0:
		return {}
	var bounds_list := SpriteSheetAtlas.build_visible_bounds(sheet_path, json_path)
	var bounds := bounds_list[0] if not bounds_list.is_empty() else Rect2(Vector2(-8.0, -8.0), Vector2(16.0, 16.0))
	return {"frames": frames, "bounds": bounds}


func _apply_source_fall_tick() -> void:
	if _grounded:
		return
	var motion := Vector2(0.0, _vertical_speed_px_per_tick)
	var safe_fraction := _cast_world_motion(motion)
	global_position += motion * safe_fraction
	if safe_fraction < 1.0 and motion.y >= 0.0:
		_grounded = true
		_vertical_speed_px_per_tick = 0.0
	else:
		_vertical_speed_px_per_tick += SOURCE_GRAVITY_PX_PER_TICK


func _cast_world_motion(motion: Vector2) -> float:
	if _pickup_shape == null or _pickup_shape.shape == null or get_world_2d() == null:
		return 1.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _pickup_shape.shape
	query.transform = Transform2D(global_rotation, global_position + _pickup_shape.position.rotated(global_rotation))
	query.motion = motion
	query.collision_mask = WORLD_COLLISION_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var fractions := get_world_2d().direct_space_state.cast_motion(query)
	return clampf(float(fractions[0]), 0.0, 1.0) if fractions.size() >= 1 else 1.0


func _on_body_entered(body: Node2D) -> void:
	try_collect(body)


func _begin_collect_tween(target: Node2D) -> void:
	_collected = true
	set_deferred(&"monitoring", false)
	if _pickup_shape != null:
		_pickup_shape.set_deferred(&"disabled", true)
	collected.emit(&"medicine" if pickup_kind == PickupKind.MEDICINE else &"equipment", source_name, target)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position:y", global_position.y - COLLECT_RISE_PX, COLLECT_TWEEN_SECONDS)
	tween.tween_property(self, "modulate:a", 0.0, COLLECT_TWEEN_SECONDS)
	tween.chain().tween_callback(queue_free)
