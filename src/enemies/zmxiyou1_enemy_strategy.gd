class_name Zmxiyou1EnemyStrategy
extends RefCounted

## Deterministic adapter for the 24 Hz ActionScript monster decisions.
##
## The strategy only decides actions and source cooldown ticks. AnimatedEnemy
## continues to own rendering, movement and Godot physics queries.

const SOURCE_TICK_RATE := 24.0

const SOURCE_CONFIG := {
	&"M01": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 80.0,
		"vertical_range": 160.0,
		"attack_chance": 50,
		"period": 36,
		"passive_until_hit": true,
	},
	&"M02": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 110.0,
		"vertical_range": 220.0,
		"attack_chance": 50,
		"period": 36,
	},
	&"M03": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 150.0,
		"vertical_range": 300.0,
		"attack_chance": 50,
		"period": 36,
	},
	&"M06": {
		"move_speed": 4.0 * SOURCE_TICK_RATE,
		"attack_range": 250.0,
		"vertical_range": 900.0,
		"cooldowns": {&"attack2": 240},
		"invulnerability_ticks": {&"attack2": 48},
	},
	&"M07": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 110.0,
		"vertical_range": 220.0,
		"attack_chance": 50,
		"period": 36,
	},
	&"M08": {
		"kind": &"flying_melee",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"flying": true,
		"follow_range": 140.0,
		"vertical_tolerance": 90.0,
		"vertical_range": 900.0,
		"target_y_offset": -90.0,
		"vertical_acceleration": 0.5 * SOURCE_TICK_RATE,
		"vertical_max_speed": 4.0 * SOURCE_TICK_RATE,
		"attack_chance": 50,
		"period": 36,
	},
	&"M13": {
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 150.0,
		"vertical_range": 300.0,
		"cooldowns": {&"attack2": 96},
	},
	&"M16": {
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 150.0,
		"vertical_range": 300.0,
		"cooldowns": {&"attack2": 240},
	},
	&"M09": {
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 400.0,
		"cooldowns": {&"attack_fire": 48, &"attack2": 130},
	},
	&"M04": {
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 150.0,
		"period": 24,
		"ranged": &"attack3",
		"skill": &"attack2",
		"normal": &"attack1",
		"cooldowns": {&"attack2": 260, &"attack3": 180},
		"invulnerability_ticks": {&"attack2": 76},
	},
	&"M10": {
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 250.0,
		"period": 24,
		"ranged": &"attack3",
		"skill": &"attack2",
		"normal": &"attack1",
		"cooldowns": {&"attack2": 144, &"attack3": 240},
		"invulnerability_ticks": {&"attack3": 45},
	},
	&"M11": {
		"move_speed": 4.0 * SOURCE_TICK_RATE,
		"attack_range": 150.0,
		"period": 24,
		"ranged": &"attack3",
		"skill": &"attack2",
		"normal": &"attack1",
		"cooldowns": {&"attack2": 100, &"attack3": 264},
		"invulnerability_ticks": {&"attack2": 47},
	},
	&"M14": {
		"kind": &"ranged_keeper",
		"move_speed": 5.0 * SOURCE_TICK_RATE,
		"near_range": 200.0,
		"far_range": 350.0,
		"attack_chance": 40,
		"period": 24,
	},
	&"M15": {
		"kind": &"flying_melee",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"flying": true,
		"follow_range": 150.0,
		"vertical_tolerance": 100.0,
		"vertical_range": 900.0,
		"target_y_offset": -60.0,
		"vertical_acceleration": 0.5 * SOURCE_TICK_RATE,
		"vertical_max_speed": 4.0 * SOURCE_TICK_RATE,
		"attack_chance": 50,
		"period": 36,
	},
	&"M17": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 400.0,
		"vertical_range": 800.0,
		"attack_chance": 60,
		"period": 36,
	},
	&"M18": {
		"move_speed": 6.0 * SOURCE_TICK_RATE,
		"attack_range": 450.0,
		"flying": true,
		"cooldowns": {&"attack2": 96},
		"follow_range": 250.0,
		"vertical_tolerance": 50.0,
		"vertical_range": 900.0,
		"target_y_offset": -60.0,
		"vertical_acceleration": 0.5 * SOURCE_TICK_RATE,
		"vertical_max_speed": 4.0 * SOURCE_TICK_RATE,
		"invulnerability_ticks": {&"attack2": 30},
	},
	&"M19": {
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 150.0,
		"period": 24,
		"cooldowns": {&"attack2": 480, &"attack3": 360},
		"invulnerability_ticks": {&"attack2": 20, &"attack3": 18},
	},
	&"M20": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 200.0,
		"vertical_range": 400.0,
		"attack_chance": 50,
		"period": 36,
	},
	&"M21": {
		"kind": &"stationary",
		"move_speed": 0.0,
	},
	&"M22": {
		"kind": &"source_controller",
		"move_speed": 13.0 * SOURCE_TICK_RATE,
	},
	&"M23": {
		"move_speed": 5.0 * SOURCE_TICK_RATE,
		"cooldowns": {
			&"attack2": 360, &"attack3": 360, &"attack4": 360, &"attack5": 360,
		},
		"invulnerability_ticks": {&"attack2": 60, &"attack3": 67, &"attack4": 54},
	},
	&"M24": {
		"move_speed": 0.0,
		"flying": true,
	},
	&"M26": {
		"move_speed": 4.0 * SOURCE_TICK_RATE,
		"cooldowns_low": {&"attack2": 700, &"attack3": 500, &"attack4": 400},
		"cooldowns_high": {&"attack2": 550, &"attack3": 400, &"attack4": 300},
		"invulnerability_ticks": {&"attack2": 90, &"attack3": 85, &"attack4": 24},
	},
	&"M25": {
		"kind": &"generic_ground",
		"move_speed": 3.0 * SOURCE_TICK_RATE,
		"attack_range": 110.0,
		"vertical_range": 220.0,
		"attack_chance": 50,
		"period": 36,
	},
	&"M27": {
		"kind": &"stationary",
		"move_speed": 0.0,
	},
}


