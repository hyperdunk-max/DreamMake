class_name SkillEffectCalibrator
extends Node2D

const FLASH_ACTOR_ORIGIN_Y := -50.0
const CALIBRATOR_WINDOW_SIZE := Vector2i(1280, 800)
const CONTROL_PANEL_WIDTH := 330.0
const SKILL_EFFECT_DISPLAY_CONFIG := preload(
	"res://src/skills/skill_effect_display_config.gd"
)

const ROLE_ENTRIES := [
	{"name": "悟空", "path": "res://resources/roles/role_1_wukong_definition.tres"},
	{"name": "唐僧", "path": "res://resources/roles/role_2_tangseng_definition.tres"},
	{"name": "八戒", "path": "res://resources/roles/role_3_bajie_definition.tres"},
	{"name": "沙僧", "path": "res://resources/roles/role_4_shaseng_definition.tres"},
]

const SKILL_NAMES := {
	"qishier_zhan": "七十二斩", "zhongzhan": "重斩", "lieyan_shan": "烈焰闪",
	"huoyan_jinjing": "火眼金睛", "shenglong_zhan": "升龙斩", "huomo_zhan": "火魔斩",
	"huoyan_tuji": "火焰突击", "lieyan_fengbao": "烈焰风暴", "jindou_yun": "金斗云",
	"binglong_bo": "冰龙波", "shengguang_qiu": "圣光球", "muyu_huichun": "沐浴回春",
	"jingu_zhou": "紧箍咒", "tianjiang_ganlu": "天降甘露", "jiuhuan_shengjing": "九环圣经",
	"xuanbing_zhen": "玄冰阵", "shuihuanying": "水幻影", "shuimo_bao": "水魔爆",
	"dunji": "盾击", "shengdun": "圣盾", "zhanzheng_nuhou": "战争怒吼",
	"shengyu_zhiqiang": "圣域之墙", "suishi_po": "碎石破", "jushi_po": "巨石破",
	"digun_qiu": "地滚球", "xuangun_qiu": "旋滚球", "tumo_ci": "土魔刺",
	"zhang_qi": "瘴气", "wudu_wawa": "巫毒娃娃", "mabi_yaoji": "麻痹药剂",
	"judu_zhen": "剧毒阵", "mengdu_su": "猛毒素", "qiangli_ji": "强力击",
	"tengkong_ji": "腾空击", "duozhong_ji": "多重击", "lvye_biaoji": "绿叶标记",
	"mumo_wu": "木魔舞",
}

