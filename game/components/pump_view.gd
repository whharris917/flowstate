class_name PumpView
extends Node3D
## Renders a SimPump: base skid, motor barrel, status lamp, mode label.
## [E] cycles the Hand-Off-Auto selector — the one thing the player can
## operate in this build.

var pump: SimPump
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _lamp: MeshInstance3D
var _mode_label: Label3D
var _motor: EquipmentAudio


func setup(pump_: SimPump) -> void:
	pump = pump_
	ViewUtil.box(self, Vector3(0.7, 0.25, 0.5), Vector3(0, 0.125, 0),
		ViewUtil.flat(Color(0.35, 0.36, 0.38)))
	var barrel := ViewUtil.cylinder(self, 0.18, 0.5, Vector3(0, 0.42, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16)))
	barrel.rotation_degrees = Vector3(0, 0, 90)
	_lamp_on = ViewUtil.glow(Color(0.05, 0.64, 0.05))
	_lamp_off = ViewUtil.flat(Color(0.22, 0.24, 0.22))
	_lamp = ViewUtil.box(self, Vector3(0.09, 0.09, 0.09), Vector3(0, 0.72, 0), _lamp_off)
	ViewUtil.label(self, pump.comp_name, Vector3(0, 1.15, 0))
	_mode_label = ViewUtil.label(self, "", Vector3(0, 0.95, 0))
	_mode_label.modulate = Color(1.0, 0.75, 0.35)
	ViewUtil.interact_body(self, Vector3(0.8, 0.9, 0.6), Vector3(0, 0.45, 0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 0.42, 0), -12.0, 1.0)


func _process(_delta: float) -> void:
	_lamp.material_override = _lamp_on if pump.running else _lamp_off
	_mode_label.text = pump.mode.to_upper()
	_motor.set_running(pump.running)


func describe() -> String:
	return "%s [%s] — %s\nflow %.2f L/s (rated %.1f) · %d starts\n[E] selector: hand / off / auto" % [
		pump.comp_name, pump.mode.to_upper(),
		"RUNNING" if pump.running else "STOPPED",
		pump.outlet.value, pump.rated_lps, pump.starts]


func use() -> void:
	pump.next_mode()
