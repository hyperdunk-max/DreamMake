class_name TangsengSkillState
extends RoleSkillState

const SHENGGUANG_QIU := &"shengguang_qiu"
const MUYU_HUICHUN := &"muyu_huichun"
const JINGU_ZHOU := &"jingu_zhou"
const TIANJIANG_GANLU := &"tianjiang_ganlu"
const JIUHUAN_SHENGJING := &"jiuhuan_shengjing"
const XUANBING_ZHEN := &"xuanbing_zhen"
const SHUIHUANYING := &"shuihuanying"
const SHUIMO_BAO := &"shuimo_bao"
const BINGLONG_BO := &"binglong_bo"

var _charge_released := false
var _charge_release_tick := 0
var _charge_qualified := false
var _next_attack_multiplier := 1.0
var _shadow_effect: OneShotSpriteEffect
var _shadow_actor_position := Vector2.ZERO
var _active_shadow_origin := Vector2.ZERO
var _has_active_shadow_origin := false
var _shuimo_marker: OneShotSpriteEffect
var _shuimo_blast_phase := false
var _hit_targets: Dictionary = {}


func request_skill(slot: int) -> bool:
	var skill := profile.get_skill(slot) if profile != null else {}
	if (
		StringName(skill.get("id", &"")) == SHUIMO_BAO
		and _shuimo_marker != null and is_instance_valid(_shuimo_marker)
		and not state_machine.has_active_state()
	):
		return state_machine.transition_to(ID, {"slot": slot, "shuimo_blast": true})
	return super.request_skill(slot)


func request_charged_normal_attack() -> bool:
	if profile == null or profile.charged_attack_skill.is_empty():
		return false
	if state_machine.has_active_state() or not actor.is_on_floor():
		return false
	return state_machine.transition_to(ID, {"charged_attack": true})


func enter(payload: Dictionary = {}) -> void:
	_charge_released = false
	_charge_release_tick = 0
	_charge_qualified = false
	_shuimo_blast_phase = bool(payload.get("shuimo_blast", false))
	_hit_targets.clear()
	_has_active_shadow_origin = false
	if bool(payload.get("charged_attack", false)):
		current_skill = profile.charged_attack_skill
		_elapsed_ticks = 0
		_tick_accumulator = 0.0
		actor.on_role_skill_started(current_skill)
		animator.play_action(StringName(current_skill["action"]), true)
		return
	if _shuimo_blast_phase:
		current_skill = profile.get_skill(int(payload.get("slot", -1)))
		_elapsed_ticks = 0
		_tick_accumulator = 0.0
		actor.on_role_skill_started(current_skill)
		animator.play_action(StringName(current_skill["reactivate_action"]), true)
		return
	super.enter(payload)
	_capture_shadow_cast_origin()


func dispose() -> void:
	_destroy_effect(_shadow_effect)
	_destroy_effect(_shuimo_marker)
	_shadow_effect = null
	_shuimo_marker = null


func release_normal_attack() -> bool:
	if get_current_skill_id() != BINGLONG_BO or _charge_released:
		return false
	_charge_released = true
	_charge_release_tick = _elapsed_ticks
	_charge_qualified = (
		_elapsed_ticks >= int(current_skill.get("charge_ticks", 48))
		and actor.can_spend_mana(int(current_skill.get("mana_cost", 20)))
	)
	if _charge_qualified:
		actor.spend_mana(int(current_skill.get("mana_cost", 20)))
	animator.play_action(StringName(current_skill.get("release_action", &"hit1")), true)
	return true


func reactivate_current_skill() -> bool:
	if (
		get_current_skill_id() != SHUIMO_BAO or _shuimo_blast_phase
		or _shuimo_marker == null or not is_instance_valid(_shuimo_marker)
	):
		return false
	_shuimo_blast_phase = true
	_elapsed_ticks = 0
	_tick_accumulator = 0.0
	animator.play_action(StringName(current_skill["reactivate_action"]), true)
	return true


func modify_outgoing_damage(damage: int) -> int:
	if _next_attack_multiplier <= 1.0:
		return damage
	var resolved := int(floor(damage * _next_attack_multiplier))
	_next_attack_multiplier = 1.0
	return resolved


func skill_tick() -> void:
	match get_current_skill_id():
		BINGLONG_BO:
			_tick_binglong_bo()
		SHENGGUANG_QIU:
			_tick_shengguang_qiu()
		MUYU_HUICHUN:
			_tick_muyu_huichun()
		JINGU_ZHOU:
			_tick_jingu_zhou()
		TIANJIANG_GANLU:
			_tick_tianjiang_ganlu()
		JIUHUAN_SHENGJING:
			_tick_jiuhuan_shengjing()
		XUANBING_ZHEN:
			_tick_xuanbing_zhen()
		SHUIHUANYING:
			_tick_shuihuanying()
		SHUIMO_BAO:
			_tick_shuimo_bao()
		_:
			super.skill_tick()