# 这里保存正式技能代码的默认 source_delta；一键保存后的值写入独立覆盖配置。
const DEFAULT_OFFSETS := {
	"1/qishier_zhan/impact": Vector2.ZERO,
	"1/zhongzhan/charge": Vector2(-15, -85), "1/zhongzhan/slash": Vector2(145, -60),
	"1/lieyan_shan/dash": Vector2(120, -50),
	"1/huoyan_jinjing/cast_eye": Vector2(21, -10), "1/huoyan_jinjing/cast_flare": Vector2(-65, 0),
	"1/huoyan_jinjing/explosion": Vector2.ZERO,
	"1/shenglong_zhan/strike": Vector2(30, 40),
	"1/huomo_zhan/hover": Vector2(-10, 0), "1/huomo_zhan/fall": Vector2(0, -40),
	"1/huomo_zhan/land": Vector2(0, 40),
	"1/huoyan_tuji/dash": Vector2(175, -30),
	"1/lieyan_fengbao/storm": Vector2(20, 30),
	"1/jindou_yun/horizontal": Vector2(50, -50), "1/jindou_yun/vertical": Vector2(0, -50),

	"2/binglong_bo/beam": Vector2(50, 10),
	"2/shengguang_qiu/orb": Vector2(175, -110),
	"2/muyu_huichun/spring": Vector2(0, -25),
	"2/jingu_zhou/ring": Vector2(210, 30),
	"2/tianjiang_ganlu/rain": Vector2(-5, -60),
	"2/jiuhuan_shengjing/aura": Vector2(20, -20), "2/jiuhuan_shengjing/strike": Vector2(150, -150),
	"2/xuanbing_zhen/ice": Vector2(0, 10),
	"2/shuihuanying/shadow": Vector2(0, -5),
	"2/shuimo_bao/marker": Vector2(130, 10), "2/shuimo_bao/blast": Vector2(30, -320),

	"3/dunji/bash": Vector2(35, -55),
	"3/shengdun/cast": Vector2(70, -110), "3/shengdun/buff": Vector2(-20, -80),
	"3/zhanzheng_nuhou/roar": Vector2(120, -115),
	"3/shengyu_zhiqiang/charge": Vector2(140, -160), "3/shengyu_zhiqiang/wall": Vector2(135, -145),
	"3/suishi_po/impact": Vector2(95, 0), "3/suishi_po/spikes": Vector2(-20, -20),
	"3/jushi_po/rocks": Vector2(195, -160),
	"3/digun_qiu/ball": Vector2(55, -25), "3/xuangun_qiu/ball": Vector2(135, -90),
	"3/tumo_ci/guard": Vector2.ZERO, "3/tumo_ci/stab": Vector2.ZERO,

	"4/zhang_qi/arrow": Vector2(30, 0), "4/zhang_qi/shovel": Vector2(245, -110),
	"4/wudu_wawa/cast": Vector2(115, -110), "4/wudu_wawa/doll": Vector2(0, -20),
	"4/mabi_yaoji/orb": Vector2(25, -30),
	"4/judu_zhen/array": Vector2(155, -50), "4/judu_zhen/burst": Vector2(150, -70),
	"4/mengdu_su/blast": Vector2.ZERO,
	"4/qiangli_ji/arrow_charge": Vector2(75, -60), "4/qiangli_ji/arrow_impact": Vector2(65, -10),
	"4/qiangli_ji/shovel": Vector2(125, -30),
	"4/tengkong_ji/arrow_charge": Vector2(80, -80), "4/tengkong_ji/arrow_impact": Vector2(60, 30),
	"4/tengkong_ji/shovel_charge": Vector2.ZERO, "4/tengkong_ji/shovel_impact": Vector2(0, -80),
	"4/duozhong_ji/arrow_charge": Vector2.ZERO, "4/duozhong_ji/arrow_impact": Vector2(225, -80),
	"4/duozhong_ji/shovel": Vector2(150, -50),
	"4/lvye_biaoji/mark": Vector2.ZERO,
	"4/mumo_wu/arrow_aura": Vector2(80, -100), "4/mumo_wu/arrow_body": Vector2.ZERO,
	"4/mumo_wu/arrow_leaf": Vector2(88, 7), "4/mumo_wu/shovel": Vector2(150, 0),
}

const PLACEMENT_NOTES := {
	"1/qishier_zhan/impact": "正式游戏中生成在目标位置。",
	"1/huoyan_jinjing/cast_flare": "关闭 X 朝向镜像；左右朝向使用略不同的 X。",
	"1/huoyan_jinjing/explosion": "正式游戏中生成在目标位置。",
	"1/huomo_zhan/hover": "关闭 X 朝向镜像。",
	"2/shuimo_bao/blast": "此偏移相对于水魔爆标记，不是角色。",
	"3/tumo_ci/stab": "正式游戏中按 stab_radius 环形生成并转向目标。",
	"4/judu_zhen/burst": "这里预览第一处；另外两处为 (190,-90)、(110,-80)。",
	"4/mengdu_su/blast": "正式游戏中生成并跟随中毒目标。",
	"4/mumo_wu/arrow_leaf": "动态偏移基值；正式游戏会随剩余叶片数变化。",
}

const NO_MIRROR_X := {
	"1/huoyan_jinjing/cast_flare": true,
	"1/huomo_zhan/hover": true,
}

const RAW_REFERENCE_OFFSETS := {
	"2/shuimo_bao/blast": true,
	"3/shengdun/buff": true,
}

const TARGET_REFERENCE_OFFSETS := {
	"1/qishier_zhan/impact": true,
	"1/huoyan_jinjing/explosion": true,
	"4/mengdu_su/blast": true,
}

