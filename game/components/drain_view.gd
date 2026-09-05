class_name DrainView
extends Node3D
## Renders a SimDrain: a curbed floor sump with a grate, a standpipe
## from the vessel side, and a live totalizer. E opens/closes it.

var drain: SimDrain
var _total: Label3D
var _grate_mat: StandardMaterial3D


func setup(drain_: SimDrain) -> void:
	drain = drain_
	var curb := ViewUtil.flat(Color(0.50, 0.50, 0.49))
	ViewUtil.box(self, Vector3(0.9, 0.16, 0.9), Vector3(0, 0.08, 0), curb)
	ViewUtil.box(self, Vector3(0.7, 0.04, 0.7), Vector3(0, 0.17, 0),
		ViewUtil.flat(Color(0.12, 0.13, 0.14)))
	_grate_mat = ViewUtil.flat(Color(0.30, 0.31, 0.33))
	for i in range(5):
		ViewUtil.box(self, Vector3(0.66, 0.03, 0.05),
			Vector3(0, 0.19, -0.26 + i * 0.13), _grate_mat)
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var dark := ViewUtil.flat(Color(0.22, 0.23, 0.25))
	var stand := ViewUtil.cylinder(self, 0.07, 0.5, Vector3(0.38, 0.32, 0), steel)
	stand.rotation_degrees = Vector3(0, 0, 20)
	# The drain valve on the standpipe: a ball valve body with a lever,
	# a flange at the connection, and a curb tag.
	ViewUtil.box(self, Vector3(0.15, 0.13, 0.13), Vector3(0.35, 0.28, 0), dark)
	var lever := ViewUtil.box(self, Vector3(0.02, 0.03, 0.18), Vector3(0.35, 0.37, 0.07), ViewUtil.flat(Color(0.75, 0.20, 0.15)))
	lever.rotation_degrees = Vector3(0, 20, 0)
	var flange := ViewUtil.cylinder(self, 0.1, 0.03, Vector3(0.455, 0.52, 0), steel)
	flange.rotation_degrees = Vector3(0, 0, 90)
	for i in 6:
		var a := TAU / 6.0 * i
		var bolt := ViewUtil.cylinder(self, 0.009, 0.02, Vector3(0.475, 0.52 + cos(a) * 0.08, sin(a) * 0.08), dark)
		bolt.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.2, 0.06, 0.004), Vector3(0, 0.1, 0.452), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	_total = ViewUtil.label(self, "", Vector3(0, 0.62, 0))
	_total.font_size = 26
	ViewUtil.label(self, drain.comp_name, Vector3(0, 0.80, 0))
	ViewUtil.interact_body(self, Vector3(0.95, 0.5, 0.95), Vector3(0, 0.25, 0))


func _process(_delta: float) -> void:
	_total.text = "%s · Σ %.0f L" % ["OPEN" if drain.is_open else "CLOSED", drain.total_l]
	_grate_mat.albedo_color = Color(0.30, 0.31, 0.33) if drain.is_open \
		else Color(0.55, 0.25, 0.20)


func describe() -> String:
	return "%s — drain, Cv %.1f L/s at 1 bar (E opens/closes)\n%s · passing %.2f L/s · total %.1f L" % [
		drain.comp_name, drain.rate_lps, "OPEN" if drain.is_open else "CLOSED",
		drain.flow_lps, drain.total_l]


func use() -> void:
	drain.is_open = not drain.is_open
