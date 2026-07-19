extends SceneTree


func _init() -> void:
	call_deferred(&"_capture")


func _capture() -> void:
	if change_scene_to_file("res://scenes/stages/zmxiyou1_stage_1.tscn") != OK:
		quit(1)
		return
	for _frame: int in range(8):
		await process_frame
	var viewport_texture: ViewportTexture = root.get_texture()
	if viewport_texture == null:
		quit(2)
		return
	var image: Image = viewport_texture.get_image()
	var error: Error = image.save_png("res://.godot/zmxiyou1_stage_1_preview.png")
	quit(0 if error == OK else 3)
