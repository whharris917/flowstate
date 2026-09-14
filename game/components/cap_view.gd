class_name CapView
extends Node3D
## Renders a SimCap: a short flanged spool at the line's own height
## with a blind flange on each nozzle that carries no line. The plant
## tells it which sides are wired (set_capped); a cut pipe shows its
## closed end, a rejoined one a plain coupling. Its anchors come from
## PlantFactory.cap_anchors(line_y).

var cap: SimCap
var line_y := 0.35
var _blinds: Dictionary = {}   # port -> MeshInstance3D


func setup(cap_: SimCap, line_y_: float) -> void:
	cap = cap_
	line_y = line_y_
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var spool := ViewUtil.cylinder(self, 0.07, 0.3, Vector3(0, line_y, 0), steel)
	spool.rotation_degrees = Vector3(0, 0, 90)
	for offset: float in [0.13, -0.13]:
		var flange := ViewUtil.cylinder(self, 0.105, 0.03, Vector3(offset, line_y, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	# Blind flanges: a thicker disc with a ring of bolt heads, one each
	# end, shown while that nozzle has no line.
	var dark := ViewUtil.flat(Color(0.30, 0.31, 0.34))
	for port: String in ["a", "b"]:
		var side := -1.0 if port == "a" else 1.0
		var blind := Node3D.new()
		add_child(blind)
		var disc := ViewUtil.cylinder(blind, 0.11, 0.035, Vector3(side * 0.165, line_y, 0), dark)
		disc.rotation_degrees = Vector3(0, 0, 90)
		for i in 8:
			var ang := TAU / 8.0 * i
			var bolt := ViewUtil.cylinder(blind, 0.01, 0.015,
				Vector3(side * 0.19, line_y + cos(ang) * 0.085, sin(ang) * 0.085), dark)
			bolt.rotation_degrees = Vector3(0, 0, 90)
		_blinds[port] = blind
	var tag := ViewUtil.label(self, cap.comp_name, Vector3(0, line_y + 0.35, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(0.45, 0.35, 0.3), Vector3(0, line_y, 0))


## Show the blind flange on a nozzle that carries no line.
func set_capped(port: String, capped: bool) -> void:
	if _blinds.has(port):
		(_blinds[port] as Node3D).visible = capped


func describe() -> String:
	var open: Array = []
	for port: String in ["a", "b"]:
		if _blinds.has(port) and (_blinds[port] as Node3D).visible:
			open.append(port)
	var state := "coupling, both sides lined" if open.is_empty() \
		else "capped on %s — click the blind to run a line from it" % " and ".join(open)
	return "%s — pipe cap: %s\n%.2f L/s through" % [cap.comp_name, state, absf(cap.inputs["a"].flow_lps)]


func use() -> void:
	pass
