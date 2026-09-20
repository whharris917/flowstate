class_name BallValveView
extends Node3D
## Renders a SimBallValve: a compact two-piece body on the line with a
## lever on top that lies along the line when open and across it when
## shut, following the real travel. E throws the lever; a clunk when it
## lands at either end. Built at the bore of the line on it.

const LINE_Y := 0.32
const HALF := 0.20

var valve: SimBallValve
var bore := 0.07
var _lever: Node3D
var _last_pos := -1.0
var _moving := false


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_lever = null
	setup(valve, r)


func setup(valve_: SimBallValve, bore_r: float = 0.07) -> void:
	valve = valve_
	bore = bore_r
	var s := SmallBoreUtil.body_scale(bore_r)
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.28, 0.29, 0.32))
	var lever_mat := ViewUtil.flat(Color(0.80, 0.16, 0.12))
	# Body: a round two-piece body with a hex at each end, on the axis.
	var body_r := bore_r * 1.7 + 0.012
	var body_l := 0.11 * s + 0.03
	var body := ViewUtil.cylinder(self, body_r, body_l, Vector3(0, LINE_Y, 0), steel)
	body.rotation_degrees = Vector3(0, 0, 90)
	for side: float in [-1.0, 1.0]:
		var hex := ViewUtil.cylinder(self, body_r * 0.95, 0.02, Vector3(side * (body_l / 2.0 + 0.01), LINE_Y, 0), steel)
		(hex.mesh as CylinderMesh).radial_segments = 6
		hex.rotation_degrees = Vector3(0, 0, 90)
	SmallBoreUtil.spool(self, -HALF, -body_l / 2.0 - 0.02, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, body_l / 2.0 + 0.02, HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, HALF, LINE_Y, bore_r, steel)
	# Stem boss and the lever on it: held, since it turns.
	var stem_top := LINE_Y + body_r + 0.03
	ViewUtil.cylinder(self, 0.014 * s + 0.008, 0.03, Vector3(0, LINE_Y + body_r + 0.015, 0), dark)
	_lever = Node3D.new()
	_lever.position = Vector3(0, stem_top, 0)
	add_child(_lever)
	var lever_l := 0.10 * s + 0.06
	ViewUtil.cylinder(_lever, 0.012 * s + 0.006, 0.012, Vector3(0, 0.006, 0), dark)
	ViewUtil.box(_lever, Vector3(lever_l, 0.008, 0.018), Vector3(lever_l / 2.0 - 0.01, 0.012, 0), lever_mat)
	ViewUtil.box(_lever, Vector3(0.03, 0.014, 0.022), Vector3(lever_l - 0.02, 0.012, 0), lever_mat)
	var tag := ViewUtil.label(self, valve.comp_name, Vector3(0, stem_top + 0.20, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(HALF * 2.0, stem_top + 0.04 - LINE_Y + 0.14, 0.2),
		Vector3(0, (LINE_Y + stem_top) / 2.0, 0))
	_last_pos = valve.position
	_place_lever()


func _place_lever() -> void:
	if _lever != null:
		# Along the line when open, across it when shut.
		_lever.rotation.y = deg_to_rad(90.0) * (1.0 - valve.position / 100.0)


func _process(_delta: float) -> void:
	if valve == null:
		return
	var pos := valve.position
	if pos != _last_pos:
		_place_lever()
	var moving := absf(pos - _last_pos) > 1e-4
	if _moving and not moving:
		EquipmentAudio.play_once(self, "res://audio/clunk.wav", Vector3(0, LINE_Y, 0), -18.0,
			1.5 if pos > 50.0 else 1.7)
	_moving = moving
	_last_pos = pos


func describe() -> String:
	var travel := "" if (valve.position <= 0.5 or valve.position >= 99.5) else " %.0f %%" % valve.position
	return "%s — ball valve, %s at 1 bar\n%s%s · passing %s · E throws the lever" % [
		valve.comp_name, SimTypes.flow_text(valve.cv_lps), valve.state(), travel,
		SimTypes.flow_text(valve.flow_lps)]


func use() -> void:
	valve.open = not valve.open
