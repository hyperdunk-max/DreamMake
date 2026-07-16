class_name ShasengSkillState
extends RoleSkillState

const ZHANG_QI := &"zhang_qi"
const WUDU_WAWA := &"wudu_wawa"
const MABI_YAOJI := &"mabi_yaoji"
const JUDU_ZHEN := &"judu_zhen"
const MENGDU_SU := &"mengdu_su"
const QIANGLI_JI := &"qiangli_ji"
const TENGKONG_JI := &"tengkong_ji"
const DUOZHONG_JI := &"duozhong_ji"
const LVYE_BIAOJI := &"lvye_biaoji"
const MUMO_WU := &"mumo_wu"

var _arrow_mode := false
var _poison_states: Dictionary = {}
var _marker_effect: OneShotSpriteEffect
var _marker_actor_position := Vector2.ZERO
var _marker_teleport_phase := false
var _doll: ShasengVoodooDoll
var _doll_effect: OneShotSpriteEffect


func enter(payload: Dictionary = {}) -> void:
	_arrow_mode = actor.animation_profile.get_weapon_mode(actor.weapon_showid) == &"arrow"
	_marker_teleport_phase = false
	var slot := int(payload.get("slot", -1))
	var selected := profile.get_skill(slot)
	if (
		StringName(selected.get("id", &"")) == LVYE_BIAOJI
		and _marker_effect != null and is_instance_valid(_marker_effect)
	):
		_marker_teleport_phase = true
		current_skill = selected
		_elapsed_ticks = 0
		_tick_accumulator = 0.0
		actor.spend_mana(int(current_skill.get("mana_cost", 0)))
		actor.on_role_skill_started(current_skill)
		actor.global_position = _marker_actor_position
		return
	super.enter(payload)


func process_persistent(delta: float) -> void:
	for raw_target in _poison_states.keys():
		var target := raw_target as Object
		if target == null or not is_instance_valid(target) or int(target.get("health")) <= 0:
			_poison_states.erase(raw_target)
			continue
		var state: Dictionary = _poison_states[raw_target]
		state["seconds_left"] = float(state.get("seconds_left", 0.0)) - delta
		state["tick_accumulator"] = float(state.get("tick_accumulator", 0.0)) + delta
		while float(state["tick_accumulator"]) >= 1.0 and float(state["seconds_left"]) > 0.0:
			state["tick_accumulator"] = float(state["tick_accumulator"]) - 1.0
			var poison_damage := int(state.get("poison_damage", 0))
			if poison_damage > 0:
				actor.apply_role_skill_hit(target, poison_damage, Vector2.ZERO)
		if float(state["seconds_left"]) <= 0.0:
			_poison_states.erase(raw_target)
		else:
			_poison_states[raw_target] = state


func dispose() -> void:
	_destroy_effect(_marker_effect)
	_destroy_effect(_doll_effect)
	if _doll != null and is_instance_valid(_doll):
		_doll.queue_free()
	_marker_effect = null
	_doll_effect = null
	_doll = null
	_poison_states.clear()


func skill_tick() -> void:
	match get_current_skill_id():
		ZHANG_QI:
			_tick_zhang_qi()
		WUDU_WAWA:
			_tick_wudu_wawa()
		MABI_YAOJI:
			_tick_mabi_yaoji()
		JUDU_ZHEN:
			_tick_judu_zhen()
		MENGDU_SU:
			_tick_mengdu_su()
		QIANGLI_JI:
			_tick_qiangli_ji()
		TENGKONG_JI:
			_tick_tengkong_ji()
		DUOZHONG_JI:
			_tick_duozhong_ji()
		LVYE_BIAOJI:
			_tick_luye_biaoji()
		MUMO_WU:
			_tick_mumo_wu()
		_:
			super.skill_tick()


func get_horizontal_velocity(facing: float) -> float:
	match get_current_skill_id():
		QIANGLI_JI:
			if _arrow_mode and _elapsed_ticks <= 2:
				return -600.0 * facing
		DUOZHONG_JI:
			if not _arrow_mode and _elapsed_ticks <= 4:
				return 480.0 * facing
		MUMO_WU:
			if _arrow_mode:
				if _elapsed_ticks >= 21 and _elapsed_ticks <= 24:
					return 600.0 * facing
				if _elapsed_ticks == 25:
					return -600.0 * facing
	return 0.0


