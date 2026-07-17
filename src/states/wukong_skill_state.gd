class_name WukongSkillState
extends RoleSkillState

# 技能显示调节说明：
# - 下方每个“显示调节”备注都列出了该技能的特效阶段与角色基准偏移。
# - Vector2(x, y)：x 正数=面朝方向前方，x 负数=身后；y 负数=上方，y 正数=下方。
# - “跟随”表示角色移动时特效一起移动；“世界坐标”表示生成后留在原地。
# - 这里只调整视觉；若希望伤害范围同步移动，还要调整对应 hitbox_offset。

const QISHIER_ZHAN := &"qishier_zhan"
const ZHONGZHAN := &"zhongzhan"
const LIEYAN_SHAN := &"lieyan_shan"
const HUOYAN_JINJING := &"huoyan_jinjing"
const SHENGLONG_ZHAN := &"shenglong_zhan"
const HUOMO_ZHAN := &"huomo_zhan"
const HUOYAN_TUJI := &"huoyan_tuji"
const LIEYAN_FENGBAO := &"lieyan_fengbao"
const JINDOU_YUN := &"jindou_yun"

var _contact_target: Object
var _contact_tick := -1
var _hit_targets: Dictionary = {}
var _huomo_phase := &""
var _phase_tick := 0
var _jindou_vertical := false
var _jindou_phase_start_tick := 0
var _jindou_effect: OneShotSpriteEffect


func enter(payload: Dictionary = {}) -> void:
	_contact_target = null
	_contact_tick = -1
	_hit_targets.clear()
	_huomo_phase = &"launch"
	_phase_tick = 0
	_jindou_vertical = false
	_jindou_phase_start_tick = 0
	_jindou_effect = null
	super.enter(payload)


func exit() -> void:
	_contact_target = null
	_contact_tick = -1
	_hit_targets.clear()
	if _jindou_effect != null and is_instance_valid(_jindou_effect):
		_jindou_effect.queue_free()
	_jindou_effect = null
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
		SHENGLONG_ZHAN:
			_tick_shenglong_zhan()
		HUOMO_ZHAN:
			_tick_huomo_zhan()
		HUOYAN_TUJI:
			_tick_huoyan_tuji()
		LIEYAN_FENGBAO:
			_tick_lieyan_fengbao()
		JINDOU_YUN:
			_tick_jindou_yun()
		_:
			super.skill_tick()


func get_horizontal_velocity(facing: float) -> float:
	if get_current_skill_id() == QISHIER_ZHAN and _contact_target != null:
		return 0.0
	if get_current_skill_id() == HUOYAN_TUJI:
		var remaining := clampi(
			int(current_skill.get("duration_ticks", 15)) - _elapsed_ticks + 1, 0, 15
		)
		return float(current_skill.get("max_move_speed", 600.0)) * remaining / 15.0 * signf(facing)
	if get_current_skill_id() == HUOMO_ZHAN:
		if _huomo_phase == &"launch":
			return 672.0 * signf(facing)
		if _huomo_phase == &"fall":
			return 960.0 * signf(facing)
		return 0.0
	if get_current_skill_id() == JINDOU_YUN:
		if _jindou_vertical:
			return 0.0
		return float(current_skill.get("horizontal_speed", 600.0)) * signf(facing)
	return super.get_horizontal_velocity(facing)


func blocks_gravity() -> bool:
	if get_current_skill_id() == JINDOU_YUN and _jindou_vertical:
		return true
	if get_current_skill_id() == HUOMO_ZHAN:
		return _huomo_phase != &"launch"
	return super.blocks_gravity()


func get_vertical_velocity() -> float:
	if get_current_skill_id() == JINDOU_YUN and _jindou_vertical:
		return float(current_skill.get("vertical_speed", -600.0))
	if get_current_skill_id() == HUOMO_ZHAN:
		if _huomo_phase == &"fall":
			return 960.0
		return 0.0
	return super.get_vertical_velocity()


func is_invulnerable() -> bool:
	if get_current_skill_id() == HUOMO_ZHAN:
		return true
	return super.is_invulnerable()


func reactivate_current_skill() -> bool:
	if get_current_skill_id() != JINDOU_YUN or _jindou_vertical:
		return false
	_jindou_vertical = true
	_jindou_phase_start_tick = _elapsed_ticks
	if _jindou_effect != null and is_instance_valid(_jindou_effect):
		_jindou_effect.queue_free()
	animator.play_action(&"skill_jindou_yun_vertical", true)
	# 显示调节（金斗云·二次激活）：vertical=(0, -50)，跟随角色。
	_jindou_effect = actor.spawn_role_skill_effect(
		get_effect(&"vertical"),
		actor.flash_actor_point(get_effect_display_offset(&"vertical", Vector2(0, -50))),
		true
	)
	return true