func _tick_binglong_bo() -> void:
	if not _charge_released:
		return
	if _elapsed_ticks <= _charge_release_tick:
		return
	if _charge_qualified:
		var origin: Vector2 = actor.flash_actor_point(Vector2(50, 10))
		var beam_spec := get_effect(&"beam")
		actor.spawn_role_skill_effect(beam_spec, origin)
		var hitbox_origin: Vector2 = actor.role_skill_effect_bounds_center(beam_spec, origin)
		actor.schedule_role_skill_box_hits(
			hitbox_origin,
			Vector2(current_skill.get("hitbox_size", Vector2(1032, 59))),
			int(current_skill.get("damage", 5)),
			Vector2(current_skill.get("knockback", Vector2(240, -24))),
			12, 4.0 / 24.0
		)
	else:
		var normal_step: Dictionary = actor.combo_attack_profile.steps[0]
		actor.perform_combo_hit(normal_step, {})
	finish_skill()


func _tick_shengguang_qiu() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 51)):
		var origin: Vector2 = _actor_or_shadow_point(Vector2(175, -110), false)
		var orb_spec := get_effect(&"orb")
		actor.spawn_role_skill_effect(orb_spec, origin)
		actor.schedule_role_skill_box_hits(
			actor.role_skill_effect_bounds_center(orb_spec, origin),
			Vector2(current_skill.get("hitbox_size", Vector2(200, 200))),
			int(current_skill.get("damage", 40)),
			Vector2(current_skill.get("knockback", Vector2(360, -48))),
			int(current_skill.get("repeat_count", 4)),
			float(current_skill.get("hit_interval_seconds", 2.0))
		)
	_finish_at_duration()


func _tick_muyu_huichun() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 5)):
		_spawn_healing_spring(_actor_or_shadow_point(Vector2(0, -25), false))
		if _has_active_shadow_origin:
			_spawn_healing_spring(_actor_or_shadow_point(Vector2(0, -25), true))
	_finish_at_duration()


func _spawn_healing_spring(origin: Vector2) -> void:
	actor.spawn_role_skill_effect(get_effect(&"spring"), origin)
	actor.schedule_role_skill_healing(
		origin, float(current_skill.get("heal_radius", 100.0)),
		int(current_skill.get("heal_per_tick", 5)),
		int(current_skill.get("heal_repeat_count", 10)),
		float(current_skill.get("heal_interval", 1.0)),
		float(current_skill.get("heal_initial_delay", 0.9))
	)


func _tick_jingu_zhou() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 5)):
		var origin: Vector2 = actor.flash_actor_point(Vector2(210, 30))
		actor.spawn_role_skill_effect(get_effect(&"ring"), origin)
		var destination: Vector2 = actor.flash_actor_point(Vector2(200, -100))
		for target in actor.find_role_skill_targets_at(Vector2(480, 480), origin):
			actor.move_role_skill_target(target as Node2D, destination, 0.625)
		_next_attack_multiplier = float(current_skill.get("next_attack_multiplier", 1.3))
	_finish_at_duration()


func _tick_tianjiang_ganlu() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 1)):
		_spawn_healing_rain(_actor_or_shadow_point(Vector2(-5, -60), false))
		if _has_active_shadow_origin:
			_spawn_healing_rain(_actor_or_shadow_point(Vector2(-5, -60), true))
	_finish_at_duration()


func _spawn_healing_rain(origin: Vector2) -> void:
	actor.spawn_role_skill_effect(get_effect(&"rain"), origin)
	actor.schedule_role_skill_healing(
		origin, float(current_skill.get("heal_radius", 150.0)),
		int(actor.max_health * float(current_skill.get("heal_ratio", 0.3))),
		1, 0.0, float(current_skill.get("heal_delay", 1.2))
	)


func _tick_jiuhuan_shengjing() -> void:
	if _elapsed_ticks == 1:
		_spawn_jiuhuan_aura(_actor_or_shadow_point(Vector2(20, -20), false))
		if _has_active_shadow_origin:
			_spawn_jiuhuan_aura(_actor_or_shadow_point(Vector2(20, -20), true))
	var strike_tick := int(current_skill.get("strike_tick", 11))
	var interval := int(current_skill.get("strike_hit_interval_ticks", 5))
	if _elapsed_ticks == strike_tick:
		actor.spawn_role_skill_effect(
			get_effect(&"strike"), _actor_or_shadow_point(Vector2(150, -150), false)
		)
		if _has_active_shadow_origin:
			actor.spawn_role_skill_effect(
				get_effect(&"strike"), _actor_or_shadow_point(Vector2(150, -150), true)
			)
	if _elapsed_ticks >= strike_tick and (_elapsed_ticks - strike_tick) % interval == 0:
		var strike_spec := get_effect(&"strike")
		var strike_origin := _actor_or_shadow_point(Vector2(150, -150), false)
		_damage_at(actor.role_skill_effect_bounds_center(strike_spec, strike_origin), Vector2(300, 299), 20, Vector2(192, -48))
		if _has_active_shadow_origin:
			var shadow_strike_origin := _actor_or_shadow_point(Vector2(150, -150), true)
			_damage_at(actor.role_skill_effect_bounds_center(strike_spec, shadow_strike_origin), Vector2(300, 299), 20, Vector2(192, -48))
	_finish_at_duration()