func blocks_gravity() -> bool:
	return _arrow_mode and get_current_skill_id() in [QIANGLI_JI, MUMO_WU] or get_current_skill_id() == TENGKONG_JI


func get_vertical_velocity() -> float:
	match get_current_skill_id():
		QIANGLI_JI:
			return -600.0 if _arrow_mode and _elapsed_ticks <= 2 else 0.0
		TENGKONG_JI:
			if _arrow_mode:
				return -840.0 if _elapsed_ticks <= 4 else 0.0
			return -240.0 if _elapsed_ticks >= 5 else 0.0
		MUMO_WU:
			return -840.0 if _arrow_mode and _elapsed_ticks <= 5 else 0.0
	return 0.0


func get_poison_stacks(target: Object) -> int:
	if target == null or not _poison_states.has(target):
		return 0
	return int((_poison_states[target] as Dictionary).get("stacks", 0))


func _tick_zhang_qi() -> void:
	var effect_tick := int(current_skill.get("arrow_effect_tick", 7) if _arrow_mode else current_skill.get("shovel_effect_tick", 3))
	if _elapsed_ticks == effect_tick:
		var effect_id := &"arrow" if _arrow_mode else &"shovel"
		var delta := Vector2(30, 0) if _arrow_mode else Vector2(245, -110)
		var damage := int(current_skill.get("arrow_damage", 24) if _arrow_mode else current_skill.get("shovel_damage", 6))
		var repeat_count := 1 if _arrow_mode else int(current_skill.get("shovel_repeat_count", 2))
		_spawn_poison_area(effect_id, delta, damage, repeat_count)
	_finish_at_mode_duration()


func _tick_wudu_wawa() -> void:
	var cast_tick := int(current_skill.get("arrow_cast_tick", 1) if _arrow_mode else current_skill.get("shovel_cast_tick", 3))
	var bind_tick := int(current_skill.get("arrow_bind_tick", 7) if _arrow_mode else current_skill.get("shovel_bind_tick", 8))
	if _elapsed_ticks == cast_tick:
		actor.spawn_role_skill_effect(get_effect(&"cast"), actor.flash_actor_point(Vector2(115, -110)), true)
	if _elapsed_ticks == bind_tick:
		_create_voodoo_doll()
	_finish_at_mode_duration()


func _tick_mabi_yaoji() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 1)):
		_launch_paralysis_chain()
	_finish_at_mode_duration()


func _tick_judu_zhen() -> void:
	if _elapsed_ticks == int(current_skill.get("array_tick", 15)):
		actor.spawn_role_skill_effect(get_effect(&"array"), actor.flash_actor_point(Vector2(155, -50)))
	if _elapsed_ticks == int(current_skill.get("burst_tick", 27)):
		var burst_spec: Dictionary = get_effect(&"burst")
		for local_delta in [Vector2(150, -70), Vector2(190, -90), Vector2(110, -80)]:
			var origin: Vector2 = actor.flash_actor_point(Vector2(local_delta))
			actor.spawn_role_skill_effect(burst_spec, origin)
			var center: Vector2 = actor.role_skill_effect_bounds_center(burst_spec, origin)
			for target in actor.find_role_skill_targets_at(Vector2(87, 134), center):
				actor.apply_role_skill_hit(target, int(current_skill.get("damage", 10)), Vector2(0, -48))
				_add_poison(target, 1, 4.0, int(current_skill.get("poison_damage", 10)))
	_finish_at_mode_duration()


func _tick_mengdu_su() -> void:
	if _elapsed_ticks == 1:
		var candidates: Array = actor.find_role_skill_targets_at(Vector2(1880, 900), actor.global_position + Vector2(0, -200))
		for target in candidates:
			var stacks := mini(int(current_skill.get("stack_cap", 6)), get_poison_stacks(target))
			if stacks <= 0:
				continue
			var damage := int(floor(stacks * stacks * float(current_skill.get("damage_per_stack_squared", 5.0))))
			var blast_origin: Vector2 = actor.flash_target_point(target as Node2D)
			var blast_effect: OneShotSpriteEffect = actor.spawn_role_skill_effect(get_effect(&"blast"), blast_origin)
			if blast_effect != null:
				blast_effect.set_follow_target(target as Node2D, blast_origin - (target as Node2D).global_position)
			actor.apply_role_skill_hit(target, damage, Vector2.ZERO)
			_poison_states.erase(target)
	finish_skill()