# 显示调节（七十二斩）：impact 直接生成在命中目标的 Flash 基准点，无角色偏移。
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
			actor.spawn_role_skill_effect(
				get_effect(&"impact"),
				actor.flash_target_point(
					_contact_target as Node2D,
					get_effect_display_offset(&"impact", Vector2.ZERO)
				)
			)
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


# 显示调节（重斩）：charge=(-15, -85)，跟随角色；slash=(145, -60)，世界坐标。
func _tick_zhongzhan() -> void:
	if _elapsed_ticks == int(current_skill.get("charge_tick", 1)):
		actor.spawn_role_skill_effect(
			get_effect(&"charge"),
			actor.flash_actor_point(get_effect_display_offset(&"charge", Vector2(-15, -85))),
			true
		)
	if _elapsed_ticks == int(current_skill.get("hit_tick", 15)):
		var effect_origin: Vector2 = actor.flash_actor_point(
			get_effect_display_offset(&"slash", Vector2(145, -60))
		)
		actor.spawn_role_skill_effect(get_effect(&"slash"), effect_origin)
		_damage_box(
			Vector2(current_skill.get("hitbox_size", Vector2(194, 123))),
			Vector2(current_skill.get("hitbox_offset", Vector2(100, -60))),
			int(current_skill.get("damage", 90)),
			Vector2(current_skill.get("knockback", Vector2(480, 0)))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 30)):
		finish_skill()


# 显示调节（烈焰闪）：dash=(120, -50)，跟随角色。
func _tick_lieyan_shan() -> void:
	if _elapsed_ticks == 1:
		actor.set_role_skill_visual_hidden(true)
		actor.spawn_role_skill_effect(
			get_effect(&"dash"),
			actor.flash_actor_point(get_effect_display_offset(&"dash", Vector2(120, -50))),
			true
		)
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


# 显示调节（火眼金睛）：cast_eye≈(21, -10)，跟随角色；cast_flare≈(-65, 0)，关闭朝向镜像并跟随角色；explosion 生成在目标处。
func _tick_huoyan_jinjing() -> void:
	if _elapsed_ticks == 1:
		var eye_x := 21.0 if actor.facing > 0.0 else 22.0
		actor.spawn_role_skill_effect(
			get_effect(&"cast_eye"),
			actor.flash_actor_point(get_effect_display_offset(&"cast_eye", Vector2(eye_x, -10))),
			true
		)
		# The Flash source places this screen flare to the actor's left for both facings.
		var flare_x := -65.0 if actor.facing > 0.0 else -55.0
		actor.spawn_role_skill_effect(
			get_effect(&"cast_flare"),
			actor.flash_actor_point(
				get_effect_display_offset(&"cast_flare", Vector2(flare_x, 0)), false
			),
			true
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
				float(current_skill.get("repeat_interval", 2.0)),
				get_effect_display_offset(&"explosion", Vector2.ZERO)
			)
		finish_skill()


# 显示调节（升龙斩）：strike=(30, 40)，跟随角色。
func _tick_shenglong_zhan() -> void:
	if _elapsed_ticks == int(current_skill.get("effect_tick", 3)):
		actor.spawn_role_skill_effect(
			get_effect(&"strike"),
			actor.flash_actor_point(get_effect_display_offset(&"strike", Vector2(30, 40))),
			true
		)
		_damage_box(
			Vector2(current_skill.get("hitbox_size", Vector2(142, 193))),
			Vector2(current_skill.get("hitbox_offset", Vector2(30, -5))),
			int(current_skill.get("damage", 36)),
			Vector2(current_skill.get("knockback", Vector2(336, -600)))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 11)):
		finish_skill()


# 显示调节（火焰突击）：dash=(175, -30)，跟随角色。
func _tick_huoyan_tuji() -> void:
	if _elapsed_ticks == 1:
		actor.spawn_role_skill_effect(
			get_effect(&"dash"),
			actor.flash_actor_point(get_effect_display_offset(&"dash", Vector2(175, -30))),
			true
		)
	var interval := int(current_skill.get("hit_interval_ticks", 4))
	if (_elapsed_ticks - 1) % interval == 0:
		_damage_box_repeated(
			Vector2(current_skill.get("hitbox_size", Vector2(289, 89))),
			Vector2(current_skill.get("hitbox_offset", Vector2(120, -75))),
			int(current_skill.get("damage", 9)),
			Vector2(current_skill.get("knockback", Vector2(360, 0)))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 15)):
		finish_skill()


