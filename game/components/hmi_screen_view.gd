class_name HmiScreenView
extends Node3D
## A freestanding operator screen: a SubViewport renders any Control
## and an emissive quad shows it in the world, framed and on two posts.
## The Control decides what is on the screen; this node only stands it
## up. The node sits at eye height (local y 1.6, ~1.68 world) so the
## posts reach the floor.

var panel: Control
var _describe: String
var _title_label: Label3D
var _title: String


func setup(panel_: Control, title: String, px: Vector2i, width_m: float, describe_text: String) -> void:
	panel = panel_
	_describe = describe_text
	var h := width_m * float(px.y) / float(px.x)
	var dark := ViewUtil.flat(Color(0.16, 0.16, 0.17))
	ViewUtil.box(self, Vector3(width_m + 0.12, h + 0.12, 0.08), Vector3(0, 0, -0.045), dark)

	var viewport := SubViewport.new()
	viewport.size = px
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(panel)

	var quad := QuadMesh.new()
	quad.size = Vector2(width_m, h)
	var screen := MeshInstance3D.new()
	screen.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = viewport.get_texture()
	mat.emission_energy_multiplier = 0.35
	screen.material_override = mat
	add_child(screen)

	_title = title
	_title_label = ViewUtil.label(self, title, Vector3(0, h / 2.0 + 0.22, 0))
	_refresh_title()
	ViewUtil.interact_body(self, Vector3(width_m + 0.15, h + 0.15, 0.2), Vector3.ZERO)
	var stand := ViewUtil.flat(Color(0.16, 0.17, 0.19))
	ViewUtil.box(self, Vector3(width_m + 0.3, h + 0.3, 0.08), Vector3(0, 0, -0.10), stand)
	for post_x: float in [-width_m / 2.0, width_m / 2.0]:
		ViewUtil.box(self, Vector3(0.12, 2.45, 0.12), Vector3(post_x, -0.46, -0.10), stand)


func _refresh_title() -> void:
	if panel != null and panel.has_method("page_name"):
		_title_label.text = "%s · %s · E next page" % [_title, str(panel.call("page_name"))]
	else:
		_title_label.text = _title


func describe() -> String:
	if panel != null and panel.has_method("page_name"):
		return "%s\nShowing %s. E turns the page." % [_describe, str(panel.call("page_name"))]
	return _describe


## A screen with pages turns to the next one; a one-page screen does nothing.
func use() -> void:
	if panel != null and panel.has_method("next_page"):
		panel.call("next_page")
		_refresh_title()
