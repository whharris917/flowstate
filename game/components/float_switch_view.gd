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
	ViewUtil.box(self, Vector3(0.12, 0.5, 0.12), offset,
		ViewUtil.flat(Color(0.62, 0.60, 0.55)))
	_lamp_on = ViewUtil.glow(Color(0.11, 0.69, 0.48))
	_lamp_off = ViewUtil.flat(Color(0.2, 0.26, 0.23))
	_lamp = ViewUtil.box(self, Vector3(0.07, 0.07, 0.05),
		offset + (Vector3(0.06, 0.2, 0) if mounted else Vector3(0, 0.2, 0.08)), _lamp_off)
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