static func has_reviewed_strategy(profile: EnemyAnimationProfile) -> bool:
	return profile != null and SOURCE_CONFIG.has(profile.source_monster_id)


static func get_move_speed(profile: EnemyAnimationProfile, fallback: float) -> float:
	var config := _config(profile)
	return float(config.get("move_speed", fallback))


static func is_flying(profile: EnemyAnimationProfile) -> bool:
	return bool(_config(profile).get("flying", false))


static func get_invulnerability_ticks(profile: EnemyAnimationProfile, action: StringName) -> int:
	var invulnerability: Dictionary = _config(profile).get("invulnerability_ticks", {})
	return maxi(0, int(invulnerability.get(_base_action(action), 0)))


static func get_source_context_stats(
	profile: EnemyAnimationProfile, source_stage: int, source_level: int
) -> Dictionary:
	if profile == null:
		return {}
	match profile.source_monster_id:
		&"M03":
			var boss_variant := source_stage == 1 and source_level == 1
			return {"max_health": 900 if boss_variant else 300, "defense": 5, "is_boss": boss_variant}
		&"M17":
			var boss_variant := source_stage == 3 and source_level == 1
			return {"max_health": 4800 if boss_variant else 1600, "defense": 70, "is_boss": boss_variant}
		&"M27":
			var total_stage := (source_stage - 1) * 3 + source_level if source_stage < 4 else 10
			return {
				"max_health": 20 * total_stage * total_stage * total_stage
				+ 20 * total_stage * total_stage
				+ 100,
				"defense": 25,
				"is_boss": false,
				"total_stage": total_stage,
			}
	return {}


static func get_cooldown_ticks(
	profile: EnemyAnimationProfile,
	action: StringName,
	fallback_seconds: float,
	high_level_variant := false
) -> int:
	var config := _config(profile)
	var cooldowns: Dictionary
	if profile != null and profile.source_monster_id == &"M26":
		cooldowns = config.get("cooldowns_high" if high_level_variant else "cooldowns_low", {})
	else:
		cooldowns = config.get("cooldowns", {})
	var base_action := _cooldown_key(profile, action)
	if cooldowns.has(base_action):
		return maxi(0, int(cooldowns[base_action]))
	return maxi(0, roundi(fallback_seconds * SOURCE_TICK_RATE))


static func get_cooldown_key(profile: EnemyAnimationProfile, action: StringName) -> StringName:
	return _cooldown_key(profile, action)


