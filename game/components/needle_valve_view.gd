class_name NeedleValveView
extends Node3D
## Renders a SimNeedleValve: a small forged body on the line, a bonnet,
## and a knurled handle on a rising stem that turns with the real
## turns_open — a turn of the handle is a turn of the stem. E opens it
## a turn at a time; at full open the next press shuts it. Built at
## the bore of the line on it.

const LINE_Y := 0.32
const HALF := 0.20
const STEM_RISE := 0.035   # how far the stem climbs from shut to full open

var valve: SimNeedleValve
var bore := 0.07
var _handle: Node3D
var _last_turns := -1.0


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_handle = null
	setup(valve, r)


func setup(valve_: SimNeedleValve, bore_r: float = 0.07) -> void:
	valve = valve_
	bore = bore_r
	var s := SmallBoreUtil.body_scale(bore_r)
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.28, 0.29, 0.32))
	var knob_mat := ViewUtil.flat(Color(0.16, 0.17, 0.20))
	# Body: a forged block on the axis, the spools out to the faces.
	var body_w := 0.12 * s + 0.04
	ViewUtil.box(self, Vector3(body_w, 0.10 * s + 0.03, 0.09 * s + 0.03), Vector3(0, LINE_Y, 0), steel)
	SmallBoreUtil.spool(self, -HALF, -body_w / 2.0, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, body_w / 2.0, HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, HALF, LINE_Y, bore_r, steel)
	# Bonnet, with its packing nut, standing off the body.
	var bonnet_h := 0.07 * s + 0.03
	var bonnet_top := LINE_Y + 0.05 * s + 0.015 + bonnet_h
	ViewUtil.cylinder(self, 0.028 * s + 0.010, bonnet_h, Vector3(0, bonnet_top - bonnet_h / 2.0, 0), steel)
	var nut := ViewUtil.cylinder(self, 0.032 * s + 0.012, 0.014, Vector3(0, bonnet_top - 0.007, 0), dark)
	(nut.mesh as CylinderMesh).radial_segments = 6
	# The stem and its knurled handle: held, since they turn and rise.
	_handle = Node3D.new()
	_handle.position = Vector3(0, bonnet_top, 0)
	add_child(_handle)
	ViewUtil.cylinder(_handle, 0.007, 0.05, Vector3(0, 0.025, 0), steel)
	var knob_r := 0.032 * s + 0.014
	ViewUtil.cylinder(_handle, knob_r, 0.018, Vector3(0, 0.055, 0), knob_mat)
	for i in 16:
		var a := TAU / 16.0 * i
		var ridge := ViewUtil.box(_handle, Vector3(0.006, 0.02, 0.004), Vector3.ZERO, knob_mat)
		ridge.position = Vector3(cos(a) * knob_r, 0.055, sin(a) * knob_r)
		ridge.rotation.y = -a
	# A pointer mark on the handle, so the turn can be seen.
	ViewUtil.box(_handle, Vector3(knob_r * 0.9, 0.003, 0.006), Vector3(knob_r * 0.45, 0.065, 0),
		ViewUtil.flat(Color(0.92, 0.85, 0.20)))
	var tag := ViewUtil.label(self, valve.comp_name, Vector3(0, bonnet_top + 0.22, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(HALF * 2.0, bonnet_top + 0.10 - LINE_Y + 0.12, 0.18),
		Vector3(0, (LINE_Y + bonnet_top + 0.10) / 2.0, 0))
	_place_handle()


func _place_handle() -> void:
	if _handle == null:
		return
	var frac := valve.turns_open / valve.turns
	_handle.rotation.y = -TAU * valve.turns_open
	_handle.position = Vector3(0, _bonnet_top() + frac * STEM_RISE, 0)


func _bonnet_top() -> float:
	var s := SmallBoreUtil.body_scale(bore)
	return LINE_Y + 0.05 * s + 0.015 + 0.07 * s + 0.03


func _process(_delta: float) -> void:
	if valve == null:
		return
	if valve.turns_open != _last_turns:
		_last_turns = valve.turns_open
		_place_handle()


func describe() -> String:
	return "%s — needle valve, %s at 1 bar full open, %.0f turns\n%.1f turns open (%.0f %%) · passing %s · E opens a turn (shuts at full open)" % [
		valve.comp_name, SimTypes.flow_text(valve.cv_lps), valve.turns,
		valve.turns_open, valve.position, SimTypes.flow_text(valve.flow_lps)]


## E: one turn open; from full open, all the way shut. A real edge in
## the sim, so it sounds like a stem turning in its packing.
func use() -> void:
	if valve.turns_open >= valve.turns - 1e-9:
		valve.turn(-valve.turns)
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3(0, _bonnet_top(), 0), -16.0, 0.6)
	else:
		valve.turn(1.0)
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3(0, _bonnet_top(), 0), -18.0, 0.9)
	_place_handle()
