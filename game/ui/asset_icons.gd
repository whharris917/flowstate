class_name AssetIcons
extends Node
## Renders catalog assets into thumbnail textures using offscreen
## SubViewports — the real geometry, lit and framed, for the build
## menu's cards. Generation is fire-and-forget at startup; icon()
## returns null until an asset's render lands (cards fill in as they
## arrive). Skipped entirely headless.

const SIZE := 168

var _icons: Dictionary = {}   # type_id -> Texture2D

## A render landed: whatever shows icons can fill in (the hotbar sits
## on screen from the first frame, before any has).
signal landed(type_id: String)


func icon(type_id: String) -> Texture2D:
	return _icons.get(type_id)


func generate(type_ids: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for type_id: String in type_ids:
		if not _icons.has(type_id):
			_icons[type_id] = await _render(type_id)
			landed.emit(type_id)


func _render(type_id: String) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var preview := AssetPreview.build(type_id)
	viewport.add_child(preview)
	var aabb := AssetPreview.bounds(preview)
	var center := aabb.get_center()
	var radius := maxf(aabb.size.length() / 2.0, 0.4)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = center + Vector3(1.0, 0.65, 1.0).normalized() * radius * 2.1
	camera.look_at(center, Vector3.UP)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45, 30, 0)
	key_light.light_energy = 1.4
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15, -140, 0)
	fill_light.light_energy = 0.5
	viewport.add_child(fill_light)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return ImageTexture.create_from_image(image)
