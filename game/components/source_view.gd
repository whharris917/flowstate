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
	ViewUtil.box(self, Vector3(0.5, 0.12, 0.5), Vector3(0, 0.06, 0),
		ViewUtil.flat(Color(0.34, 0.35, 0.37)))
	ViewUtil.cylinder(self, 0.09, 1.5, Vector3(0, 0.85, 0), steel)
	for flange_y: float in [0.35, 1.25]:
		ViewUtil.cylinder(self, 0.15, 0.05, Vector3(0, flange_y, 0), steel)
	var spout := ViewUtil.cylinder(self, 0.09, 0.5, Vector3(0.25, 1.55, 0), steel)
	spout.rotation_degrees = Vector3(0, 0, 90)
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
	var plate := ViewUtil.label(self, "SUPPLY", Vector3(0, 1.15, 0.15))
	plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	plate.font_size = 26
	_total = ViewUtil.label(self, "", Vector3(0, 1.95, 0))
	_total.font_size = 28
	ViewUtil.label(self, source.comp_name, Vector3(0, 2.14, 0))
	ViewUtil.interact_body(self, Vector3(0.7, 1.8, 0.7), Vector3(0, 0.9, 0))


func _process(_delta: float) -> void:
	_total.text = "Σ %.0f L" % source.total_l


func describe() -> String:
	return "%s — supply header (utility tie-in)\nunlimited · drawing %.2f L/s · total %.1f L" % [
		source.comp_name, source.draw.value, source.total_l]


func use() -> void:
	pass
