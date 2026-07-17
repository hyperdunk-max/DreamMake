class_name BajieSkillState
extends RoleSkillState

# 技能显示调节说明：
# - Vector2(x, y)：x 正数=面朝方向前方，x 负数=身后；y 负数=上方，y 正数=下方。
# - “跟随”表示角色移动时特效一起移动；未标注跟随的特效生成后使用世界坐标。
# - 搜索“显示调节”可快速定位每个技能；视觉与 hitbox_offset 需要分别调整。

const DUNJI := &"dunji"
const SHENGDUN := &"shengdun"
const ZHANZHENG_NUHOU := &"zhanzheng_nuhou"
const SHENGYU_ZHIQIANG := &"shengyu_zhiqiang"
const SUISHI_PO := &"suishi_po"
const JUSHI_PO := &"jushi_po"
const DIGUN_QIU := &"digun_qiu"
const XUANGUN_QIU := &"xuangun_qiu"
const TUMO_CI := &"tumo_ci"

var _next_attack_multiplier := 1.0
var _shield_seconds_left := 0.0
var _shield_effect: OneShotSpriteEffect
var _active_effect: OneShotSpriteEffect
var _tumo_guard_effect: OneShotSpriteEffect
var _tumo_reactivated := false


func enter(payload: Dictionary = {}) -> void:
	_tumo_reactivated = false
	actor.set_role_skill_visual_hidden(false)
	super.enter(payload)


func exit() -> void:
	var skill_id := get_current_skill_id()
	if skill_id == XUANGUN_QIU or skill_id == TUMO_CI:
		actor.set_role_skill_visual_hidden(false)
	if skill_id == XUANGUN_QIU:
		_destroy_effect(_active_effect)
		_active_effect = null
	if skill_id == TUMO_CI:
		_destroy_effect(_tumo_guard_effect)
		_tumo_guard_effect = null
	super.exit()


func dispose() -> void:
	_destroy_effect(_shield_effect)
	_destroy_effect(_active_effect)
	_destroy_effect(_tumo_guard_effect)
	_shield_effect = null
	_active_effect = null
	_tumo_guard_effect = null
	_shield_seconds_left = 0.0
	actor.set_role_skill_visual_hidden(false)


func reactivate_current_skill() -> bool:
	if get_current_skill_id() != TUMO_CI or _tumo_reactivated:
		return false
	if _elapsed_ticks < int(current_skill.get("reactivate_from_tick", 31)):
		return false
	var mana_cost := int(current_skill.get("reactivate_cost", 30))
	if not actor.can_spend_mana(mana_cost):
		return false
	actor.spend_mana(mana_cost)
	_tumo_reactivated = true
	_elapsed_ticks = 0
	_tick_accumulator = 0.0
	animator.play_action(StringName(current_skill.get("reactivate_action", &"skill_tumo_ci_finish")), true)
	if _tumo_guard_effect != null and is_instance_valid(_tumo_guard_effect):
		_tumo_guard_effect.seek_frame(139)
	# 显示调节（土魔刺·二次激活）：刺以角色基准点为圆心，半径由 stab_radius 控制，随后转向目标。
	_spawn_tumo_stabs()
	return true


func process_persistent(delta: float) -> void:
	if _shield_seconds_left <= 0.0:
		return
	_shield_seconds_left = maxf(0.0, _shield_seconds_left - delta)
	if _shield_seconds_left <= 0.0:
		_destroy_effect(_shield_effect)
		_shield_effect = null


func is_persistently_invulnerable() -> bool:
	return _shield_seconds_left > 0.0


func is_invulnerable() -> bool:
	return get_current_skill_id() == TUMO_CI or super.is_invulnerable()


func modify_outgoing_damage(damage: int) -> int:
	return _resolve_next_attack_damage(damage)


func modify_incoming_damage(damage: int, damage_kind: StringName) -> int:
	if damage_kind != &"physical" or profile == null:
		return damage
	return maxi(1, damage - profile.passive_physical_defense)


func on_damage_received(damage: int) -> void:
	if damage <= 0 or profile == null or profile.passive_damage_heal_amount <= 0:
		return
	if randf() <= profile.passive_damage_heal_chance:
		actor.heal(profile.passive_damage_heal_amount)


func on_incoming_hit_blocked(source: Object, damage: int) -> void:
	if get_current_skill_id() != TUMO_CI:
		return
	if source == null or not is_instance_valid(source) or not source.has_method("take_hit"):
		return
	var direction: float = actor.facing
	if source is Node2D:
		direction = signf((source as Node2D).global_position.x - actor.global_position.x)
	source.call("take_hit", damage * 2, Vector2(120.0 * direction, -48.0))


