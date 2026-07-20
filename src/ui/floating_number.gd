class_name FloatingNumber
extends Control

## Runtime text replacement for the six Flash number bitmap families.
## Four labels produce soft glow + black outer ring + white inner ring + fill.

const GLOW_SHADER: Shader = preload("res://shaders/ui/soft_text_glow.gdshader")

@export var style: FloatingNumberStyle:
	set(value):
		style = value
		if is_node_ready():
			_apply_style()
@export var display_text: String = "0":
	set(value):
		display_text = value
		if is_node_ready():
			_sync_text_and_size()

var _glow_label: Label
var _outer_label: Label
var _inner_label: Label
var _fill_label: Label
var _active_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_ensure_layers()
	_apply_style()
	_sync_text_and_size()


func configure(text_value: String, number_style: FloatingNumberStyle, animate: bool = false) -> void:
	display_text = text_value
	style = number_style
	if not is_node_ready():
		return
	_apply_style()
	_sync_text_and_size()
	if animate:
		play_and_free()


func play_and_free() -> void:
	if style == null:
		return
	if _active_tween != null:
		_active_tween.kill()
	var origin := position
	pivot_offset = size * 0.5
	scale = Vector2.ONE * style.intro_scale
	modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "scale", Vector2.ONE, style.intro_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "modulate:a", 1.0, style.intro_duration)
	_active_tween.set_parallel(false)
	_active_tween.tween_interval(style.hold_duration)
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "position", origin - Vector2(0.0, style.rise_distance), style.fade_duration)
	_active_tween.tween_property(self, "modulate:a", 0.0, style.fade_duration)
	_active_tween.set_parallel(false)
	_active_tween.tween_callback(queue_free)


func get_style_id() -> StringName:
	return style.style_id if style != null else &""


func _ensure_layers() -> void:
	if _fill_label != null:
		return
	_glow_label = _make_label("Glow")
	_outer_label = _make_label("OuterOutline")
	_inner_label = _make_label("InnerOutline")
	_fill_label = _make_label("Fill")


func _make_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = false
	add_child(label)
	return label


func _apply_style() -> void:
	_ensure_layers()
	if style == null:
		return
	_glow_label.label_settings = _make_settings(style.glow_color, style.glow_color, style.outer_outline_size + 2)
	var glow_material := ShaderMaterial.new()
	glow_material.shader = GLOW_SHADER
	glow_material.set_shader_parameter("glow_color", style.glow_color)
	glow_material.set_shader_parameter("radius_px", style.glow_radius)
	glow_material.set_shader_parameter("strength", style.glow_strength)
	_glow_label.material = glow_material

	_outer_label.label_settings = _make_settings(
		style.outer_outline_color,
		style.outer_outline_color,
		style.outer_outline_size,
		true
	)
	_inner_label.label_settings = _make_settings(
		style.inner_outline_color,
		style.inner_outline_color,
		style.inner_outline_size
	)
	_fill_label.label_settings = _make_settings(style.fill_color, style.fill_color, 0)
	_sync_text_and_size()


func _make_settings(color: Color, outline_color: Color, outline_size: int, with_shadow: bool = false) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = style.font
	settings.font_size = style.font_size
	settings.font_color = color
	settings.outline_color = outline_color
	settings.outline_size = outline_size
	if with_shadow:
		settings.shadow_color = style.shadow_color
		settings.shadow_offset = style.shadow_offset
		settings.shadow_size = style.shadow_size
	return settings


func _sync_text_and_size() -> void:
	if _fill_label == null:
		return
	for label: Label in [_glow_label, _outer_label, _inner_label, _fill_label]:
		label.text = display_text
	var current_font_size := style.font_size if style != null else 28
	var outline_padding := style.outer_outline_size * 2 if style != null else 8
	var width := maxi(54, roundi(display_text.length() * current_font_size * 0.72) + outline_padding * 2 + 18)
	var height := maxi(48, current_font_size + outline_padding * 2 + 18)
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size
	for label: Label in [_glow_label, _outer_label, _inner_label, _fill_label]:
		label.position = Vector2.ZERO
		label.size = size
	pivot_offset = size * 0.5
