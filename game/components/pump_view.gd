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
	# A vertical in-line centrifugal pump, the pharmaceutical plant's
	# workhorse: suction and discharge on one axis through the casing,
	# the motor standing on top. Pedestal and grout plate with anchor
	# bolts, casing with a drain plug, flanged nozzles, motor with its
	# fin rings, fan cowl, terminal box and nameplate. All of it scales
	# with the rating, so a small pump looks small.
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var dark := ViewUtil.flat(Color(0.22, 0.23, 0.25))
	var casing := ViewUtil.flat(Color(0.16, 0.42, 0.28))
	var motor := ViewUtil.flat(Color(0.16, 0.36, 0.62))
	ViewUtil.box(self, Vector3(0.7, 0.22, 0.5), Vector3(0, 0.11, 0), ViewUtil.flat(Color(0.35, 0.36, 0.38)))
	ViewUtil.box(self, Vector3(0.62, 0.03, 0.42), Vector3(0, 0.235, 0), steel)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ViewUtil.cylinder(self, 0.014, 0.05, Vector3(corner.x * 0.27, 0.27, corner.y * 0.17), dark)
	# Casing on the pipe axis, a flange on each face, the nozzles out to
	# the fittings, and a drain plug underneath.
	var r := 0.17 * size
	var body := ViewUtil.cylinder(self, r, 0.22 * size, Vector3(0, 0.42, 0), casing)
	body.rotation_degrees = Vector3(0, 0, 90)
	for side: float in [-1.0, 1.0]:
		var face := ViewUtil.cylinder(self, r * 1.12, 0.025, Vector3(side * 0.11 * size, 0.42, 0), steel)
		face.rotation_degrees = Vector3(0, 0, 90)
		var nozzle := ViewUtil.cylinder(self, 0.065, 0.25 - 0.11 * size, Vector3(side * (0.11 * size + (0.25 - 0.11 * size) / 2.0), 0.42, 0), casing)
		nozzle.rotation_degrees = Vector3(0, 0, 90)
		var flange := ViewUtil.cylinder(self, 0.11, 0.03, Vector3(side * 0.235, 0.42, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.02, 0.06, Vector3(0, 0.42 - r - 0.02, 0), steel)
	ViewUtil.box(self, Vector3(0.09, 0.10, 0.04), Vector3(0, 0.42 - r * 0.6, r * 0.9), casing)  # casing foot
	# Motor stack: adapter, body with fin rings, fan cowl, terminal box
	# with its conduit stub toward the power fitting, nameplate.
	var mr := 0.15 * size
	var mh := 0.42 * size
	var top := 0.42 + r
	ViewUtil.cylinder(self, mr * 0.85, 0.12, Vector3(0, top + 0.06, 0), dark)
	ViewUtil.cylinder(self, mr, mh, Vector3(0, top + 0.12 + mh / 2.0, 0), motor)
	for i in 6:
		ViewUtil.cylinder(self, mr * 1.08, 0.012, Vector3(0, top + 0.17 + i * mh * 0.14, 0), motor)
	ViewUtil.cylinder(self, mr * 1.05, 0.08, Vector3(0, top + 0.12 + mh + 0.04, 0), dark)
	ViewUtil.cylinder(self, mr * 0.35, 0.03, Vector3(0, top + 0.12 + mh + 0.09, 0), steel)
	ViewUtil.box(self, Vector3(0.12, 0.10, 0.08), Vector3(-0.05, top + 0.30, -mr - 0.04), steel)
	var stub := ViewUtil.cylinder(self, 0.018, 0.10, Vector3(-0.05, top + 0.30, -mr - 0.11), dark)
	stub.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.005, 0.06, 0.12), Vector3(mr + 0.003, top + 0.38, 0), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	_lamp_on = ViewUtil.glow(Color(0.05, 0.64, 0.05))
	_lamp_off = ViewUtil.flat(Color(0.22, 0.24, 0.22))
	_lamp = ViewUtil.box(self, Vector3(0.07, 0.07, 0.05), Vector3(0.02, 0.62, mr + 0.03), _lamp_off)
	var label_y := top + 0.12 + mh + 0.32
	ViewUtil.label(self, pump.comp_name, Vector3(0, label_y + 0.2, 0))
	_mode_label = ViewUtil.label(self, "", Vector3(0, label_y, 0))
	_mode_label.modulate = Color(1.0, 0.75, 0.35)
	ViewUtil.interact_body(self, Vector3(0.8, label_y - 0.1, 0.6), Vector3(0, (label_y - 0.1) / 2.0, 0))
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