func skill_tick() -> void:
	match get_current_skill_id():
		DUNJI:
			_tick_dunji()
		SHENGDUN:
			_tick_shengdun()
		ZHANZHENG_NUHOU:
			_tick_zhanzheng_nuhou()
		SHENGYU_ZHIQIANG:
			_tick_shengyu_zhiqiang()
		SUISHI_PO:
			_tick_suishi_po()
		JUSHI_PO:
			_tick_jushi_po()
		DIGUN_QIU:
			_tick_digun_qiu()
		XUANGUN_QIU:
			_tick_xuangun_qiu()
		TUMO_CI:
			_tick_tumo_ci()
		_:
			super.skill_tick()


func get_horizontal_velocity(facing: float) -> float:
	if get_current_skill_id() == DIGUN_QIU:
		if _elapsed_ticks < int(current_skill.get("movement_start_tick", 8)):
			return 0.0
	return super.get_horizontal_velocity(facing)


# 显示调节（盾击）：bash=(35, -55)，世界坐标。
func _tick_dunji() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 1)):
		_spawn_damage_effect(&"bash", Vector2(35, -55))
	_finish_at_duration()


# 显示调节（圣盾）：cast=(70, -110)，世界坐标；buff=(-20 * facing, -80)，跟随角色。
func _tick_shengdun() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 1)):
		actor.spawn_role_skill_effect(
			get_effect(&"cast"),
			actor.flash_actor_point(get_effect_display_offset(&"cast", Vector2(70, -110)))
		)
		_shield_seconds_left = float(current_skill.get("shield_seconds", 10.0))
		_destroy_effect(_shield_effect)
		var buff_offset := get_effect_display_offset(&"buff", Vector2(-20, -80))
		var buff_origin := actor.global_position + Vector2(buff_offset.x * actor.facing, buff_offset.y)
		_shield_effect = actor.spawn_role_skill_effect(get_effect(&"buff"), buff_origin, true)
	_finish_at_duration()


# 显示调节（战争怒吼）：roar=(120, -115)，世界坐标；destination=(0, -100) 是拉怪终点。
func _tick_zhanzheng_nuhou() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 1)):
		actor.spawn_role_skill_effect(
			get_effect(&"roar"),
			actor.flash_actor_point(get_effect_display_offset(&"roar", Vector2(120, -115)))
		)
		var destination: Vector2 = actor.flash_actor_point(Vector2(0, -100))
		for target in actor.find_role_skill_targets_at(Vector2(1880, 900), actor.global_position + Vector2(0, -200)):
			actor.move_role_skill_target(target as Node2D, destination, float(current_skill.get("pull_seconds", 1.0)))
		_next_attack_multiplier = float(current_skill.get("next_attack_multiplier", 1.3))
	_finish_at_duration()


# 显示调节（圣域之墙）：charge=(140, -160)，wall=(135, -145)，均为世界坐标。
func _tick_shengyu_zhiqiang() -> void:
	if _elapsed_ticks == 5:
		actor.spawn_role_skill_effect(
			get_effect(&"charge"),
			actor.flash_actor_point(get_effect_display_offset(&"charge", Vector2(140, -160)))
		)
	if _elapsed_ticks == 17:
		_spawn_damage_effect(&"wall", Vector2(135, -145), true)
	_finish_at_duration()


# 显示调节（碎石破）：impact=(95, 0)，spikes=(-20, -20)，均为世界坐标。
func _tick_suishi_po() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 7)):
		actor.spawn_role_skill_effect(
			get_effect(&"impact"),
			actor.flash_actor_point(get_effect_display_offset(&"impact", Vector2(95, 0)))
		)
		_spawn_damage_effect(&"spikes", Vector2(-20, -20), true)
	_finish_at_duration()


# 显示调节（巨石破）：rocks=(195, -160)，世界坐标。
func _tick_jushi_po() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 7)):
		_spawn_damage_effect(&"rocks", Vector2(195, -160), true)
	_finish_at_duration()


# 显示调节（地滚球）：ball=(55, -25)，跟随角色。
func _tick_digun_qiu() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 8)):
		var origin: Vector2 = actor.flash_actor_point(
			get_effect_display_offset(&"ball", Vector2(55, -25))
		)
		var ball_spec: Dictionary = get_effect(&"ball")
		_active_effect = actor.spawn_role_skill_effect(ball_spec, origin, true)
		var center: Vector2 = actor.role_skill_effect_bounds_center(ball_spec, origin)
		var damage: int = _resolve_next_attack_damage(int(current_skill.get("damage", 20)))
		actor.schedule_following_role_skill_box_hits(
			center - actor.global_position,
			Vector2(current_skill.get("hitbox_size", Vector2(150, 115))), damage,
			Vector2(current_skill.get("knockback", Vector2(360, -48))),
			int(current_skill.get("repeat_count", 4)),
			float(current_skill.get("hit_interval_seconds", 7.0 / 24.0))
		)
	_finish_at_duration()


