class_name SourceView
extends Node3D
## Renders a SimSource: a battery-limit supply station — riser with
## flanges, isolation handwheel, BL plate, and a live totalizer of
## everything drawn through it.

var source: SimSource
var _total: Label3D


func setup(source_: SimSource) -> void:
	source = source_
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var dark := ViewUtil.flat(Color(0.22, 0.23, 0.25))
	# A utility tie-in: a bolted base, the riser with its flanges and a
	# pipe clamp, an elbow at the top into the spout, a pressure gauge
	# on a pigtail, a bleed valve, and the isolation handwheel.
	ViewUtil.box(self, Vector3(0.5, 0.12, 0.5), Vector3(0, 0.06, 0),
		ViewUtil.flat(Color(0.34, 0.35, 0.37)))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ViewUtil.cylinder(self, 0.014, 0.04, Vector3(corner.x * 0.2, 0.13, corner.y * 0.2), dark)
	ViewUtil.cylinder(self, 0.09, 1.5, Vector3(0, 0.85, 0), steel)
	for flange_y: float in [0.35, 1.25]:
		var flange := ViewUtil.cylinder(self, 0.15, 0.05, Vector3(0, flange_y, 0), steel)
		for i in 8:
			var a := TAU / 8.0 * i
			ViewUtil.cylinder(self, 0.012, 0.02, flange.position + Vector3(cos(a) * 0.125, 0.03, sin(a) * 0.125), dark)
	ViewUtil.box(self, Vector3(0.26, 0.06, 0.26), Vector3(0, 0.2, 0), dark)
	var elbow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.095
	sphere.height = 0.19
	elbow.mesh = sphere
	elbow.material_override = steel
	elbow.position = Vector3(0, 1.55, 0)
	add_child(elbow)
	var spout := ViewUtil.cylinder(self, 0.09, 0.5, Vector3(0.25, 1.55, 0), steel)
	spout.rotation_degrees = Vector3(0, 0, 90)
	var pigtail := ViewUtil.cylinder(self, 0.012, 0.16, Vector3(-0.15, 1.35, 0), steel)
	pigtail.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.012, 0.12, Vector3(-0.22, 1.41, 0), steel)
	var gauge := ViewUtil.cylinder(self, 0.06, 0.025, Vector3(-0.22, 1.5, 0), dark)
	gauge.rotation_degrees = Vector3(90, 0, 0)
	var face := ViewUtil.cylinder(self, 0.05, 0.006, Vector3(-0.22, 1.5, 0.014), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	face.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.006, 0.04, 0.004), Vector3(-0.22, 1.515, 0.02), ViewUtil.flat(Color(0.85, 0.20, 0.15)))
	var bleed := ViewUtil.cylinder(self, 0.018, 0.08, Vector3(0.12, 0.62, 0.04), steel)
	bleed.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.02, 0.06, 0.02), Vector3(0.16, 0.66, 0.04), ViewUtil.flat(Color(0.75, 0.20, 0.15)))
	# Isolation handwheel.
	var wheel := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.10
	torus.outer_radius = 0.14
	wheel.mesh = torus
	wheel.material_override = ViewUtil.flat(Color(0.75, 0.20, 0.15))
	wheel.position = Vector3(0, 0.85, 0.14)
	wheel.rotation_degrees = Vector3(90, 0, 0)
	add_child(wheel)
	ViewUtil.box(self, Vector3(0.52, 0.22, 0.04), Vector3(0, 1.15, 0.12),
		ViewUtil.flat(Color(0.10, 0.32, 0.52)))
	var plate := ViewUtil.plate(self, "SUPPLY", Vector3(0, 1.15, 0.15))
	plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	plate.font_size = 26
	_total = ViewUtil.label(self, "", Vector3(0, 1.95, 0))
	_total.font_size = 28
	ViewUtil.label(self, source.comp_name, Vector3(0, 2.14, 0))
	ViewUtil.interact_body(self, Vector3(0.7, 1.8, 0.7), Vector3(0, 0.9, 0))


func _process(_delta: float) -> void:
	_total.text = "Σ %.0f L" % source.total_l


func describe() -> String:
	return "%s — supply header (utility tie-in)\n%.0f kPa · delivering %.2f L/s · total %.1f L" % [
		source.comp_name, source.pressure_kpa, source.delivered_lps, source.total_l]


func use() -> void:
	pass
