class_name RoleSkillState
extends CharacterActionState

const ID := &"role_skill"
const SKILL_EFFECT_DISPLAY_CONFIG := preload(
	"res://src/skills/skill_effect_display_config.gd"
)

var profile: RoleSkillProfile
var current_skill: Dictionary = {}
var _elapsed_ticks := 0
var _tick_accumulator := 0.0


func configure(skill_profile: RoleSkillProfile) -> void:
	profile = skill_profile
	current_skill = {}
	_elapsed_ticks = 0
	_tick_accumulator = 0.0


func is_configured() -> bool:
	return profile != null and profile.get_skill_count() > 0


func request_skill(slot: int) -> bool:
	if not is_configured():
		return false
	var skill := profile.get_skill(slot)
	if skill.is_empty():
		return false
	if state_machine.is_in_state(ID):
		if StringName(skill.get("id", &"")) != get_current_skill_id():
			return false
		return reactivate_current_skill()
	if state_machine.has_active_state():
		return false
	if not bool(skill.get("allow_air", true)) and not actor.is_on_floor():
		return false
	var mana_cost := int(skill.get("mana_cost", 0))
	if not actor.has_method("can_spend_mana") or not actor.can_spend_mana(mana_cost):
		return false
	return state_machine.transition_to(ID, {"slot": slot})


func request_skill_by_id(skill_id: StringName) -> bool:
	if profile == null:
		return false
	return request_skill(profile.find_skill_index(skill_id))


func reactivate_current_skill() -> bool:
	return false


func release_normal_attack() -> bool:
	return false


func request_charged_normal_attack() -> bool:
	return false


func modify_outgoing_damage(damage: int) -> int:
	return damage


func modify_incoming_damage(damage: int, _damage_kind: StringName) -> int:
	return damage


func on_damage_received(_damage: int) -> void:
	pass


func on_incoming_hit_blocked(_source: Object, _damage: int) -> void:
	pass


func process_persistent(_delta: float) -> void:
	pass


func is_persistently_invulnerable() -> bool:
	return false


func dispose() -> void:
	pass


func enter(payload: Dictionary = {}) -> void:
	current_skill = profile.get_skill(int(payload.get("slot", -1)))
	_elapsed_ticks = 0
	_tick_accumulator = 0.0
	actor.spend_mana(int(current_skill.get("mana_cost", 0)))
	if actor.has_method("on_role_skill_started"):
		actor.on_role_skill_started(current_skill)
	if bool(current_skill.get("play_action", true)):
		animator.play_action(StringName(current_skill["action"]), true)


func exit() -> void:
	_tick_accumulator = 0.0
	if actor.has_method("set_role_skill_visual_hidden"):
		actor.set_role_skill_visual_hidden(false)


func physics_process(delta: float) -> void:
	_tick_accumulator += delta * profile.logical_fps
	var pending_ticks := mini(int(_tick_accumulator), 8)
	_tick_accumulator -= pending_ticks
	for _tick in range(pending_ticks):
		_elapsed_ticks += 1
		skill_tick()
		if not state_machine.is_in_state(ID):
			break


func skill_tick() -> void:
	if _elapsed_ticks >= int(current_skill.get("duration_ticks", 1)):
		finish_skill()


func finish_skill() -> void:
	state_machine.clear_state(self)


func blocks_horizontal_movement() -> bool:
	return true


func get_horizontal_velocity(facing: float) -> float:
	return float(current_skill.get("move_speed", 0.0)) * signf(facing)


func blocks_gravity() -> bool:
	return bool(current_skill.get("freeze_vertical", false))


func get_vertical_velocity() -> float:
	return float(current_skill.get("vertical_speed", 0.0))


func is_invulnerable() -> bool:
	return bool(current_skill.get("invulnerable", false))


func get_current_skill_id() -> StringName:
	return StringName(current_skill.get("id", &""))


func get_elapsed_ticks() -> int:
	return _elapsed_ticks


func get_effect(effect_id: StringName) -> Dictionary:
	var effects: Dictionary = current_skill.get("effects", {})
	return effects.get(effect_id, {}) as Dictionary


func get_effect_display_offset(effect_id: StringName, fallback: Vector2) -> Vector2:
	if profile == null:
		return fallback
	return SKILL_EFFECT_DISPLAY_CONFIG.get_offset(
		profile.role_id, get_current_skill_id(), effect_id, fallback
	)
