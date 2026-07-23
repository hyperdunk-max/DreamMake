class_name AnimatedEnemy
extends SandbagEnemy

## Animated monster with animation tree + basic AI.
## Uses EnemyAnimationProfile for sprite frames.

enum State { IDLE, WALK, ATTACK, HURT, DEATH }

const WALK_SPEED: float = 60.0
const ATTACK_RANGE: float = 48.0
const ATTACK_COOLDOWN: float = 1.5
const HURT_DURATION: float = 0.35

var _state: State = State.IDLE
var _attack_timer: float = 0.0
var _hurt_timer: float = 0.0
var _current_animation: StringName = &"idle"
var _player_ref: CharacterBody2D = null
var _facing: int = -1  # -1 = left, +1 = right

const BULLET_SCENE := preload("res://scenes/effects/enemy_bullet.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea

var _bullet_frames: Dictionary = {}  # bullet_name -> SpriteFrames
var _event_dispatcher: EnemyAnimationEventDispatcher


func _ready() -> void:
	super._ready()
	if sprite != null and animated_sprite != null:
		sprite.visible = false

	if animated_sprite != null and definition != null and definition.animation_profile != null:
		_load_animations()
		_switch_state(State.IDLE)

	if attack_area != null:
		attack_area.body_entered.connect(_on_attack_area_body_entered)

	_event_dispatcher = EnemyAnimationEventDispatcher.new()
	add_child(_event_dispatcher)
	_event_dispatcher.source_event.connect(_on_source_event)
	if definition != null and definition.animation_profile != null:
		_event_dispatcher.bind(animated_sprite, definition.animation_profile)

	_preload_bullets()


func _load_animations() -> void:
	var profile := definition.animation_profile
	animated_sprite.sprite_frames = profile.build_sprite_frames()
	animated_sprite.scale = definition.visual_scale
	animated_sprite.position = definition.visual_offset
	# Apply initial sprite_offset from default animation
	if profile.actions.has(profile.default_animation):
		var spec := profile.get_spec(profile.default_animation)
		if not spec.is_empty():
			animated_sprite.position = definition.visual_offset + Vector2(spec.get("sprite_offset", Vector2.ZERO))


func _physics_process(delta: float) -> void:
	# Physics (gravity, friction)
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)

	# Timers
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	hit_flash_seconds = maxf(0.0, hit_flash_seconds - delta)
	stun_seconds = maxf(0.0, stun_seconds - delta)

	# Flash
	animated_sprite.modulate = Color(1.0, 0.45, 0.45) if hit_flash_seconds > 0.0 else Color.WHITE

	if health <= 0 and _state != State.DEATH:
		_switch_state(State.DEATH)

	# AI
	_update_ai(delta)

	move_and_slide()


func _update_ai(_delta: float) -> void:
	match _state:
		State.DEATH:
			return

		State.HURT:
			_hurt_timer -= _delta
			if _hurt_timer <= 0.0 and health > 0:
				_switch_state(State.IDLE)
			return

		State.ATTACK:
			# Stay in attack until animation finishes
			if not animated_sprite.is_playing() or animated_sprite.animation != _current_animation:
				_switch_state(State.IDLE)
			return

		State.IDLE, State.WALK:
			_find_player()
			if _player_ref == null:
				_switch_state(State.IDLE)
				return

			var to_player := _player_ref.global_position.x - global_position.x
			var dist := absf(to_player)

			# Face player
			_facing = -1 if to_player < 0 else 1
			animated_sprite.flip_h = _facing > 0

			# State transitions
			if dist <= ATTACK_RANGE and _attack_timer <= 0.0:
				_switch_state(State.ATTACK)
			elif dist > ATTACK_RANGE:
				_switch_state(State.WALK)
				velocity.x = WALK_SPEED * _facing
			else:
				_switch_state(State.IDLE)


func _switch_state(new_state: State) -> void:
	if _state == State.DEATH:
		return
	_state = new_state

	match new_state:
		State.IDLE:
			_play_anim(&"idle")
			velocity.x = 0.0
		State.WALK:
			_play_anim(&"move")
		State.ATTACK:
			_play_anim(&"attack3")
			_attack_timer = ATTACK_COOLDOWN
			velocity.x = 0.0
			_check_attack_hit()
		State.HURT:
			_play_anim(&"hurt")
			_hurt_timer = HURT_DURATION
			velocity.x = 0.0
		State.DEATH:
			_play_anim(&"death")
			velocity.x = 0.0
			collision_shape.set_deferred(&"disabled", true)