func _tick_qiangli_ji() -> void:
	var effect_tick := int(current_skill.get("arrow_effect_tick", 1) if _arrow_mode else current_skill.get("shovel_effect_tick", 5))
	if _elapsed_ticks == effect_tick:
		if _arrow_mode:
			actor.spawn_role_skill_effect(get_effect(&"arrow_charge"), actor.flash_actor_point(Vector2(75, -60)), true)
			_spawn_plain_area(&"arrow_impact", Vector2(65, -10), int(current_skill.get("damage", 40)), Vector2(720, -48))
		else:
			_spawn_plain_area(&"shovel", Vector2(125, -30), int(current_skill.get("damage", 40)), Vector2(720, -48), 1, 0.0, true)
	_finish_at_mode_duration()


func _tick_tengkong_ji() -> void:
	if not _arrow_mode:
		if _elapsed_ticks == 1:
			actor.spawn_role_skill_effect(get_effect(&"shovel_charge"), actor.flash_actor_point(Vector2.ZERO), true)
		if _elapsed_ticks == int(current_skill.get("shovel_hit_tick", 8)):
			_spawn_plain_area(&"shovel_impact", Vector2(0, -80), int(current_skill.get("shovel_damage", 80)), Vector2(360, -600), 1, 0.0, true)
	else:
		if _elapsed_ticks == 1:
			actor.spawn_role_skill_effect(get_effect(&"arrow_charge"), actor.flash_actor_point(Vector2(80, -80)), true)
		if _elapsed_ticks == int(current_skill.get("arrow_hit_tick", 3)):
			_spawn_plain_area(&"arrow_impact", Vector2(60, 30), int(current_skill.get("arrow_damage", 20)), Vector2(120, 0), 1, 0.0, true)
	_finish_at_mode_duration()


func _tick_duozhong_ji() -> void:
	if not _arrow_mode and _elapsed_ticks == int(current_skill.get("shovel_effect_tick", 1)):
		var origin: Vector2 = actor.flash_actor_point(Vector2(150, -50))
		var spec: Dictionary = get_effect(&"shovel")
		actor.spawn_role_skill_effect(spec, origin)
		_schedule_plain_area_hits(
			actor.role_skill_effect_bounds_center(spec, origin), Vector2(342, 166),
			int(current_skill.get("shovel_damage", 24)), Vector2(240, -48),
			int(current_skill.get("shovel_repeat_count", 5)), 8.0 / 24.0
		)
	if _arrow_mode:
		if _elapsed_ticks == 1:
			actor.spawn_role_skill_effect(get_effect(&"arrow_charge"), actor.flash_actor_point(Vector2.ZERO), true)
		if _elapsed_ticks == int(current_skill.get("arrow_effect_tick", 13)):
			_spawn_plain_area(&"arrow_impact", Vector2(225, -80), int(current_skill.get("arrow_damage", 80)), Vector2(240, -48))
	_finish_at_mode_duration()


func _tick_luye_biaoji() -> void:
	if _marker_teleport_phase:
		if _elapsed_ticks == 1:
			finish_skill()
		return
	if _elapsed_ticks == int(current_skill.get("mark_tick", 1)):
		_marker_actor_position = actor.global_position
		_marker_effect = actor.spawn_role_skill_effect(get_effect(&"mark"), actor.flash_actor_point(Vector2.ZERO))
	_finish_at_mode_duration()


