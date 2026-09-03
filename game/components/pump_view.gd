class_name PumpView
extends Node3D
## Renders a SimPump: base skid, motor barrel sized to what the pump is
## rated for, status lamp, selector label. [E] cycles the selector
## (Manual On / Off / Auto). The hover text is the nameplate plus the
## operating point, so two pumps that look alike can be told apart by
## the one number that separates them, and a pump that is turning with
## nothing moving says why.

var pump: SimPump
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _lamp: MeshInstance3D
var _mode_label: Label3D
var _motor: EquipmentAudio
var _was_running: bool = false


func setup(pump_: SimPump) -> void:
	pump = pump_
	# Hydraulic size: rated flow times shutoff head. A 3 L/s pump for
	# 30 m is the reference; a 3 L/s pump for 5 m is visibly smaller.
	var size := clampf(pow(pump.rated_lps * pump.head_m / 90.0, 1.0 / 3.0), 0.6, 1.5)
	ViewUtil.box(self, Vector3(0.7, 0.25, 0.5), Vector3(0, 0.125, 0),
		ViewUtil.flat(Color(0.35, 0.36, 0.38)))
	var barrel := ViewUtil.cylinder(self, 0.18 * size, 0.5 * size, Vector3(0, 0.42, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16)))
	barrel.rotation_degrees = Vector3(0, 0, 90)
	_lamp_on = ViewUtil.glow(Color(0.05, 0.64, 0.05))
	_lamp_off = ViewUtil.flat(Color(0.22, 0.24, 0.22))
	_lamp = ViewUtil.box(self, Vector3(0.09, 0.09, 0.09), Vector3(0, 0.42 + 0.22 * size + 0.08, 0), _lamp_off)
	ViewUtil.label(self, pump.comp_name, Vector3(0, 1.15, 0))
	_mode_label = ViewUtil.label(self, "", Vector3(0, 0.95, 0))
	_mode_label.modulate = Color(1.0, 0.75, 0.35)
	ViewUtil.interact_body(self, Vector3(0.8, 0.9, 0.6), Vector3(0, 0.45, 0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 0.42, 0), -12.0, 1.0)


func _process(_delta: float) -> void:
	_lamp.material_override = _lamp_on if pump.running else _lamp_off
	_mode_label.text = SimPump.mode_label(pump.mode)
	_motor.set_running(pump.running)
	if pump.running != _was_running:
		_was_running = pump.running
		EquipmentAudio.play_once(self, "res://audio/clunk.wav",
			Vector3(0, 0.5, 0), -8.0, 1.0 if pump.running else 0.8)


func describe() -> String:
	var lift_m := pump.head_pa / SimHydraulics.HEAD_PA_PER_M
	return "%s [%s] — %s\nrated %.1f L/s · shutoff head %.0f m · %d starts\nflow %.2f L/s · suction %.0f kPa · discharge %.0f kPa · lifting %.1f m\n[E] selector: manual on / off / auto" % [
		pump.comp_name, SimPump.mode_label(pump.mode), pump.status(),
		pump.rated_lps, pump.head_m, pump.starts,
		pump.flow_lps, pump.suction_pa / 1000.0, pump.discharge_pa / 1000.0, lift_m]


func use() -> void:
	pump.next_mode()
