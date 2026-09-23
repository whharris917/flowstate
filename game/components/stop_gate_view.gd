class_name StopGateView
extends VialPartView
## Renders a SimStopGate: a small pneumatic cylinder on a bracket beside
## the track, its pin across the belt at the height of a vial's heel
## while held and drawn back clear while released. The origin is the
## pin's point on the track's centreline; the bracket stands off to +z.
## A hiss of air each time the pin moves.

var gate: SimStopGate
var _pin: Node3D
var _was_blocking := true


func _build() -> void:
	gate = record as SimStopGate
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var alu := ViewUtil.flat(Color(0.78, 0.79, 0.80))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	# The post and bracket, from the floor beside the track.
	ViewUtil.box(self, Vector3(0.03, DECK + 0.02, 0.03), Vector3(0, (DECK + 0.02) / 2.0, 0.16), steel)
	ViewUtil.cylinder(self, 0.05, 0.01, Vector3(0, 0.005, 0.16), dark)
	ViewUtil.box(self, Vector3(0.05, 0.12, 0.02), Vector3(0, 0.6, 0.155), dark)
	# The cylinder, along -z toward the track, just above the belt.
	var body := ViewUtil.cylinder(self, 0.013, 0.08, Vector3(0, DECK + 0.012, 0.10), alu)
	body.rotation_degrees = Vector3(90, 0, 0)
	_pin = Node3D.new()
	add_child(_pin)
	var pin := ViewUtil.cylinder(_pin, 0.004, 0.09, Vector3(0, DECK + 0.012, 0.015), steel)
	pin.rotation_degrees = Vector3(90, 0, 0)
	var tag := ViewUtil.label(self, gate.comp_name, Vector3(0, DECK + 0.2, 0.12))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.08, 0.1, 0.12), Vector3(0, DECK + 0.02, 0.1))
	_was_blocking = gate.blocking


func _process(_delta: float) -> void:
	if gate == null:
		return
	# Drawn back into the cylinder as it retracts, clear of the belt.
	_pin.position.z = 0.07 * gate.retracted / 100.0
	if gate.blocking != _was_blocking:
		_was_blocking = gate.blocking
		EquipmentAudio.play_once(self, "res://audio/valve_air.wav", Vector3(0, DECK, 0.1), -20.0, 1.8)


func describe() -> String:
	var where := " on %s" % gate.host if gate.host != "" else " · not over a track"
	return "%s — stop gate%s\n%s · %s" % [gate.comp_name, where,
		"HOLDING" if gate.blocking else "RELEASED",
		"coil energized" if gate.release.value > 0.5 else "coil off (spring holds the pin across)"]