static func decide(
	profile: EnemyAnimationProfile,
	distance: float,
	source_tick: int,
	cooldowns: Dictionary,
	phase: int,
	high_level_variant: bool,
	rng: RandomNumberGenerator,
	runtime_flags: Dictionary = {}
) -> Dictionary:
	if profile == null:
		return {}
	match profile.source_monster_id:
		&"M01", &"M02", &"M03", &"M07", &"M17", &"M20", &"M25":
			return _decide_generic_ground(
				profile,
				distance,
				float(runtime_flags.get("vertical_distance", 0.0)),
				source_tick,
				rng,
				runtime_flags
			)
		&"M06", &"M13", &"M16":
			return _decide_periodic_ground_enemy(
				profile,
				distance,
				float(runtime_flags.get("vertical_distance", 0.0)),
				source_tick,
				cooldowns
			)
		&"M09":
			return _decide_m09(distance, source_tick, cooldowns, bool(runtime_flags.get("flying", false)), rng)
		&"M04", &"M10", &"M11":
			return _decide_periodic_boss(profile, distance, source_tick, cooldowns)
		&"M08", &"M15":
			return _decide_flying_melee(
				profile,
				distance,
				float(runtime_flags.get("vertical_distance", 0.0)),
				float(runtime_flags.get("vertical_delta", 0.0)),
				source_tick,
				rng,
				bool(runtime_flags.get("target_acquired", false))
			)
		&"M14":
			return _decide_m14(
				distance, source_tick, rng, bool(runtime_flags.get("target_acquired", false))
			)
		&"M18":
			return _decide_m18(
				distance,
				float(runtime_flags.get("vertical_distance", 0.0)),
				float(runtime_flags.get("vertical_delta", 0.0)),
				source_tick,
				cooldowns,
				rng
			)
		&"M19":
			return _decide_m19(distance, source_tick, cooldowns, phase)
		&"M23":
			return _decide_m23(distance, cooldowns, rng)
		&"M21", &"M22", &"M24", &"M27":
			return {"reviewed": true, "move": false}
		&"M26":
			return _decide_m26(distance, source_tick, cooldowns, high_level_variant, rng)
	return {}


static func _decide_generic_ground(
	profile: EnemyAnimationProfile,
	distance: float,
	vertical_distance: float,
	source_tick: int,
	rng: RandomNumberGenerator,
	runtime_flags: Dictionary
) -> Dictionary:
	var config := _config(profile)
	if bool(config.get("passive_until_hit", false)) and not bool(runtime_flags.get("provoked", false)):
		return {"reviewed": true, "patrol": true, "move": false}
	if not bool(runtime_flags.get("target_acquired", false)):
		return {"reviewed": true, "patrol": true, "move": false}
	if vertical_distance > float(config["vertical_range"]):
		return {"reviewed": true, "patrol": true, "move": false}
	if distance > float(config["attack_range"]):
		return {"reviewed": true, "move": true}
	if source_tick % int(config["period"]) != 0:
		return {"reviewed": true, "move": false}
	if rng.randi_range(0, 99) < int(config["attack_chance"]):
		return {"reviewed": true, "action": &"attack1", "move": false}
	return {"reviewed": true, "move": false}


static func _decide_periodic_ground_enemy(
	profile: EnemyAnimationProfile,
	distance: float,
	vertical_distance: float,
	source_tick: int,
	cooldowns: Dictionary
) -> Dictionary:
	var config := _config(profile)
	if vertical_distance > float(config["vertical_range"]) or distance > float(config["attack_range"]):
		return {"reviewed": true, "move": true}
	if source_tick % 24 != 0:
		return {"reviewed": true, "move": false}
	if _is_ready(cooldowns, &"attack2"):
		return {"reviewed": true, "action": &"attack2", "move": false}
	return {"reviewed": true, "action": &"attack1", "move": false}


