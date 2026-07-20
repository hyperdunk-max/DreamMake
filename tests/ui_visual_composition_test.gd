extends SceneTree

const STYLE_PATHS: PackedStringArray = [
	"res://resources/ui/number_styles/pnum_player_damage.tres",
	"res://resources/ui/number_styles/bunum_recovery.tres",
	"res://resources/ui/number_styles/bulnum_bullet.tres",
	"res://resources/ui/number_styles/hurtnum_damage.tres",
	"res://resources/ui/number_styles/bnum_critical.tres",
	"res://resources/ui/number_styles/num_combo.tres",
]
const SAMPLE_ICON := "res://assets/ui/equipment/qlp.png"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seen_styles: Dictionary = {}
	for path: String in STYLE_PATHS:
		var style := load(path) as FloatingNumberStyle
		_assert(style != null, "Number style should load: %s" % path)
		if style == null:
			continue
		_assert(style.validate().is_empty(), "Number style should validate: %s" % path)
		_assert(not seen_styles.has(style.style_id), "Number style ids must be unique: %s" % style.style_id)
		seen_styles[style.style_id] = true
		var number := FloatingNumber.new()
		root.add_child(number)
		number.configure("12345", style, false)
		await process_frame
		_assert(number.get_style_id() == style.style_id, "FloatingNumber should retain its style id.")
		_assert(number.get_child_count() == 4, "FloatingNumber should compose four text layers, not digit sprites.")
		number.queue_free()

	var provider := InventoryIconProvider.new()
	var item := {
		"id": "qlp",
		"type": "equipment",
		"icon_source": {"texture_path": SAMPLE_ICON},
	}
	var inventory_texture := provider.get_item_icon(item)
	var drop_texture := provider.get_drop_icon(item)
	_assert(inventory_texture != null, "Canonical equipment icon should load.")
	_assert(inventory_texture == drop_texture, "Inventory and drop views must reuse the same Texture2D instance.")

	var inventory_view := EquipmentIconView.new()
	var drop_view := EquipmentIconView.new()
	root.add_child(inventory_view)
	root.add_child(drop_view)
	inventory_view.configure(inventory_texture, "fine", EquipmentIconView.Context.INVENTORY)
	drop_view.configure(drop_texture, "fine", EquipmentIconView.Context.DROP)
	await process_frame
	_assert(inventory_view.get_base_texture() == drop_view.get_base_texture(), "Both equipment contexts must share base pixels.")

	if _failed:
		quit(1)
	else:
		print("PASS: six text styles replace digit sheets and one equipment texture feeds inventory/drop composition.")
		quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("FAIL: %s" % message)
