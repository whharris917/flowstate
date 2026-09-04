class_name BlockValveView
extends Node3D
## Renders a SimBlockValve: a flanged ball-valve body, a rack-and-pinion
## actuator across the top with its solenoid and lamp, and a position
## beacon that lies along the line when open and across it when shut.
## The label reads the real state. Air on every stroke, a clunk when
## it lands at either end of travel.

var valve: SimBlockValve
var _beacon: MeshInstance3D
var _lamp: StandardMaterial3D
var _label: Label3D
var _last_pos: float = 0.0
var _moving: bool = false


func setup(valve_: SimBlockValve) -> void:
	valve = valve_
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var housing := ViewUtil.flat(Color(0.20, 0.22, 0.26))
	var actuator := ViewUtil.flat(Color(0.16, 0.36, 0.62))
	# Body: a short flanged run with the ball housing in the middle.
	var run := ViewUtil.cylinder(self, 0.08, 0.56, Vector3(0, 0.32, 0), steel)
	run.rotation_degrees = Vector3(0, 0, 90)
	for side: float in [-1.0, 1.0]:
		var flange := ViewUtil.cylinder(self, 0.14, 0.05, Vector3(side * 0.30, 0.32, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.30
	ball.mesh = sphere
	ball.material_override = housing
	ball.position = Vector3(0, 0.32, 0)
	add_child(ball)
	# Stem, mounting bracket, and the actuator barrel across the top.
	ViewUtil.cylinder(self, 0.03, 0.16, Vector3(0, 0.50, 0), steel)
	ViewUtil.box(self, Vector3(0.20, 0.04, 0.16), Vector3(0, 0.57, 0), steel)
	var barrel := ViewUtil.cylinder(self, 0.075, 0.44, Vector3(0, 0.66, 0), actuator)
	barrel.rotation_degrees = Vector3(0, 0, 90)
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.05, 0.17, 0.17), Vector3(side * 0.235, 0.66, 0), actuator)
	# Solenoid on the front with its lamp: lit while the coil is energized.
	ViewUtil.box(self, Vector3(0.09, 0.12, 0.10), Vector3(0, 0.72, 0.14), steel)
	_lamp = ViewUtil.glow(Color(0.10, 0.80, 0.35), 1.2)
	var lamp := ViewUtil.cylinder(self, 0.015, 0.01, Vector3(0, 0.75, 0.195), _lamp)
	lamp.rotation_degrees = Vector3(90, 0, 0)
	# Position beacon on the pinion: a paddle that follows the ball.
	ViewUtil.cylinder(self, 0.03, 0.06, Vector3(0, 0.76, 0), steel)
	_beacon = ViewUtil.box(self, Vector3(0.22, 0.02, 0.05), Vector3(0, 0.80, 0),
		ViewUtil.flat(Color(0.92, 0.55, 0.10)))
	_label = ViewUtil.label(self, "", Vector3(0, 1.0, 0))
	_label.font_size = 30
	ViewUtil.label(self, valve.comp_name, Vector3(0, 1.18, 0))
	ViewUtil.interact_body(self, Vector3(0.7, 1.05, 0.55), Vector3(0, 0.55, 0))
	_last_pos = valve.position


func _process(_delta: float) -> void:
	var pos := valve.position
	# Along the line when open, across it when shut.
	_beacon.rotation.y = deg_to_rad(90.0) * (1.0 - pos / 100.0)
	var state := valve.state()
	_label.text = state if (pos <= 0.5 or pos >= 99.5) else "%s %.0f %%" % [state, pos]
	var energized := valve.commanded_open
	_lamp.albedo_color = Color(0.10, 0.80, 0.35) if energized else Color(0.22, 0.24, 0.22)
	_lamp.emission_energy_multiplier = 1.2 if energized else 0.0
	# Air when the stroke starts, a clunk when it lands at either end.
	var moving := absf(pos - _last_pos) > 1e-4
	if moving and not _moving:
		EquipmentAudio.play_once(self, "res://audio/valve_air.wav",
			Vector3(0, 0.66, 0), -12.0, randf_range(0.9, 1.1))
	elif _moving and not moving:
		EquipmentAudio.play_once(self, "res://audio/clunk.wav",
			Vector3(0, 0.35, 0), -14.0, 1.1 if pos > 50.0 else 1.3)
	_moving = moving
	_last_pos = pos


func describe() -> String:
	var pos := valve.position
	var travel := "" if (pos <= 0.5 or pos >= 99.5) else " %.0f %%" % pos
	return "%s — block valve, Cv %.0f L/s at 1 bar\ncmd %s · %s%s · flow %.2f L/s" % [
		valve.comp_name, valve.cv_lps, "OPEN" if valve.commanded_open else "CLOSE",
		valve.state(), travel, valve.flow_lps]


func use() -> void:
	pass