static func _decide_flying_melee(
	profile: EnemyAnimationProfile,
	distance: float,
	vertical_distance: float,
	vertical_delta: float,
	source_tick: int,
	rng: RandomNumberGenerator,
	target_acquired: bool
) -> Dictionary:
	var config := _config(profile)
	if not target_acquired:
		return {"reviewed": true, "patrol": true, "move": false, "vertical_stop": true}
	if (
		vertical_distance > float(config["vertical_range"])
		or distance > float(config["follow_range"])
		or vertical_distance > float(config["vertical_tolerance"])
	):
		return {
			"reviewed": true,
			"move": true,
			"flight_vertical_target_delta": vertical_delta + float(config["target_y_offset"]),
			"vertical_acceleration": float(config["vertical_acceleration"]),
			"vertical_max_speed": float(config["vertical_max_speed"]),
		}
	if source_tick % int(config["period"]) == 0 and rng.randi_range(0, 99) < int(config["attack_chance"]):
		return {"reviewed": true, "action": &"attack1", "move": false, "vertical_stop": true}
	return {"reviewed": true, "move": false, "vertical_stop": true}


static func _decide_m14(
	distance: float, source_tick: int, rng: RandomNumberGenerator, target_acquired: bool
) -> Dictionary:
	if not target_acquired:
		return {"reviewed": true, "patrol": true, "move": false}
	if source_tick % 24 == 0:
		if rng.randi_range(0, 99) < 40:
			return {"reviewed": true, "action": &"attack1", "move": false}
		return {"reviewed": true, "move": false}
	if distance <= 200.0:
		return {"reviewed": true, "move": true, "move_away": true}
	if distance >= 350.0:
		return {"reviewed": true, "move": true}
	return {"reviewed": true, "move": false}


static func _decide_m09(
	distance: float,
	source_tick: int,
	cooldowns: Dictionary,
	flying: bool,
	rng: RandomNumberGenerator
) -> Dictionary:
	if distance > 400.0:
		if flying and source_tick % 24 == 0 and rng.randi_range(0, 99) < 50 and _is_ready(cooldowns, &"attack_fire"):
			return {"reviewed": true, "action": &"attack1", "move": false}
		return {"reviewed": true, "move": true}
	if source_tick % 24 != 0:
		return {"reviewed": true, "move": true}
	if distance <= 150.0:
		if not flying:
			return {"reviewed": true, "action": &"attack4", "move": false}
		return {"reviewed": true, "move": false}
	if rng.randf() < 0.3:
		if _is_ready(cooldowns, &"attack2"):
			return {"reviewed": true, "action": &"attack2", "move": false}
	elif _is_ready(cooldowns, &"attack_fire"):
		return {"reviewed": true, "action": &"attack1" if flying else &"attack3", "move": false}
	return {"reviewed": true, "move": false}


static func _decide_periodic_boss(
	profile: EnemyAnimationProfile, distance: float, source_tick: int, cooldowns: Dictionary
) -> Dictionary:
	var config := _config(profile)
	if distance > float(config["attack_range"]):
		var ranged := StringName(config["ranged"])
		return _attack_or_move(ranged, cooldowns)
	if source_tick % int(config["period"]) != 0:
		return {"reviewed": true, "move": false}
	var skill := StringName(config["skill"])
	if _is_ready(cooldowns, skill):
		return {"reviewed": true, "action": skill, "move": false}
	return {"reviewed": true, "action": StringName(config["normal"]), "move": false}


