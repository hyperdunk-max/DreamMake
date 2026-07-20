class_name FloatingNumberStyle
extends Resource

## Data-only preset for recreating one Flash number family with Godot text.
## The glyph is rendered once; glow and the two outline rings are composed at
## runtime, so 0-9 do not require separate textures.

@export var style_id: StringName = &"default"
@export var display_name: String = "Default"
@export var font: Font
@export_range(8, 128, 1) var font_size: int = 28
@export var fill_color: Color = Color.WHITE
@export var inner_outline_color: Color = Color.WHITE
@export_range(0, 16, 1) var inner_outline_size: int = 2
@export var outer_outline_color: Color = Color.BLACK
@export_range(0, 24, 1) var outer_outline_size: int = 4
@export var glow_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export_range(0.0, 12.0, 0.25) var glow_radius: float = 3.0
@export_range(0.0, 3.0, 0.05) var glow_strength: float = 0.8
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.65)
@export var shadow_offset: Vector2 = Vector2(1.0, 2.0)
@export_range(0, 12, 1) var shadow_size: int = 1
@export_range(0.1, 4.0, 0.05) var intro_scale: float = 1.35
@export_range(0.01, 1.0, 0.01) var intro_duration: float = 0.12
@export_range(0.0, 200.0, 1.0) var rise_distance: float = 42.0
@export_range(0.05, 3.0, 0.05) var hold_duration: float = 0.55
@export_range(0.05, 2.0, 0.05) var fade_duration: float = 0.28


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if font == null:
		errors.append("font is required")
	if font_size <= 0:
		errors.append("font_size must be positive")
	if outer_outline_size < inner_outline_size:
		errors.append("outer_outline_size must be >= inner_outline_size")
	return errors