# 显示调节（烈焰风暴）：storm=(20, 30)，跟随角色。
func _tick_lieyan_fengbao() -> void:
	if _elapsed_ticks == 1:
		actor.spawn_role_skill_effect(
			get_effect(&"storm"),
			actor.flash_actor_point(get_effect_display_offset(&"storm", Vector2(20, 30))),
			true
		)
	var interval := int(current_skill.get("hit_interval_ticks", 3))
	if (_elapsed_ticks - 1) % interval == 0:
		_damage_box_repeated(
			Vector2(current_skill.get("hitbox_size", Vector2(369, 158))),
			Vector2(current_skill.get("hitbox_offset", Vector2(20, -20))),
			int(current_skill.get("damage", 21)),
			Vector2(current_skill.get("knockback", Vector2(192, -48)))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 10)):
		finish_skill()


# 显示调节（金斗云）：horizontal=(50, -50)，跟随角色；vertical=(0, -50) 在二次激活处生成。
func _tick_jindou_yun() -> void:
	if _elapsed_ticks == 1:
		_jindou_effect = actor.spawn_role_skill_effect(
			get_effect(&"horizontal"),
			actor.flash_actor_point(get_effect_display_offset(&"horizontal", Vector2(50, -50))),
			true
		)
	var phase_elapsed := _elapsed_ticks - _jindou_phase_start_tick
	var interval := int(current_skill.get("hit_interval_ticks", 5))
	if phase_elapsed > 0 and (phase_elapsed - 1) % interval == 0:
		var offset := Vector2(0, -50) if _jindou_vertical else Vector2(50, -50)
		_damage_box_repeated(
			Vector2(current_skill.get("hitbox_size", Vector2(234, 155))),
			offset,
			int(current_skill.get("damage", 5)),
			Vector2(current_skill.get(
				"vertical_knockback" if _jindou_vertical else "knockback",
				Vector2(0, -600) if _jindou_vertical else Vector2(480, 0)
			))
		)
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 35)):
		finish_skill()


# 显示调节（火魔斩）：hover=(-10, 0)，关闭朝向镜像、世界坐标；fall=(0, -40)、land=(0, 40)，均为世界坐标。
func _tick_huomo_zhan() -> void:
	if _huomo_phase == &"launch":
		if _elapsed_ticks == 1:
			actor.velocity.y = -840.0
		if _elapsed_ticks >= 6:
			var nearby: Array = actor.find_role_skill_targets(Vector2(200, 200), Vector2(0, -70))
			if nearby.is_empty():
				_start_huomo_fall()
			else:
				_huomo_phase = &"hover"
				_phase_tick = 0
				actor.set_role_skill_visual_hidden(true)
				actor.spawn_role_skill_effect(
					get_effect(&"hover"),
					actor.flash_actor_point(
						get_effect_display_offset(&"hover", Vector2(-10, 0)), false
					)
				)
	elif _huomo_phase == &"hover":
		_phase_tick += 1
		if _phase_tick <= 44 and (_phase_tick - 1) % 5 == 0:
			_damage_box_repeated(
				Vector2(368, 231), Vector2(-10, -45),
				int(current_skill.get("hover_damage", 18)), Vector2(48, -48)
			)
		if _phase_tick >= int(current_skill.get("hover_ticks", 46)):
			_start_huomo_fall()
	elif _huomo_phase == &"fall":
		_phase_tick += 1
		if (_phase_tick > 1 and actor.is_on_floor()) or _phase_tick >= 30:
			_start_huomo_land()
	elif _huomo_phase == &"land":
		_phase_tick += 1
		if _phase_tick >= 11:
			finish_skill()


func _start_huomo_fall() -> void:
	_huomo_phase = &"fall"
	_phase_tick = 0
	actor.set_role_skill_visual_hidden(true)
	actor.spawn_role_skill_effect(
		get_effect(&"fall"),
		actor.flash_actor_point(get_effect_display_offset(&"fall", Vector2(0, -40)))
	)
	_damage_box_repeated(Vector2(164, 237), Vector2(0, -90), 14, Vector2(240, 480))


func _start_huomo_land() -> void:
	_huomo_phase = &"land"
	_phase_tick = 0
	actor.spawn_role_skill_effect(
		get_effect(&"land"),
		actor.flash_actor_point(get_effect_display_offset(&"land", Vector2(0, 40)))
	)
	_damage_box_repeated(
		Vector2(197, 178), Vector2(0, -10),
		int(current_skill.get("land_damage", 90)), Vector2(240, -360)
	)


func _damage_box(size: Vector2, offset: Vector2, damage: int, knockback: Vector2) -> void:
	for target in actor.find_role_skill_targets(size, offset):
		if _hit_targets.has(target):
			continue
		_hit_targets[target] = true
		actor.apply_role_skill_hit(target, damage, knockback)


func _damage_box_repeated(size: Vector2, offset: Vector2, damage: int, knockback: Vector2) -> void:
	for target in actor.find_role_skill_targets(size, offset):
		actor.apply_role_skill_hit(target, damage, knockback)