static func _decide_m18(
	distance: float,
	vertical_distance: float,
	vertical_delta: float,
	source_tick: int,
	cooldowns: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	# Source followHero keeps closing until horizontal <= 250 and vertical <= 50,
	# accelerating toward 60 px above the target by 0.5 px/tick up to 4 px/tick.
	if distance > 250.0 or vertical_distance > 50.0:
		return {
			"reviewed": true,
			"move": true,
			"flight_vertical_target_delta": vertical_delta - 60.0,
			"vertical_acceleration": 0.5 * SOURCE_TICK_RATE,
			"vertical_max_speed": 4.0 * SOURCE_TICK_RATE,
		}
	if source_tick % 24 != 0:
		return {"reviewed": true, "move": false, "vertical_stop": true}
	if rng.randi_range(0, 99) < 50:
		return {"reviewed": true, "action": &"attack1", "move": false, "vertical_stop": true}
	if _is_ready(cooldowns, &"attack2"):
		return {"reviewed": true, "action": &"attack2", "move": false, "vertical_stop": true}
	return {"reviewed": true, "move": false, "vertical_stop": true}


static func _decide_m19(
	distance: float, source_tick: int, cooldowns: Dictionary, phase: int
) -> Dictionary:
	var suffix := "_2" if phase >= 2 else "_1"
	if distance > 150.0:
		return _attack_or_move(StringName("attack3%s" % suffix), cooldowns)
	if source_tick % 24 != 0:
		return {"reviewed": true, "move": false}
	var skill := StringName("attack2%s" % suffix)
	if _is_ready(cooldowns, skill):
		return {"reviewed": true, "action": skill, "move": false}
	return {"reviewed": true, "action": StringName("attack1%s" % suffix), "move": false}


static func _decide_m23(
	distance: float, cooldowns: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	if distance <= 80.0:
		if _is_ready(cooldowns, &"attack5"):
			return {"reviewed": true, "action": &"attack5", "move": false}
		return {"reviewed": true, "move": false}
	if distance <= 100.0:
		if _is_ready(cooldowns, &"attack4"):
			return {"reviewed": true, "action": &"attack4", "move": false}
		return _probable_normal_attack(rng)
	if distance <= 200.0:
		var attack2_ready := _is_ready(cooldowns, &"attack2")
		var attack3_ready := _is_ready(cooldowns, &"attack3")
		if attack2_ready and attack3_ready:
			return {
				"reviewed": true,
				"action": &"attack2" if rng.randf() < 0.5 else &"attack3",
				"move": false,
			}
		if attack2_ready:
			return {"reviewed": true, "action": &"attack2", "move": false}
		if attack3_ready:
			return {"reviewed": true, "action": &"attack3", "move": false}
		return _probable_normal_attack(rng)
	return {"reviewed": true, "move": true}


static func _decide_m26(
	distance: float,
	source_tick: int,
	cooldowns: Dictionary,
	high_level_variant: bool,
	rng: RandomNumberGenerator
) -> Dictionary:
	var source_attack_chance := 20 if high_level_variant else 40
	if distance <= 100.0:
		if _is_ready(cooldowns, &"attack4"):
			return {"reviewed": true, "action": &"attack4", "move": false}
		if source_tick % 36 == 0 and rng.randi_range(0, 99) < source_attack_chance:
			return {"reviewed": true, "action": &"attack1", "move": false}
		return {"reviewed": true, "move": true}
	if distance <= 450.0:
		var attack2_ready := _is_ready(cooldowns, &"attack2")
		var attack3_ready := _is_ready(cooldowns, &"attack3")
		if attack2_ready and attack3_ready:
			return {
				"reviewed": true,
				"action": &"attack2" if rng.randf() < 0.5 else &"attack3",
				"move": false,
			}
		if attack2_ready:
			return {"reviewed": true, "action": &"attack2", "move": false}
		if attack3_ready:
			return {"reviewed": true, "action": &"attack3", "move": false}
		if source_tick % 24 == 0 and rng.randi_range(0, 99) < source_attack_chance:
			return {"reviewed": true, "action": &"attack1", "move": false}
	return {"reviewed": true, "move": true}


static func _attack_or_move(action: StringName, cooldowns: Dictionary) -> Dictionary:
	if _is_ready(cooldowns, action):
		return {"reviewed": true, "action": action, "move": false}
	return {"reviewed": true, "move": true}


static func _probable_normal_attack(rng: RandomNumberGenerator) -> Dictionary:
	if rng.randf() < 0.8:
		return {"reviewed": true, "action": &"attack1", "move": false}
	return {"reviewed": true, "move": true}


static func _is_ready(cooldowns: Dictionary, action: StringName) -> bool:
	return int(cooldowns.get(action, cooldowns.get(_base_action(action), 0))) <= 0


static func _base_action(action: StringName) -> StringName:
	var text := str(action)
	if text.ends_with("_1") or text.ends_with("_2"):
		text = text.left(-2)
	return StringName(text)


static func _cooldown_key(profile: EnemyAnimationProfile, action: StringName) -> StringName:
	var base_action := _base_action(action)
	if profile != null and profile.source_monster_id == &"M09" and base_action in [&"attack1", &"attack3"]:
		return &"attack_fire"
	return base_action


static func _config(profile: EnemyAnimationProfile) -> Dictionary:
	if profile == null:
		return {}
	return SOURCE_CONFIG.get(profile.source_monster_id, {})