func _play_anim(action: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(action):
		# Fallback: use idle for missing animations
		if action != &"idle" and animated_sprite.sprite_frames.has_animation(&"idle"):
			action = &"idle"
		else:
			return
	_current_animation = action
	animated_sprite.play(action)
	# Apply per-action sprite_offset from animation profile
	if definition != null and definition.animation_profile != null:
		var spec := definition.animation_profile.get_spec(action)
		if not spec.is_empty():
			animated_sprite.position = Vector2(spec.get("sprite_offset", Vector2.ZERO))


func _find_player() -> void:
	if _player_ref != null and is_instance_valid(_player_ref):
		return
	# Find player by group
	var players := get_tree().get_nodes_in_group(&"players")
	if not players.is_empty():
		_player_ref = players[0] as CharacterBody2D


func take_hit(damage: int, impulse: Vector2) -> void:
	if health <= 0:
		return
	super.take_hit(damage, impulse)
	if health > 0:
		_switch_state(State.HURT)
	else:
		_switch_state(State.DEATH)


func _check_attack_hit() -> void:
	if attack_area == null:
		return
	for body: Node2D in attack_area.get_overlapping_bodies():
		if body.is_in_group(&"players"):
			var player := body as PropertyActor2D
			if player != null and player.has_method(&"take_hit"):
				var dmg := get_effective_attack()
				var knockback := Vector2(100.0 * _facing, -80.0)
				player.take_hit(dmg, knockback)


func _on_attack_area_body_entered(body: Node2D) -> void:
	if _state != State.ATTACK:
		return
	if body.is_in_group(&"players"):
		var player := body as PropertyActor2D
		if player != null and player.has_method(&"take_hit"):
			var dmg := get_effective_attack()
			var knockback := Vector2(100.0 * _facing, -80.0)
			player.take_hit(dmg, knockback)


## --- Bullet / Projectile System ---

func _preload_bullets() -> void:
	# Load bullet sprite sheets defined in profile
	if definition == null or definition.animation_profile == null:
		return
	for action: StringName in definition.animation_profile.actions:
		var spec := definition.animation_profile.get_spec(action)
		var bullet_sheet := str(spec.get("bullet_sprite_sheet", ""))
		var bullet_json := str(spec.get("bullet_sprite_json", ""))
		if bullet_sheet.is_empty() or bullet_json.is_empty():
			continue
		_load_bullet_frames(action, bullet_sheet, bullet_json)


func _load_bullet_frames(bullet_name: String, sheet_path: String, json_path: String) -> void:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(sheet_path)) != OK:
		return
	var texture := ImageTexture.create_from_image(image)
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null:
		return
	var frames_data: Dictionary = data.get("frames", {})
	var sorted_names := PackedStringArray(frames_data.keys())
	sorted_names.sort()
	var sf := SpriteFrames.new()
	sf.add_animation(bullet_name)
	for fname: String in sorted_names:
		var fi: Dictionary = frames_data[fname]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(fi.get("x", 0), fi.get("y", 0), fi.get("w", 64), fi.get("h", 64))
		sf.add_frame(bullet_name, atlas)
	_bullet_frames[bullet_name] = sf


func _on_source_event(action: StringName, event: Dictionary) -> void:
	var event_id: String = event.get("id", "")
	# Check for bullet spawn events (id contains "bullet" or "hit" spawn type)
	if "bullet" in event_id or "doHit" in event_id or "hit" in event_id:
		_spawn_bullet(action, event)


func _spawn_bullet(action: StringName, _event: Dictionary) -> void:
	# Determine which bullet to spawn based on current action
	var bullet_name := str(action)  # e.g. "attack3"

	var sf: SpriteFrames = _bullet_frames.get(bullet_name, null)
	if sf == null:
		# Try common names
		for key in _bullet_frames:
			sf = _bullet_frames[key]
			bullet_name = key
			break
	if sf == null:
		return

	# Read bullet parameters from the action spec, with defaults for backward compatibility.
	var spec := definition.animation_profile.get_spec(action)
	var bullet_damage := int(spec.get("bullet_damage", 20))
	var bullet_knockback := Vector2(spec.get("bullet_knockback", Vector2(100, -80)))
	var bullet_hit_max := int(spec.get("bullet_hit_max_count", 40))
	var bullet_collision := Vector2(spec.get("bullet_collision_size", Vector2(80, 80)))

	var bullet = BULLET_SCENE.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = global_position
	bullet.configure(sf, bullet_name, _facing, bullet_damage, bullet_knockback, bullet_hit_max, bullet_collision)