func _tick_mumo_wu() -> void:
	if not _arrow_mode:
		if _elapsed_ticks == int(current_skill.get("shovel_effect_tick", 5)):
			var origin: Vector2 = actor.flash_actor_point(Vector2(150, 0))
			var spec: Dictionary = get_effect(&"shovel")
			actor.spawn_role_skill_effect(spec, origin)
			_schedule_plain_area_hits(
				actor.role_skill_effect_bounds_center(spec, origin), Vector2(798, 63),
				int(current_skill.get("shovel_damage", 60)), Vector2(120, -48),
				int(current_skill.get("shovel_repeat_count", 12)), 20.0 / 24.0
			)
	else:
		if _elapsed_ticks == 25:
			actor.facing *= -1.0
		if _elapsed_ticks in [1, 25]:
			actor.spawn_role_skill_effect(get_effect(&"arrow_aura"), actor.flash_actor_point(Vector2(80, -100)), true)
			_spawn_following_area(&"arrow_body", Vector2.ZERO, int(current_skill.get("arrow_damage", 40)), Vector2(120, -48), 2, 10.0 / 24.0)
		var leaf_counts := {4: 17, 9: 12, 15: 6, 34: 17, 39: 12, 45: 6}
		if leaf_counts.has(_elapsed_ticks):
			var remaining := int(leaf_counts[_elapsed_ticks])
			_spawn_plain_area(
				&"arrow_leaf", Vector2(88 + remaining, 7 - remaining * 2),
				int(current_skill.get("arrow_damage", 40)), Vector2(120, -48)
			)
	_finish_at_mode_duration()


func _spawn_poison_area(effect_id: StringName, source_delta: Vector2, damage: int, repeat_count: int) -> void:
	var spec: Dictionary = get_effect(effect_id)
	var origin: Vector2 = actor.flash_actor_point(source_delta)
	actor.spawn_role_skill_effect(spec, origin, not _arrow_mode)
	var center: Vector2 = actor.role_skill_effect_bounds_center(spec, origin)
	if _arrow_mode:
		_schedule_poison_hits(
			center, Vector2(571, 60), damage,
			int(current_skill.get("poison_damage", 10)), repeat_count, 12.0 / 24.0
		)
	else:
		_schedule_following_poison_hits(
			center - actor.global_position, Vector2(216, 153), damage,
			int(current_skill.get("poison_damage", 10)), repeat_count, 12.0 / 24.0
		)


func _schedule_poison_hits(
	origin: Vector2, size: Vector2, damage: int, poison_damage: int,
	repeat_count: int, interval: float
) -> void:
	for repeat_index in range(repeat_count):
		if repeat_index > 0:
			await actor.get_tree().create_timer(interval).timeout
		for target in actor.find_role_skill_targets_at(size, origin):
			actor.apply_role_skill_hit(target, damage, Vector2(120, -72))
			_add_poison(target, 1, 8.0, poison_damage)


func _schedule_following_poison_hits(
	follow_offset: Vector2, size: Vector2, damage: int, poison_damage: int,
	repeat_count: int, interval: float
) -> void:
	for repeat_index in range(repeat_count):
		if repeat_index > 0:
			await actor.get_tree().create_timer(interval).timeout
		for target in actor.find_role_skill_targets_at(size, actor.global_position + follow_offset):
			actor.apply_role_skill_hit(target, damage, Vector2(120, -72))
			_add_poison(target, 1, 8.0, poison_damage)


func _launch_paralysis_chain() -> void:
	var chain_range := float(current_skill.get("chain_range", 500.0))
	var travel_speed := float(current_skill.get("travel_speed", 416.666667))
	var stack_seconds := float(current_skill.get("poison_stack_seconds", 7.0))
	var stun_seconds := float(current_skill.get("stun_seconds", 0.5))
	var max_jumps := int(current_skill.get("max_jumps", 8))
	var target := _find_chain_target(actor.global_position, [], true, chain_range)
	if target == null:
		return
	var effect: OneShotSpriteEffect = actor.spawn_role_skill_effect(get_effect(&"orb"), actor.flash_actor_point(Vector2(25, -30)))
	if effect == null:
		return
	var visited: Array = []
	while target != null and visited.size() < max_jumps and is_instance_valid(effect):
		visited.append(target)
		var destination: Vector2 = actor.flash_target_point(target as Node2D)
		var travel_seconds: float = effect.global_position.distance_to(destination) / travel_speed
		var tween: Tween = actor.get_tree().create_tween()
		tween.tween_property(effect, "global_position", destination, travel_seconds)
		await tween.finished
		if target == null or not is_instance_valid(target):
			break
		_add_poison(target, 1, stack_seconds, 0)
		if target.has_method("apply_stun"):
			target.apply_stun(stun_seconds)
		target = _find_chain_target(effect.global_position, visited, false, chain_range)
	if is_instance_valid(effect):
		effect.queue_free()


