class_name CentrifugeView
extends Node3D
## Renders a SimCentrifuge: squat bowl on legs with a domed lid and
## motor pod; a marked rotor collar genuinely spins with the drive.
## E starts/stops the bowl. Whines when spinning.

var fuge: SimCentrifuge
var _rotor: Node3D
var _label: Label3D
var _motor: EquipmentAudio
var _was_spinning: bool = false


func setup(fuge_: SimCentrifuge) -> void:
	fuge = fuge_
	var body_mat := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	body_mat.metallic = 0.5
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	for leg_angle in range(3):
		var ang := TAU / 3.0 * leg_angle
		ViewUtil.box(self, Vector3(0.1, 0.45, 0.1),
			Vector3(cos(ang) * 0.42, 0.22, sin(ang) * 0.42), dark)
	ViewUtil.cylinder(self, 0.5, 0.75, Vector3(0, 0.8, 0), body_mat)
	var lid := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 0.5
	lid.mesh = dome
	lid.material_override = body_mat
	lid.position = Vector3(0, 1.18, 0)
	add_child(lid)
	# Rotor collar with an index stripe: watch it actually spin.
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.44, 0)
	add_child(_rotor)
	ViewUtil.cylinder(_rotor, 0.14, 0.1, Vector3.ZERO, dark)
	ViewUtil.box(_rotor, Vector3(0.26, 0.04, 0.05), Vector3(0, 0.03, 0),
		ViewUtil.flat(Color(0.92, 0.55, 0.10)))
	ViewUtil.cylinder(self, 0.16, 0.28, Vector3(0, 1.62, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16)))
	_label = ViewUtil.label(self, "", Vector3(0, 1.95, 0))
	_label.font_size = 26
	ViewUtil.label(self, fuge.comp_name, Vector3(0, 2.15, 0))
	ViewUtil.interact_body(self, Vector3(1.2, 1.7, 1.2), Vector3(0, 0.9, 0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 1.6, 0), -9.0, 1.45)


func _process(delta: float) -> void:
	if fuge.spinning:
		_rotor.rotate_y(delta * 22.0)
	_motor.set_running(fuge.spinning)
	if fuge.spinning != _was_spinning:
		_was_spinning = fuge.spinning
		EquipmentAudio.play_once(self, "res://audio/clunk.wav",
			Vector3(0, 1.6, 0), -8.0, 1.1 if fuge.spinning else 0.85)
	_label.text = "%s · %.1f L/s" % [
		"SPINNING" if fuge.spinning else ("ON, waiting" if fuge.is_on else "stopped"),
		fuge.draw_lps]


func describe() -> String:
	return "%s — centrifuge, %.1f L/s (E starts/stops)\n%s · product %.2f L/s · waste %.2f L/s · %d starts" % [
		fuge.comp_name, fuge.rate_lps,
		"SPINNING" if fuge.spinning else ("ON but starved/unpowered" if fuge.is_on else "stopped"),
		fuge.product.value, fuge.waste.value, fuge.starts]


func use() -> void:
	fuge.is_on = not fuge.is_on
