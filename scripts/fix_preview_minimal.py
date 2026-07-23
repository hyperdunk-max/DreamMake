"""Apply minimal effect preview changes to restored script."""
with open("src/debug/enemy_animation_preview.gd", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add effects_layer onready
old = """@onready var preview_world: Node2D = $PreviewWorld
@onready var sprite: AnimatedSprite2D = $PreviewWorld/AnimatedSprite2D
@onready var monster_option: OptionButton"""
new = """@onready var preview_world: Node2D = $PreviewWorld
@onready var sprite: AnimatedSprite2D = $PreviewWorld/AnimatedSprite2D
@onready var effects_layer: Node2D = $PreviewWorld/EffectsLayer
@onready var monster_option: OptionButton"""
content = content.replace(old, new)

# 2. Add _load_effects call in play_action
old2 = 'event_label.text = "帧数'
new2 = '_load_effects(action)\n\tevent_label.text = "帧数'
content = content.replace(old2, new2)

# 3. Add _load_effects method
old3 = "func _on_action_selected(index: int) -> void:"
new3 = """func _load_effects(action: StringName) -> void:
	for child in effects_layer.get_children():
		child.queue_free()
	var spec := _profile.get_spec(action)
	var bullet_sheet := str(spec.get("bullet_sprite_sheet", ""))
	var bullet_json := str(spec.get("bullet_sprite_json", ""))
	if bullet_sheet.is_empty():
		return
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(bullet_sheet)) != OK:
		return
	var texture := ImageTexture.create_from_image(image)
	var file := FileAccess.open(bullet_json, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null:
		return
	var frames_data: Dictionary = data.get("frames", {})
	var sorted_names := PackedStringArray(frames_data.keys())
	sorted_names.sort()
	var effect_sprite := AnimatedSprite2D.new()
	effect_sprite.name = "EffectBullet"
	var sf := SpriteFrames.new()
	sf.add_animation("bullet")
	for fname: String in sorted_names:
		var fi: Dictionary = frames_data[fname]
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(fi.get("x", 0), fi.get("y", 0), fi.get("w", 64), fi.get("h", 64))
		sf.add_frame("bullet", atlas)
	effect_sprite.sprite_frames = sf
	effect_sprite.scale = sprite.scale
	effect_sprite.position = sprite.position
	effects_layer.add_child(effect_sprite)
	effect_sprite.play("bullet")
	event_label.text += "\\n弹道特效"

func _on_action_selected(index: int) -> void:"""
content = content.replace(old3, new3)

with open("src/debug/enemy_animation_preview.gd", "w", encoding="utf-8") as f:
    f.write(content)
print("Done")
