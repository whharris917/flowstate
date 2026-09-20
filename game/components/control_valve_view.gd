class_name ControlValveView
extends Node3D
## Renders a SimControlValve: globe body between flanges, yoke and
## diaphragm actuator, a stem indicator that rides the real position,
## and a live percent readout.

var valve: SimControlValve
var _indicator: MeshInstance3D
var _label: Label3D
var _last_pos: float = 0.0
var _air_cool: float = 0.0
var _seated: bool = true


var bore := 0.07   # the bore of the biggest line on it


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_indicator = null
	setup(valve, r)


func setup(valve_: SimControlValve, bore_r: float = 0.07) -> void:
	valve = valve_
	bore = bore_r
	var s := bore_r / 0.07
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var green := ViewUtil.flat(Color(0.16, 0.42, 0.28))
	# Body: horizontal run with flanges, globe bulge below, at the bore
	# of the line (2026-09-20); the flanges are the mates of the lines'
	# own, their faces at the anchors (0.31).
	var body := ViewUtil.cylinder(self, 0.09 * s, 0.56, Vector3(0, 0.32, 0), steel)
	body.rotation_degrees = Vector3(0, 0, 90)
	for side: float in [-1.0, 1.0]:
		var flange := ViewUtil.cylinder(self, bore_r * 1.8, 0.045, Vector3(side * 0.2875, 0.32, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.13 * s, 0.22, Vector3(0, 0.30, 0), green)
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
	# Flange bolts, a positioner on the yoke with its gauge and the air
	# tubing up to the diaphragm, and a nameplate.
	for side: float in [-1.0, 1.0]:
		for i in 8:
			var a := TAU / 8.0 * i
			var bolt := ViewUtil.cylinder(self, 0.011, 0.02, Vector3(side * 0.315, 0.32 + cos(a) * bore_r * 1.5, sin(a) * bore_r * 1.5), steel)
			bolt.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.10, 0.14, 0.08), Vector3(0.16, 0.74, 0.06), ViewUtil.flat(Color(0.22, 0.23, 0.26)))
	var pgauge := ViewUtil.cylinder(self, 0.025, 0.012, Vector3(0.16, 0.77, 0.105), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	pgauge.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.cylinder(self, 0.005, 0.2, Vector3(0.20, 0.88, 0.06), steel)
	var tube := ViewUtil.cylinder(self, 0.005, 0.12, Vector3(0.14, 0.98, 0.06), steel)
	tube.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.004, 0.035, 0.08), Vector3(0.122, 0.62, 0), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	# Stem with a travel indicator that follows the real position.
	ViewUtil.cylinder(self, 0.018, 0.30, Vector3(0, 0.72, 0), steel)
	_indicator = ViewUtil.box(self, Vector3(0.10, 0.02, 0.05), Vector3(0, 0.60, 0.05),
		ViewUtil.flat(Color(0.92, 0.55, 0.10)))
	_label = ViewUtil.label(self, "", Vector3(0, 1.22, 0))
	_label.font_size = 32
	ViewUtil.label(self, valve.comp_name, Vector3(0, 1.42, 0))
	ViewUtil.interact_body(self, Vector3(0.7, 1.2, 0.55), Vector3(0, 0.62, 0))


func _process(delta: float) -> void:
	_label.text = "%.0f %%" % valve.position
	_indicator.position.y = 0.60 + valve.position / 100.0 * 0.22
	# The actuator breathes when the stem actually travels: an air
	# burst per stroke, re-fired while a long move is still going.
	_air_cool = maxf(_air_cool - delta, 0.0)
	var speed := absf(valve.position - _last_pos) / maxf(delta, 1e-5)
	_last_pos = valve.position
	if speed > 2.5 and _air_cool <= 0.0:
		EquipmentAudio.play_once(self, "res://audio/valve_air.wav",
			Vector3(0, 0.98, 0), -12.0, randf_range(0.92, 1.08))
		_air_cool = 1.1
	# Plug meeting the seat is a real mechanical event.
	if valve.position < 1.0 and not _seated:
		_seated = true
		EquipmentAudio.play_once(self, "res://audio/clunk.wav",
			Vector3(0, 0.35, 0), -12.0, 1.25)
	elif valve.position > 4.0:
		_seated = false


func describe() -> String:
	return "%s — control valve\ncmd %.1f %% · position %.1f %% · flow %.2f L/s" % [
		valve.comp_name, valve.cmd.value, valve.position, valve.flow_lps]


func use() -> void:
	pass
