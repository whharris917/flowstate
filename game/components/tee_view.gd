class_name TeeView
extends Node3D
## Renders a SimTee: a stainless cross at line height with a flanged
## stub each way — the run stub in or out along x, the side legs along
## z — on a small saddle. Unused nozzles wear a blind flange. Its
## anchors are in PlantFactory.PORT_ANCHORS; the fittings that land
## there are the runs' own.

const LINE_Y := 0.35

var tee: SimTee
var _label: Label3D
var bore := 0.07   # the bore of the biggest line on it; the body is built at it


## Built again at another bore (the plant, when a line of another size
## lands on it): everything goes, the body comes back at the new size.
func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_label = null
	setup(tee, r)


func setup(tee_: SimTee, bore_r: float = 0.07) -> void:
	tee = tee_
	bore = bore_r
	var s := bore_r / 0.07
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.22, 0.23, 0.26))
	# Body: two short runs crossing, a boss at the crossing.
	var run_x := ViewUtil.cylinder(self, bore_r, 0.5, Vector3(0, LINE_Y, 0), steel)
	run_x.rotation_degrees = Vector3(0, 0, 90)
	var run_z := ViewUtil.cylinder(self, bore_r, 0.5, Vector3(0, LINE_Y, 0), steel)
	run_z.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.cylinder(self, 0.10 * s, 0.18, Vector3(0, LINE_Y, 0), steel)
	# Flanges at the four faces, the mates of the lines' own: 1.8 × bore,
	# 0.045 thick, their faces at the anchors (0.27).
	for offset: Vector3 in [Vector3(0.2475, 0, 0), Vector3(-0.2475, 0, 0)]:
		var flange := ViewUtil.cylinder(self, bore_r * 1.8, 0.045, Vector3(0, LINE_Y, 0) + offset, steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	for offset: Vector3 in [Vector3(0, 0, 0.2475), Vector3(0, 0, -0.2475)]:
		var flange := ViewUtil.cylinder(self, bore_r * 1.8, 0.045, Vector3(0, LINE_Y, 0) + offset, steel)
		flange.rotation_degrees = Vector3(90, 0, 0)
	# Saddle support to the floor.
	ViewUtil.box(self, Vector3(0.12, LINE_Y - 0.08, 0.12), Vector3(0, (LINE_Y - 0.08) / 2.0, 0), dark)
	ViewUtil.box(self, Vector3(0.3, 0.02, 0.3), Vector3(0, 0.01, 0), dark)
	_label = ViewUtil.label(self, tee.comp_name, Vector3(0, 0.85, 0))
	_label.font_size = 28
	ViewUtil.interact_body(self, Vector3(0.7, 0.7, 0.7), Vector3(0, LINE_Y, 0))


func describe() -> String:
	return "%s — %s tee: one node, four nozzles\n%s L/s" % [
		tee.comp_name, "splitter" if tee.mode == "split" else "mixer", tee.leg_flows()]


func use() -> void:
	pass