func _spawn_jiuhuan_aura(origin: Vector2) -> void:
	var aura_spec := get_effect(&"aura")
	actor.spawn_role_skill_effect(aura_spec, origin)
	_damage_at(actor.role_skill_effect_bounds_center(aura_spec, origin), Vector2(91, 91), int(current_skill.get("damage", 20)), Vector2(0, -48))


func _tick_xuanbing_zhen() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 13)):
		_spawn_xuanbing(_actor_or_shadow_point(Vector2(0, 10), false))
		if _has_active_shadow_origin:
			_spawn_xuanbing(_actor_or_shadow_point(Vector2(0, 10), true))
	_finish_at_duration()


func _spawn_xuanbing(origin: Vector2) -> void:
	var ice_spec := get_effect(&"ice")
	actor.spawn_role_skill_effect(ice_spec, origin)
	_damage_at(
		actor.role_skill_effect_bounds_center(ice_spec, origin),
		Vector2(current_skill.get("hitbox_size", Vector2(404, 125))),
		int(current_skill.get("damage", 20)),
		Vector2(current_skill.get("knockback", Vector2(168, -96)))
	)


func _tick_shuihuanying() -> void:
	if _elapsed_ticks != 1:
		return
	if _shadow_effect != null and is_instance_valid(_shadow_effect):
		actor.global_position = _shadow_actor_position
		_destroy_effect(_shadow_effect)
		_shadow_effect = null
	else:
		_shadow_actor_position = actor.global_position
		_shadow_effect = actor.spawn_role_skill_effect(
			get_effect(&"shadow"), actor.flash_actor_point(Vector2(0, -5))
		)
	finish_skill()


func _tick_shuimo_bao() -> void:
	if not _shuimo_blast_phase:
		if _elapsed_ticks == int(current_skill.get("marker_tick", 2)):
			_shuimo_marker = actor.spawn_role_skill_effect(
				get_effect(&"marker"), actor.flash_actor_point(Vector2(130, 10))
			)
		if _elapsed_ticks >= int(current_skill.get("duration_ticks", 4)):
			finish_skill()
		return
	if _elapsed_ticks == int(current_skill.get("reactivate_hit_tick", 5)):
		if _shuimo_marker != null and is_instance_valid(_shuimo_marker):
			var blast_origin := _shuimo_marker.global_position + Vector2(30 * actor.facing, -320)
			_destroy_effect(_shuimo_marker)
			_shuimo_marker = null
			var blast_spec := get_effect(&"blast")
			actor.spawn_role_skill_effect(blast_spec, blast_origin)
			_damage_at(actor.role_skill_effect_bounds_center(blast_spec, blast_origin), Vector2(266, 431), int(current_skill.get("damage", 208)), Vector2(192, -72))
	if _elapsed_ticks >= int(current_skill.get("reactivate_duration_ticks", 10)):
		finish_skill()


func _capture_shadow_cast_origin() -> void:
	if get_current_skill_id() not in [MUYU_HUICHUN, TIANJIANG_GANLU, JIUHUAN_SHENGJING, XUANBING_ZHEN]:
		return
	if _shadow_effect == null or not is_instance_valid(_shadow_effect):
		return
	_active_shadow_origin = _shadow_actor_position
	_has_active_shadow_origin = true
	_destroy_effect(_shadow_effect)
	_shadow_effect = null


func _actor_or_shadow_point(source_delta: Vector2, use_shadow: bool) -> Vector2:
	if not use_shadow:
		return actor.flash_actor_point(source_delta)
	return actor.flash_actor_point(source_delta) - actor.global_position + _active_shadow_origin


func _damage_at(origin: Vector2, size: Vector2, damage: int, knockback: Vector2) -> void:
	for target in actor.find_role_skill_targets_at(size, origin):
		actor.apply_role_skill_hit(target, damage, knockback)


func _finish_at_duration() -> void:
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 1)):
		finish_skill()


func _destroy_effect(effect: Node) -> void:
	if effect != null and is_instance_valid(effect):
		effect.queue_free()