@onready var preview_world: Node2D = $PreviewWorld
@onready var animator: LayeredSpriteAnimator = $PreviewWorld/Actor/LayeredSpriteAnimator
@onready var role_option: OptionButton = $UI/Panel/Margin/VBox/RoleOption
@onready var skill_option: OptionButton = $UI/Panel/Margin/VBox/SkillOption
@onready var effect_option: OptionButton = $UI/Panel/Margin/VBox/EffectOption
@onready var weapon_option: OptionButton = $UI/Panel/Margin/VBox/WeaponOption
@onready var x_spin: SpinBox = $UI/Panel/Margin/VBox/Coordinates/XSpin
@onready var y_spin: SpinBox = $UI/Panel/Margin/VBox/Coordinates/YSpin
@onready var zoom_spin: SpinBox = $UI/Panel/Margin/VBox/ZoomRow/ZoomSpin
@onready var facing_button: Button = $UI/Panel/Margin/VBox/Buttons/FacingButton
@onready var pause_button: Button = $UI/Panel/Margin/VBox/Buttons/PauseButton
@onready var position_label: Label = $UI/Panel/Margin/VBox/PositionLabel
@onready var frame_label: Label = $UI/Panel/Margin/VBox/FrameLabel
@onready var note_label: Label = $UI/Panel/Margin/VBox/NoteLabel
@onready var status_label: Label = $UI/Panel/Margin/VBox/StatusLabel

var _role: RoleDefinition
var _skill: Dictionary = {}
var _effect_spec: Dictionary = {}
var _effect: OneShotSpriteEffect
var _source_delta := Vector2.ZERO
var _facing := 1.0
var _dragging := false
var _updating_controls := false
var _paused := false


func _ready() -> void:
	get_window().content_scale_size = CALIBRATOR_WINDOW_SIZE
	get_window().size = CALIBRATOR_WINDOW_SIZE
	get_viewport().size_changed.connect(_update_preview_layout)
	role_option.item_selected.connect(_on_role_selected)
	skill_option.item_selected.connect(_on_skill_selected)
	effect_option.item_selected.connect(_on_effect_selected)
	weapon_option.item_selected.connect(_on_weapon_selected)
	x_spin.value_changed.connect(_on_coordinate_changed)
	y_spin.value_changed.connect(_on_coordinate_changed)
	zoom_spin.value_changed.connect(_on_zoom_changed)
	facing_button.pressed.connect(_toggle_facing)
	pause_button.pressed.connect(_toggle_pause)
	$UI/Panel/Margin/VBox/Buttons/ReplayButton.pressed.connect(_replay)
	$UI/Panel/Margin/VBox/EditButtons/ResetButton.pressed.connect(_reset_offset)
	$UI/Panel/Margin/VBox/EditButtons/SaveButton.pressed.connect(_save_offset)
	for entry in ROLE_ENTRIES:
		role_option.add_item(str(entry["name"]))
	role_option.select(0)
	_on_role_selected(0)
	_update_preview_layout()
	queue_redraw()


