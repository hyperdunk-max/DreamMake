class_name WukongSkillState
extends RoleSkillState

const QISHIER_ZHAN := &"qishier_zhan"
const ZHONGZHAN := &"zhongzhan"
const LIEYAN_SHAN := &"lieyan_shan"
const HUOYAN_JINJING := &"huoyan_jinjing"

var _contact_target: Object
var _contact_tick := -1
var _hit_targets: Dictionary = {}


func enter(payload: Dictionary = {}) -> void:
	_contact_target = null
	_contact_tick = -1
	_hit_targets.clear()
	super.enter(payload)


func exit() -> void:
	_contact_target = null
	_contact_tick = -1
	_hit_targets.clear()
	super.exit()


func skill_tick() -> void:
	match get_current_skill_id():
		QISHIER_ZHAN:
			_tick_qishier_zhan()
		ZHONGZHAN:
			_tick_zhongzhan()
		LIEYAN_SHAN:
			_tick_lieyan_shan()
		HUOYAN_JINJING:
			_tick_huoyan_jinjing()
		_:
			super.skill_tick()


func get_horizontal_velocity(facing: float) -> float:
	if get_current_skill_id() == QISHIER_ZHAN and _contact_target != null:
		return 0.0
	return super.get_horizontal_velocity(facing)


func _tick_qishier_zhan() -> void:
	if _contact_target == null:
		var targets: Array = actor.find_role_skill_targets(
			Vector2(current_skill.get("contact_size", Vector2(76, 68))),
			Vector2(current_skill.get("contact_offset", Vector2(38, -34)))
		)
		if not targets.is_empty():
			_contact_target = targets[0]
			_contact_tick = _elapsed_ticks
			actor.set_role_skill_visual_hidden(true)
			actor.spawn_role_skill_effect(get_effect(&"impact"), _contact_target.global_position)
		elif _elapsed_ticks >= int(current_skill.get("duration_ticks", 20)):
			finish_skill()
		return
	var contact_elapsed := _elapsed_ticks - _contact_tick + 1
	var hit_ticks: Array = current_skill.get("contact_hit_ticks", [3, 6, 8, 12, 14])
	if hit_ticks.has(contact_elapsed) and is_instance_valid(_contact_target):
		actor.apply_role_skill_hit(
			_contact_target,
			int(current_skill.get("damage", 4)),
			Vector2(current_skill.get("knockback", Vector2.ZERO))
		)
	if contact_elapsed >= int(current_skill.get("contact_recovery_ticks", 30)):
		finish_skill()


func _tick_zhongzhan() -> void:
	if _elapsed_ticks == int(current_skill.get("charge_tick", 2)):
		actor.spawn_role_skill_effect(
			get_effect(&"charge"),
			actor.global_position + Vector2(0, -85),
			true
		)
	if _elapsed_ticks == int(current_skill.get("hit_tick", 16)):
		var effect_origin: Vector2 = actor.global_position + Vector2(145 * actor.facing, -60)
		actor.spawn_role_skill_effect(get_effect(&"slash"), effect_origin)
		_damage_box(
			Vector2(current_skill.get("hitbox_size", Vector2(194, 123))),
			Vector2(current_skill.get("hitbox_offset", Vector2(100, -60))),
			int(current_skill.get("damage", 90)),
			Vector2(current_skill.get("knockback", Vector2(480, 0)))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 30)):
		finish_skill()


func _tick_lieyan_shan() -> void:
	if _elapsed_ticks == 1:
		actor.set_role_skill_visual_hidden(true)
		actor.spawn_role_skill_effect(get_effect(&"dash"), actor.global_position, true)
	for target in actor.find_role_skill_targets(
		Vector2(current_skill.get("hitbox_size", Vector2(180, 76))),
		Vector2(current_skill.get("hitbox_offset", Vector2(55, -38)))
	):
		if _hit_targets.has(target):
			continue
		_hit_targets[target] = true
		actor.apply_role_skill_hit(
			target,
			int(current_skill.get("damage", 100)),
			Vector2(current_skill.get("knockback", Vector2(0, -48)))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 10)):
		finish_skill()


func _tick_huoyan_jinjing() -> void:
	if _elapsed_ticks == 1:
		actor.spawn_role_skill_effect(
			get_effect(&"cast_eye"), actor.global_position + Vector2(21 * actor.facing, -10), true
		)
		actor.spawn_role_skill_effect(
			get_effect(&"cast_flare"), actor.global_position + Vector2(-60, 0), true
		)
	if _elapsed_ticks >= int(current_skill.get("target_tick", 17)):
		var target: Object = actor.find_nearest_role_skill_target()
		if target != null:
			actor.schedule_role_skill_hits(
				target,
				get_effect(&"explosion"),
				int(current_skill.get("damage", 27)),
				Vector2(current_skill.get("knockback", Vector2.ZERO)),
				int(current_skill.get("repeat_count", 3)),
				float(current_skill.get("repeat_interval", 2.0))
			)
		finish_skill()


func _damage_box(size: Vector2, offset: Vector2, damage: int, knockback: Vector2) -> void:
	for target in actor.find_role_skill_targets(size, offset):
		if _hit_targets.has(target):
			continue
		_hit_targets[target] = true
		actor.apply_role_skill_hit(target, damage, knockback)
