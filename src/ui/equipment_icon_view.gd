class_name EquipmentIconView
extends Control

## Composes one canonical transparent equipment texture for two contexts:
## inventory adds a slot/quality frame; world drop removes the frame and adds
## a pulsing glow. The equipment pixels are never duplicated.

enum Context { INVENTORY, DROP }

const DROP_SHADER: Shader = preload("res://shaders/ui/equipment_drop_glow.gdshader")
const QUALITY_COLORS: Dictionary = {
	"common": Color("9a8358"),
	"excellent": Color("55c85a"),
	"fine": Color("54a9e8"),
	"epic": Color("b76be3"),
	"evil": Color("dc5748"),
	"legendary": Color("f1bd43"),
}

var _context: Context = Context.INVENTORY
var _quality: String = "common"
var _background: Panel
var _icon: TextureRect


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_nodes()
	_apply_context()


func configure(texture: Texture2D, quality: String, context: Context) -> void:
	_context = context
	_quality = quality
	_ensure_nodes()
	_icon.texture = texture
	_apply_context()


func set_context(context: Context) -> void:
	_context = context
	_apply_context()


func get_base_texture() -> Texture2D:
	return _icon.texture if _icon != null else null


func _ensure_nodes() -> void:
	if _icon != null:
		return
	_background = Panel.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_icon = TextureRect.new()
	_icon.position = Vector2(6, 6)
	_icon.size = Vector2(52, 52)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)


func _apply_context() -> void:
	if _icon == null:
		return
	if _context == Context.INVENTORY:
		_background.visible = true
		_background.add_theme_stylebox_override("panel", _inventory_style())
		_icon.material = null
	else:
		_background.visible = false
		var material := ShaderMaterial.new()
		material.shader = DROP_SHADER
		material.set_shader_parameter("glow_color", QUALITY_COLORS.get(_quality, QUALITY_COLORS["common"]))
		_icon.material = material


func _inventory_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("21160f")
	style.border_color = Color(QUALITY_COLORS.get(_quality, QUALITY_COLORS["common"]))
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style
