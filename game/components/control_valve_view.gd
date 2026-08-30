class_name ControlValveView
extends Node3D
## Renders a SimControlValve: globe body between flanges, yoke and
## diaphragm actuator, a stem indicator that rides the real position,
## and a live percent readout.

var valve: SimControlValve
var _indicator: MeshInstance3D
var _label: Label3D


func setup(valve_: SimControlValve) -> void:
	valve = valve_
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var green := ViewUtil.flat(Color(0.16, 0.42, 0.28))
	# Body: horizontal run with flanges, globe bulge below.
	var body := ViewUtil.cylinder(self, 0.09, 0.56, Vector3(0, 0.32, 0), steel)
	body.rotation_degrees = Vector3(0, 0, 90)
	for side: float in [-1.0, 1.0]:
		var flange := ViewUtil.cylinder(self, 0.15, 0.05, Vector3(side * 0.30, 0.32, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.13, 0.22, Vector3(0, 0.30, 0), green)
	# Bonnet, yoke, and the diaphragm actuator on top.
	ViewUtil.cylinder(self, 0.08, 0.18, Vector3(0, 0.50, 0), green)
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.04, 0.34, 0.04), Vector3(side * 0.10, 0.72, 0), steel)
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.24
	dome_mesh.height = 0.26
	dome.mesh = dome_mesh
	dome.material_override = ViewUtil.flat(Color(0.20, 0.45, 0.30))
	dome.position = Vector3(0, 0.98, 0)
	add_child(dome)
	# Stem with a travel indicator that follows the real position.
	ViewUtil.cylinder(self, 0.018, 0.30, Vector3(0, 0.72, 0), steel)
	_indicator = ViewUtil.box(self, Vector3(0.10, 0.02, 0.05), Vector3(0, 0.60, 0.05),
		ViewUtil.flat(Color(0.92, 0.55, 0.10)))
	_label = ViewUtil.label(self, "", Vector3(0, 1.22, 0))
	_label.font_size = 32
	ViewUtil.label(self, valve.comp_name, Vector3(0, 1.42, 0))
	ViewUtil.interact_body(self, Vector3(0.7, 1.2, 0.55), Vector3(0, 0.62, 0))


func _process(_delta: float) -> void:
	_label.text = "%.0f %%" % valve.position
	_indicator.position.y = 0.60 + valve.position / 100.0 * 0.22


func describe() -> String:
	return "%s — control valve\ncmd %.1f %% · position %.1f %% · flow %.2f L/s" % [
		valve.comp_name, valve.cmd.value, valve.position, valve.flow.value]


func use() -> void:
	pass