# 显示调节（旋滚球）：ball=(135, -90)，跟随角色。
func _tick_xuangun_qiu() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 3)):
		var origin: Vector2 = actor.flash_actor_point(
			get_effect_display_offset(&"ball", Vector2(135, -90))
		)
		var ball_spec: Dictionary = get_effect(&"ball")
		_active_effect = actor.spawn_role_skill_effect(ball_spec, origin, true)
		actor.set_role_skill_visual_hidden(true)
		var center: Vector2 = actor.role_skill_effect_bounds_center(ball_spec, origin)
		var damage: int = _resolve_next_attack_damage(int(current_skill.get("damage", 60)))
		actor.schedule_following_role_skill_box_hits(
			center - actor.global_position,
			Vector2(current_skill.get("hitbox_size", Vector2(244, 231))), damage,
			Vector2(current_skill.get("knockback", Vector2.ZERO)),
			int(current_skill.get("repeat_count", 4)),
			float(current_skill.get("hit_interval_seconds", 7.0 / 24.0))
		)
	_finish_at_duration()


# 显示调节（土魔刺）：guard=(0, 0)，跟随角色；二次激活的环形刺参数见 reactivate_current_skill()。
func _tick_tumo_ci() -> void:
	if _tumo_reactivated:
		if _elapsed_ticks >= int(current_skill.get("reactivate_duration_ticks", 20)):
			finish_skill()
		return
	if _elapsed_ticks == int(current_skill.get("guard_tick", 1)):
		_tumo_guard_effect = actor.spawn_role_skill_effect(
			get_effect(&"guard"),
			actor.flash_actor_point(get_effect_display_offset(&"guard", Vector2.ZERO)),
			true
		)
	if _elapsed_ticks == int(current_skill.get("hide_tick", 11)):
		actor.set_role_skill_visual_hidden(true)
	_finish_at_duration()


func _spawn_damage_effect(effect_id: StringName, source_delta: Vector2, repeated := false) -> void:
	var spec: Dictionary = get_effect(effect_id)
	var origin: Vector2 = actor.flash_actor_point(
		get_effect_display_offset(effect_id, source_delta)
	)
	actor.spawn_role_skill_effect(spec, origin)
	var center: Vector2 = actor.role_skill_effect_bounds_center(spec, origin)
	var damage: int = _resolve_next_attack_damage(int(current_skill.get("damage", 0)))
	var size: Vector2 = Vector2(current_skill.get("hitbox_size", Vector2(96, 96)))
	var knockback: Vector2 = Vector2(current_skill.get("knockback", Vector2.ZERO))
	if repeated:
		actor.schedule_role_skill_box_hits(
			center, size, damage, knockback,
			int(current_skill.get("repeat_count", 1)),
			float(current_skill.get("hit_interval_seconds", 0.0))
		)
	else:
		for target in actor.find_role_skill_targets_at(size, center):
			actor.apply_role_skill_hit(target, damage, knockback)


func _spawn_tumo_stabs() -> void:
	var stab_count: int = int(current_skill.get("stab_count", 10))
	var radius: float = float(current_skill.get("stab_radius", 100.0))
	var turn_seconds: float = float(current_skill.get("stab_delay_seconds", 1.0))
	var center: Vector2 = actor.flash_actor_point(
		get_effect_display_offset(&"stab", Vector2.ZERO)
	)
	var target: Node2D = actor.find_nearest_role_skill_target() as Node2D
	var target_point: Vector2 = target.global_position + Vector2(0, -50) if target != null else center + Vector2(1, 300)
	var stab_spec: Dictionary = get_effect(&"stab")
	for index in range(stab_count):
		var angle: float = TAU * float(index) / float(stab_count)
		var source: Vector2 = center + Vector2(sin(angle), -cos(angle)) * radius
		var effect: OneShotSpriteEffect = actor.spawn_role_skill_effect(stab_spec, source)
		if effect == null:
			continue
		effect.rotation = angle
		effect.modulate.a = 0.0
		var turn_tween: Tween = actor.get_tree().create_tween().set_parallel(true)
		turn_tween.tween_property(effect, "rotation", (target_point - source).angle() + PI / 2.0, turn_seconds)
		turn_tween.tween_property(effect, "modulate:a", 1.0, turn_seconds)
		var move_tween: Tween = actor.get_tree().create_tween()
		move_tween.tween_interval(turn_seconds)
		move_tween.tween_property(effect, "global_position", target_point, 0.35)
	var damage: int = _resolve_next_attack_damage(int(current_skill.get("damage", 14)))
	actor.schedule_role_skill_box_hits(
		target_point, Vector2(current_skill.get("hitbox_size", Vector2(64, 96))),
		damage, Vector2(0, -120), stab_count, 0.03, turn_seconds + 0.35
	)


func _resolve_next_attack_damage(damage: int) -> int:
	if _next_attack_multiplier <= 1.0:
		return damage
	var resolved := int(floor(damage * _next_attack_multiplier))
	_next_attack_multiplier = 1.0
	return resolved


func _finish_at_duration() -> void:
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 1)):
		finish_skill()


func _destroy_effect(effect: Node) -> void:
	if effect != null and is_instance_valid(effect):
		effect.queue_free()
