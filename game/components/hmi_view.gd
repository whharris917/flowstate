class_name HmiView
extends Node3D
## A wall-mounted HMI screen: a SubViewport renders a TrendPanel and a
## quad in the world displays it, softly emissive like a real display.

const SCREEN_W := 1.6
const SCREEN_H := 1.0

var panel: TrendPanel


func setup(historian: SimHistorian, tank: SimTank, switch: SimFloatSwitch,
		relay: SimRelay, pump: SimPump) -> void:
	ViewUtil.box(self, Vector3(SCREEN_W + 0.12, SCREEN_H + 0.12, 0.08),
		Vector3(0, 0, -0.045), ViewUtil.flat(Color(0.16, 0.16, 0.17)))

	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	panel = TrendPanel.new()
	panel.setup(historian, tank, switch, relay, pump)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(panel)

	var quad := QuadMesh.new()
	quad.size = Vector2(SCREEN_W, SCREEN_H)
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

	ViewUtil.label(self, "HMI", Vector3(0, SCREEN_H / 2.0 + 0.25, 0))
	ViewUtil.interact_body(self, Vector3(SCREEN_W + 0.15, SCREEN_H + 0.15, 0.2), Vector3.ZERO)


func describe() -> String:
	return "HMI — tank level trend, last 120 s\nDrawn from historian samples, one per scan."


func use() -> void:
	pass