func _find_chain_target(origin: Vector2, visited: Array, forward_only: bool, chain_range: float) -> Object:
	var candidates: Array = actor.find_role_skill_targets_at(Vector2(1000, 1000), origin)
	var nearest: Object
	var nearest_distance := INF
	for candidate in candidates:
		if visited.has(candidate):
			continue
		var distance: float = (candidate.global_position - origin).length()
		if distance > chain_range:
			continue
		if forward_only and (candidate.global_position.x - actor.global_position.x) * actor.facing < 0.0:
			continue
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _create_voodoo_doll() -> void:
	var target := actor.find_nearest_role_skill_target() as Node2D
	if target == null:
		return
	if _doll != null and is_instance_valid(_doll):
		_doll.queue_free()
	_destroy_effect(_doll_effect)
	_doll = ShasengVoodooDoll.new()
	actor.get_tree().current_scene.add_child(_doll)
	_doll.global_position = actor.flash_actor_point(Vector2(0, -20))
	_doll.configure(target, actor, float(current_skill.get("doll_seconds", 10.0)))
	_doll_effect = actor.spawn_role_skill_effect(get_effect(&"doll"), _doll.global_position)
	if _doll_effect != null:
		_doll_effect.set_follow_target(_doll, Vector2.ZERO)


func _add_poison(target: Object, stacks: int, seconds: float, poison_damage: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var state: Dictionary = _poison_states.get(target, {
		"stacks": 0, "seconds_left": 0.0, "tick_accumulator": 0.0, "poison_damage": 0,
	})
	state["stacks"] = int(state.get("stacks", 0)) + stacks
	state["seconds_left"] = seconds
	state["poison_damage"] = maxi(int(state.get("poison_damage", 0)), poison_damage)
	_poison_states[target] = state


func _spawn_plain_area(
	effect_id: StringName, source_delta: Vector2, damage: int, knockback: Vector2,
	repeat_count := 1, interval := 0.0, follow_actor := false
) -> void:
	var spec: Dictionary = get_effect(effect_id)
	var origin: Vector2 = actor.flash_actor_point(source_delta)
	actor.spawn_role_skill_effect(spec, origin, follow_actor)
	var size := Vector2(spec.get("hitbox_size", spec.get("effect_output_size", Vector2(96, 96))))
	_schedule_plain_area_hits(actor.role_skill_effect_bounds_center(spec, origin), size, damage, knockback, repeat_count, interval)


func _spawn_following_area(
	effect_id: StringName, source_delta: Vector2, damage: int, knockback: Vector2,
	repeat_count: int, interval: float
) -> void:
	var spec: Dictionary = get_effect(effect_id)
	var origin: Vector2 = actor.flash_actor_point(source_delta)
	actor.spawn_role_skill_effect(spec, origin, true)
	var size := Vector2(spec.get("hitbox_size", spec.get("effect_output_size", Vector2(96, 96))))
	var center: Vector2 = actor.role_skill_effect_bounds_center(spec, origin)
	actor.schedule_following_role_skill_box_hits(
		center - actor.global_position, size, damage, knockback, repeat_count, interval
	)


func _schedule_plain_area_hits(
	origin: Vector2, size: Vector2, damage: int, knockback: Vector2,
	repeat_count: int, interval: float
) -> void:
	for repeat_index in range(repeat_count):
		if repeat_index > 0:
			await actor.get_tree().create_timer(interval).timeout
		for target in actor.find_role_skill_targets_at(size, origin):
			actor.apply_role_skill_hit(target, damage, knockback)


func _finish_at_mode_duration() -> void:
	var duration := int(current_skill.get("arrow_duration_ticks", 1) if _arrow_mode else current_skill.get("shovel_duration_ticks", 1))
	if _elapsed_ticks >= duration:
		finish_skill()


func _destroy_effect(effect: Node) -> void:
	if effect != null and is_instance_valid(effect):
		effect.queue_free()
