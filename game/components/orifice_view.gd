class_name OrificeView
extends Node3D
## Renders a SimOrifice: a plate between a pair of faces on a short
## spool, its handle tab standing up out of the joint with the tag on
## it, the way a restriction orifice is found in a real line. Built at
## the bore of the line on it; a tube line meets it through compression
## nuts, a pipe through flanges (SmallBoreUtil).

const LINE_Y := 0.32
const HALF := 0.20

var orifice: SimOrifice
var bore := 0.07


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	setup(orifice, r)


func setup(orifice_: SimOrifice, bore_r: float = 0.07) -> void:
	orifice = orifice_
	bore = bore_r
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var bright := ViewUtil.flat(Color(0.78, 0.80, 0.83))
	# The spool either side of the joint, and the line's fitting at each face.
	var joint := maxf(bore_r * 0.5, 0.025)
	SmallBoreUtil.spool(self, -HALF, -joint, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, joint, HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, HALF, LINE_Y, bore_r, steel)
	# The joint the plate sits in: a flange pair on a pipe, a union nut
	# on tubing.
	var plate_r := maxf(bore_r * 2.0, 0.035)
	if SmallBoreUtil.is_tube(bore_r):
		var nut := ViewUtil.cylinder(self, plate_r * 0.9, joint * 2.0, Vector3(0, LINE_Y, 0), steel)
		(nut.mesh as CylinderMesh).radial_segments = 6
		nut.rotation_degrees = Vector3(0, 0, 90)
	else:
		for side: float in [-1.0, 1.0]:
			var flange := ViewUtil.cylinder(self, bore_r * 1.8, joint - 0.004,
				Vector3(side * (joint / 2.0 + 0.002), LINE_Y, 0), steel)
			flange.rotation_degrees = Vector3(0, 0, 90)
	# The plate itself, proud of the joint, and its handle tab with the
	# hole a tag wire goes through.
	var plate := ViewUtil.cylinder(self, plate_r, 0.006, Vector3(0, LINE_Y, 0), bright)
	plate.rotation_degrees = Vector3(0, 0, 90)
	var tab_h := plate_r + 0.06
	ViewUtil.box(self, Vector3(0.006, tab_h, 0.028), Vector3(0, LINE_Y + tab_h / 2.0, 0), bright)
	var hole := ViewUtil.cylinder(self, 0.006, 0.008, Vector3(0, LINE_Y + tab_h - 0.012, 0),
		ViewUtil.flat(Color(0.10, 0.10, 0.11)))
	hole.rotation_degrees = Vector3(0, 0, 90)
	var tag := ViewUtil.label(self, orifice.comp_name, Vector3(0, LINE_Y + tab_h + 0.10, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(HALF * 2.0, tab_h + 0.1, maxf(plate_r * 2.0, 0.12)),
		Vector3(0, LINE_Y + tab_h / 2.0 - 0.02, 0))


func describe() -> String:
	return "%s — restriction orifice, %s at 1 bar\npassing %s" % [
		orifice.comp_name, SimTypes.flow_text(orifice.cv_lps), SimTypes.flow_text(orifice.flow_lps)]


func use() -> void:
	pass
