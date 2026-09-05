class_name FloatSwitchView
extends Node3D
## Renders a SimFloatSwitch: a small housing on the tank shell spanning
## the trip band, with a contact-state lamp. Mounted on a vessel, local
## +x is the outward normal at the mount, so the housing stands proud of
## the shell and the contact gland faces out.

var switch: SimFloatSwitch
var mounted: bool = false
var _lamp: MeshInstance3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _was_closed: bool = false


func setup(switch_: SimFloatSwitch, mounted_: bool = false) -> void:
	switch = switch_
	mounted = mounted_
	var offset := Vector3(0.06, 0, 0) if mounted else Vector3.ZERO
	# A float switch: a domed head over the body, a flanged boss where
	# it meets the shell with the float stem reaching in behind it, a
	# conduit boss at the contact, the trip lamp on the head.
	var housing := ViewUtil.flat(Color(0.62, 0.60, 0.55))
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	ViewUtil.box(self, Vector3(0.12, 0.30, 0.12), offset + Vector3(0, -0.05, 0), housing)
	ViewUtil.cylinder(self, 0.075, 0.16, offset + Vector3(0, 0.18, 0), housing)
	ViewUtil.cylinder(self, 0.05, 0.03, offset + Vector3(0, 0.27, 0), dark)
	if mounted:
		var boss := ViewUtil.cylinder(self, 0.085, 0.03, Vector3(0.0, -0.05, 0), steel)
		boss.rotation_degrees = Vector3(0, 0, 90)
		for i in 6:
			var a := TAU / 6.0 * i
			var bolt := ViewUtil.cylinder(self, 0.008, 0.02, Vector3(0.015, -0.05 + cos(a) * 0.065, sin(a) * 0.065), dark)
			bolt.rotation_degrees = Vector3(0, 0, 90)
		var stem := ViewUtil.cylinder(self, 0.008, 0.22, Vector3(-0.12, -0.05, 0), steel)
		stem.rotation_degrees = Vector3(0, 0, 90)
	else:
		ViewUtil.box(self, Vector3(0.16, 0.03, 0.16), Vector3(0, -0.215, 0), dark)
	var gland := ViewUtil.cylinder(self, 0.018, 0.04, offset + Vector3(0.07, 0.05, 0), dark)
	gland.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.004, 0.035, 0.08), offset + Vector3(0.062, -0.12, 0), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	_lamp_on = ViewUtil.glow(Color(0.11, 0.69, 0.48))
	_lamp_off = ViewUtil.flat(Color(0.2, 0.26, 0.23))
	var lamp_at := offset + (Vector3(0.076, 0.18, 0) if mounted else Vector3(0, 0.18, 0.076))
	_lamp = ViewUtil.box(self, Vector3(0.05, 0.05, 0.03), lamp_at, _lamp_off)
	if mounted:
		_lamp.rotation_degrees = Vector3(0, 90, 0)
	ViewUtil.label(self, switch.comp_name, offset + Vector3(0, 0.5, 0))
	ViewUtil.interact_body(self, Vector3(0.2, 0.55, 0.2), offset)


func _process(_delta: float) -> void:
	_lamp.material_override = _lamp_on if switch.closed else _lamp_off
	# A trip is a limit reached: announce it, both ways.
	if switch.closed != _was_closed:
		_was_closed = switch.closed
		EquipmentAudio.play_once(self, "res://audio/beep.wav",
			Vector3(0, 0.25, 0), -9.0, 1.25 if switch.closed else 0.9)


func describe() -> String:
	return "%s — contact %s\ntrips: close at %.0f L, open at %.0f L" % [
		switch.comp_name, "CLOSED (calling)" if switch.closed else "OPEN",
		switch.low_l, switch.high_l]


## One line for the vessel it is mounted on to repeat.
func summary() -> String:
	return "%s %s" % [switch.comp_name, "CLOSED (calling)" if switch.closed else "open"]


func use() -> void:
	pass
