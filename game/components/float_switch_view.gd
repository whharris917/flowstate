class_name FloatSwitchView
extends Node3D
## Renders a SimFloatSwitch: a small housing on the tank shell spanning
## the trip band, with a contact-state lamp.

var switch: SimFloatSwitch
var _lamp: MeshInstance3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _was_closed: bool = false


func setup(switch_: SimFloatSwitch) -> void:
	switch = switch_
	ViewUtil.box(self, Vector3(0.12, 0.5, 0.12), Vector3.ZERO,
		ViewUtil.flat(Color(0.62, 0.60, 0.55)))
	_lamp_on = ViewUtil.glow(Color(0.11, 0.69, 0.48))
	_lamp_off = ViewUtil.flat(Color(0.2, 0.26, 0.23))
	_lamp = ViewUtil.box(self, Vector3(0.07, 0.07, 0.05), Vector3(0, 0.2, 0.08), _lamp_off)
	ViewUtil.label(self, switch.comp_name, Vector3(0, 0.5, 0))
	ViewUtil.interact_body(self, Vector3(0.2, 0.55, 0.2), Vector3.ZERO)


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


func use() -> void:
	pass
