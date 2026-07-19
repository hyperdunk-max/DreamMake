class_name InventoryIconProvider
extends RefCounted

## Creates presentation textures and caches them. Equipment/portrait pixels come
## directly from the extracted Flash atlases already selected by the project.

var _cache: Dictionary = {}


func get_item_icon(item: Dictionary) -> Texture2D:
	var item_id: String = str(item.get("id", ""))
	if _cache.has(item_id):
		return _cache[item_id] as Texture2D
	var icon_source: Dictionary = item.get("icon_source", {})
	var atlas: Texture2D = icon_source.get("atlas") as Texture2D
	var frame_size: Vector2i = Vector2i(icon_source.get("frame_size", Vector2i.ZERO))
	var texture: Texture2D
	if atlas != null and frame_size.x > 0 and frame_size.y > 0:
		texture = crop_flash_frame(atlas, frame_size)
	if texture == null:
		texture = _make_fallback_icon(item_id, str(item.get("type", "")))
	_cache[item_id] = texture
	return texture


func get_character_portrait(body_atlas: Texture2D, weapon_atlas: Texture2D, frame_size: Vector2i) -> Texture2D:
	var body_path: String = body_atlas.resource_path if body_atlas != null else ""
	var weapon_path: String = weapon_atlas.resource_path if weapon_atlas != null else ""
	var cache_key: String = "portrait|%s|%s|%s" % [body_path, weapon_path, frame_size]
	if _cache.has(cache_key):
		return _cache[cache_key] as Texture2D
	var combined: Image = Image.create(frame_size.x, frame_size.y, false, Image.FORMAT_RGBA8)
	combined.fill(Color.TRANSPARENT)
	for atlas: Texture2D in [body_atlas, weapon_atlas]:
		if atlas == null:
			continue
		var source: Image = atlas.get_image()
		if source == null:
			continue
		var width: int = mini(frame_size.x, source.get_width())
		var height: int = mini(frame_size.y, source.get_height())
		combined.blend_rect(source, Rect2i(0, 0, width, height), Vector2i.ZERO)
	var result: Texture2D = _texture_from_used_rect(combined, 6)
	_cache[cache_key] = result
	return result


func crop_flash_frame(atlas: Texture2D, frame_size: Vector2i) -> Texture2D:
	var image: Image = atlas.get_image()
	if image == null:
		return null
	var width: int = mini(frame_size.x, image.get_width())
	var height: int = mini(frame_size.y, image.get_height())
	var frame: Image = image.get_region(Rect2i(0, 0, width, height))
	return _texture_from_used_rect(frame, 4)


func clear_cache() -> void:
	_cache.clear()


func _texture_from_used_rect(image: Image, padding: int) -> Texture2D:
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var padded: Rect2i = used.grow(padding).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return ImageTexture.create_from_image(image.get_region(padded))


func _make_fallback_icon(item_id: String, item_type: String) -> Texture2D:
	var image: Image = Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var border: Color = Color("4b2a17")
	if item_id.contains("health"):
		_draw_bottle(image, Color("d94a3f"), border)
	elif item_id.contains("mana"):
		_draw_bottle(image, Color("397bd8"), border)
	elif item_id.contains("wood") or item_id.contains("sandalwood"):
		image.fill_rect(Rect2i(8, 14, 32, 20), border)
		image.fill_rect(Rect2i(10, 16, 28, 16), Color("b87937"))
		image.fill_rect(Rect2i(14, 19, 20, 2), Color("e0b063"))
	elif item_id.contains("iron") or item_id.contains("stone"):
		image.fill_rect(Rect2i(9, 11, 30, 27), border)
		image.fill_rect(Rect2i(12, 14, 24, 21), Color("87909e"))
		image.fill_rect(Rect2i(15, 16, 12, 4), Color("c5ced8"))
	else:
		var fill: Color = Color("8d65b5") if item_type == "material" else Color("b28b45")
		image.fill_rect(Rect2i(8, 8, 32, 32), border)
		image.fill_rect(Rect2i(11, 11, 26, 26), fill)
	return ImageTexture.create_from_image(image)


func _draw_bottle(image: Image, liquid: Color, border: Color) -> void:
	image.fill_rect(Rect2i(19, 5, 10, 8), border)
	image.fill_rect(Rect2i(21, 7, 6, 8), Color("e9d6a2"))
	image.fill_rect(Rect2i(13, 13, 22, 28), border)
	image.fill_rect(Rect2i(16, 16, 16, 22), Color("f3e4bd"))
	image.fill_rect(Rect2i(17, 25, 14, 12), liquid)
	image.fill_rect(Rect2i(18, 18, 4, 6), Color(1.0, 1.0, 1.0, 0.7))
