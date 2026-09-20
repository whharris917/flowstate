class_name RotameterView
extends Node3D
## Renders a SimRotameter: a body on the line with the tapered glass
## tube standing up from it, a scale plate behind the tube, and the
## float riding at the height the real flow puts it. The tube keeps
## its size whatever the line's bore, since it has to be read. Built
## at the bore of the line on it.

const LINE_Y := 0.32
const HALF := 0.22
const TUBE_H := 0.30

var meter: SimRotameter
var bore := 0.07
var _float: Node3D
var _tube_base := 0.0


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_float = null
	setup(meter, r)


func setup(meter_: SimRotameter, bore_r: float = 0.07) -> void:
	meter = meter_
	bore = bore_r
	var half := SmallBoreUtil.half_for(HALF, bore_r)
	var s := SmallBoreUtil.body_scale(bore_r)
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.28, 0.29, 0.32))
	var body_w := 0.10 * s + 0.05
	ViewUtil.box(self, Vector3(body_w, 0.07 * s + 0.03, 0.08 * s + 0.03), Vector3(0, LINE_Y, 0), steel)
	SmallBoreUtil.spool(self, -half, -body_w / 2.0, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, body_w / 2.0, half, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -half, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, half, LINE_Y, bore_r, steel)
	# The tube: tapered glass, the bottom end fitting on the body, the
	# top end fitting closing it.
	_tube_base = LINE_Y + 0.035 * s + 0.015 + 0.02
	ViewUtil.cylinder(self, 0.032, 0.02, Vector3(0, _tube_base - 0.01, 0), dark)
	ViewUtil.cylinder(self, 0.032, 0.02, Vector3(0, _tube_base + TUBE_H + 0.01, 0), dark)
	var glass := ViewUtil.flat(Color(0.82, 0.90, 0.94, 0.30))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tube := MeshInstance3D.new()
	var tube_mesh := CylinderMesh.new()
	tube_mesh.bottom_radius = 0.018
	tube_mesh.top_radius = 0.026
	tube_mesh.height = TUBE_H
	tube_mesh.radial_segments = 24
	tube.mesh = tube_mesh
	tube.material_override = glass
	tube.position = Vector3(0, _tube_base + TUBE_H / 2.0, 0)
	add_child(tube)
	# The scale plate behind the tube, ten divisions.
	ViewUtil.box(self, Vector3(0.06, TUBE_H + 0.02, 0.004), Vector3(0, _tube_base + TUBE_H / 2.0, -0.036),
		ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	for i in 11:
		var w := 0.02 if i % 5 == 0 else 0.012
		ViewUtil.box(self, Vector3(w, 0.002, 0.003), Vector3(-0.03 + w / 2.0, _tube_base + TUBE_H * i / 10.0, -0.033), dark)
	# Tie rods either side of the tube.
	for side: float in [-1.0, 1.0]:
		ViewUtil.cylinder(self, 0.004, TUBE_H, Vector3(side * 0.04, _tube_base + TUBE_H / 2.0, 0.0), steel)
	# The float: held, since it rides the flow.
	_float = Node3D.new()
	add_child(_float)
	var cone := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.bottom_radius = 0.014
	cone_mesh.top_radius = 0.006
	cone_mesh.height = 0.024
	cone.mesh = cone_mesh
	cone.material_override = ViewUtil.flat(Color(0.80, 0.16, 0.12))
	_float.add_child(cone)
	var tag := ViewUtil.label(self, meter.comp_name, Vector3(0, _tube_base + TUBE_H + 0.22, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(half * 2.0, TUBE_H + 0.16 + (_tube_base - LINE_Y), 0.16),
		Vector3(0, (LINE_Y + _tube_base + TUBE_H + 0.02) / 2.0, 0))
	_place_float()


func _place_float() -> void:
	if _float != null:
		_float.position = Vector3(0, _tube_base + 0.014 + (TUBE_H - 0.028) * meter.float_frac, 0)


func _process(_delta: float) -> void:
	if meter != null:
		_place_float()


func describe() -> String:
	return "%s — rotameter, %s full scale\nreads %s (%.0f %% of scale)" % [
		meter.comp_name, SimTypes.flow_text(meter.range_lps), SimTypes.flow_text(meter.flow_lps),
		meter.float_frac * 100.0]


func use() -> void:
	pass