func _process(_delta: float) -> void:
	if _effect != null and is_instance_valid(_effect):
		frame_label.text = "当前帧：%d / %d" % [
			_effect.get_frame_index() + 1,
			int(_effect_spec.get("effect_frame_count", 0)),
		]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.x > CONTROL_PANEL_WIDTH:
			_dragging = true
			_update_offset_from_mouse(event.position)
		elif not event.pressed:
			_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_update_offset_from_mouse(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var step := 10.0 if event.shift_pressed else 1.0
		var movement := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: movement.x = -step
			KEY_RIGHT: movement.x = step
			KEY_UP: movement.y = -step
			KEY_DOWN: movement.y = step
		if movement != Vector2.ZERO:
			_set_source_delta(_source_delta + movement)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	for x in range(int(CONTROL_PANEL_WIDTH) + 10, int(viewport_size.x), 50):
		draw_line(Vector2(x, 0), Vector2(x, viewport_size.y), Color(0.16, 0.2, 0.28), 1.0)
	for y in range(0, int(viewport_size.y), 50):
		draw_line(Vector2(CONTROL_PANEL_WIDTH, y), Vector2(viewport_size.x, y), Color(0.16, 0.2, 0.28), 1.0)
	var actor_origin := preview_world.global_position
	var visual_nudge_y := _role.animation_profile.visual_nudge.y if _role != null else 0.0
	var flash_origin := preview_world.to_global(Vector2(0, FLASH_ACTOR_ORIGIN_Y + visual_nudge_y))
	var effect_reference_origin := preview_world.to_global(_effect_reference_local_origin())
	draw_line(actor_origin + Vector2(-12, 0), actor_origin + Vector2(12, 0), Color.WHITE, 2.0)
	draw_line(actor_origin + Vector2(0, -12), actor_origin + Vector2(0, 12), Color.WHITE, 2.0)
	draw_circle(flash_origin, 5.0, Color(1.0, 0.78, 0.2))
	if _effect != null and is_instance_valid(_effect):
		var effect_origin := _effect.global_position
		draw_line(effect_reference_origin, effect_origin, Color(0.3, 0.85, 1.0, 0.8), 2.0)
		draw_circle(effect_origin, 5.0, Color(0.3, 0.85, 1.0))


func _on_role_selected(index: int) -> void:
	if index < 0 or index >= ROLE_ENTRIES.size():
		return
	_role = load(str(ROLE_ENTRIES[index]["path"])) as RoleDefinition
	if _role == null:
		status_label.text = "角色资源加载失败"
		return
	animator.register_role(
		_role.role_id, _role.animation_profile,
		_role.default_body_showid, _role.default_weapon_showid
	)
	animator.set_facing(_facing)
	_populate_weapons()
	_populate_skills()


func _populate_weapons() -> void:
	weapon_option.clear()
	var weapon_ids := _role.animation_profile.get_weapon_showids()
	weapon_ids.sort()
	for weapon_id in weapon_ids:
		var mode := _role.animation_profile.get_weapon_mode(int(weapon_id))
		weapon_option.add_item("%s（ID %d）" % [str(mode), int(weapon_id)])
		weapon_option.set_item_metadata(weapon_option.item_count - 1, int(weapon_id))
	var default_index := 0
	for index in range(weapon_option.item_count):
		if int(weapon_option.get_item_metadata(index)) == _role.default_weapon_showid:
			default_index = index
			break
	weapon_option.select(default_index)
	_on_weapon_selected(default_index)


func _populate_skills() -> void:
	skill_option.clear()
	for skill in _role.skill_profile.active_skills:
		var skill_id := str(skill.get("id", ""))
		skill_option.add_item("%s  [%s]" % [SKILL_NAMES.get(skill_id, skill_id), skill_id])
		skill_option.set_item_metadata(skill_option.item_count - 1, skill_id)
	if skill_option.item_count > 0:
		skill_option.select(0)
		_on_skill_selected(0)


func _on_skill_selected(index: int) -> void:
	if _role == null or index < 0 or index >= skill_option.item_count:
		return
	var skill_id := StringName(skill_option.get_item_metadata(index))
	var skill_index := _role.skill_profile.find_skill_index(skill_id)
	_skill = _role.skill_profile.get_skill(skill_index)
	var action := StringName(_skill.get("action", _role.animation_profile.default_action))
	animator.play_action(action, true)
	effect_option.clear()
	var effects: Dictionary = _skill.get("effects", {})
	var effect_ids := effects.keys()
	effect_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for raw_effect_id in effect_ids:
		var effect_id := str(raw_effect_id)
		effect_option.add_item(effect_id)
		effect_option.set_item_metadata(effect_option.item_count - 1, effect_id)
	if effect_option.item_count > 0:
		effect_option.select(0)
		_on_effect_selected(0)


func _on_effect_selected(index: int) -> void:
	if index < 0 or index >= effect_option.item_count:
		return
	var effect_id := StringName(effect_option.get_item_metadata(index))
	_effect_spec = (_skill.get("effects", {}) as Dictionary).get(effect_id, {})
	_set_source_delta(_get_saved_offset())
	note_label.text = "备注：%s" % PLACEMENT_NOTES.get(
		_selection_key(), "拖动蓝色特效，或修改 X/Y；确认后点击一键保存。"
	)
	_spawn_effect()


func _on_weapon_selected(index: int) -> void:
	if _role == null or index < 0 or index >= weapon_option.item_count:
		return
	animator.set_weapon(int(weapon_option.get_item_metadata(index)))
	if not _skill.is_empty():
		animator.play_action(StringName(_skill.get("action", &"idle")), true)


func _spawn_effect() -> void:
	if _effect != null and is_instance_valid(_effect):
		_effect.queue_free()
	_effect = null
	var frames: Array = []
	var pattern := str(_effect_spec.get("effect_path_pattern", ""))
	for frame_index in range(int(_effect_spec.get("effect_frame_count", 0))):
		var texture := load(pattern % frame_index) as Texture2D
		if texture != null:
			frames.append(texture)
	if frames.is_empty():
		status_label.text = "没有加载到特效帧"
		return
	_effect = OneShotSpriteEffect.new()
	preview_world.add_child(_effect)
	var source_facing := int(_effect_spec.get("effect_source_facing", 1))
	var gameplay_facing := float(source_facing) if bool(_effect_spec.get("ignore_facing", false)) else _facing
	_effect.configure(
		frames, float(_effect_spec.get("effect_fps", 24.0)), source_facing,
		gameplay_facing, Vector2(_effect_spec.get("effect_sprite_offset", Vector2.ZERO))
	)
	_effect.set_looping(true)
	if _effect_spec.has("blend_mode"):
		_effect.set_blend_mode(int(_effect_spec["blend_mode"]))
	_effect.set_process(not _paused)
	_apply_effect_position()
	status_label.text = "已加载；拖动预览区即可调节"


func _selection_key() -> String:
	if _role == null or _skill.is_empty() or effect_option.selected < 0:
		return ""
	return "%d/%s/%s" % [
		_role.role_id, str(_skill.get("id", "")),
		str(effect_option.get_item_metadata(effect_option.selected)),
	]


func _get_saved_offset() -> Vector2:
	var fallback := Vector2(DEFAULT_OFFSETS.get(_selection_key(), Vector2.ZERO))
	return SKILL_EFFECT_DISPLAY_CONFIG.get_offset_by_key(_selection_key(), fallback)


func _set_source_delta(value: Vector2) -> void:
	_source_delta = Vector2(roundf(value.x), roundf(value.y))
	_updating_controls = true
	x_spin.value = _source_delta.x
	y_spin.value = _source_delta.y
	_updating_controls = false
	_apply_effect_position()
	position_label.text = "当前：Vector2(%d, %d)" % [int(_source_delta.x), int(_source_delta.y)]
	status_label.text = "预览值已修改，尚未写入正式技能"


func _apply_effect_position() -> void:
	if _effect == null or not is_instance_valid(_effect) or _role == null:
		return
	var displayed_delta := _source_delta
	if not NO_MIRROR_X.has(_selection_key()):
		displayed_delta.x *= _facing
	displayed_delta += _effect_reference_local_origin()
	_effect.position = displayed_delta


func _update_offset_from_mouse(mouse_position: Vector2) -> void:
	if _role == null:
		return
	var local_position := preview_world.to_local(mouse_position)
	local_position -= _effect_reference_local_origin()
	if not NO_MIRROR_X.has(_selection_key()):
		local_position.x *= _facing
	_set_source_delta(local_position)


func _effect_reference_local_origin() -> Vector2:
	if _role == null or RAW_REFERENCE_OFFSETS.has(_selection_key()):
		return Vector2.ZERO
	var y := FLASH_ACTOR_ORIGIN_Y
	if not TARGET_REFERENCE_OFFSETS.has(_selection_key()):
		y += _role.animation_profile.visual_nudge.y
	return Vector2(0, y)


func _on_coordinate_changed(_value: float) -> void:
	if _updating_controls:
		return
	_set_source_delta(Vector2(x_spin.value, y_spin.value))


func _on_zoom_changed(value: float) -> void:
	preview_world.scale = Vector2.ONE * float(value)
	queue_redraw()


func _toggle_facing() -> void:
	_facing *= -1.0
	facing_button.text = "朝向：右" if _facing > 0.0 else "朝向：左"
	animator.set_facing(_facing)
	_spawn_effect()


func _toggle_pause() -> void:
	_paused = not _paused
	pause_button.text = "继续" if _paused else "暂停"
	if _effect != null and is_instance_valid(_effect):
		_effect.set_process(not _paused)


func _replay() -> void:
	animator.play_action(StringName(_skill.get("action", &"idle")), true)
	if _effect != null and is_instance_valid(_effect):
		_effect.seek_frame(0)
		_effect.set_process(not _paused)


func _reset_offset() -> void:
	_set_source_delta(_get_saved_offset())
	status_label.text = "已恢复最近一次保存值"


func _save_offset() -> void:
	var error: Error = SKILL_EFFECT_DISPLAY_CONFIG.save_offset_by_key(
		_selection_key(), _source_delta
	)
	if error != OK:
		status_label.text = "保存失败，错误码：%d" % error
		return
	status_label.text = "已保存，正式游戏将直接使用 Vector2(%d, %d)" % [
		int(_source_delta.x), int(_source_delta.y),
	]


func _update_preview_layout() -> void:
	var viewport_size := get_viewport_rect().size
	preview_world.position = Vector2(
		CONTROL_PANEL_WIDTH + (viewport_size.x - CONTROL_PANEL_WIDTH) * 0.52,
		viewport_size.y * 0.7
	)
	queue_redraw()
