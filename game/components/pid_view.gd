class_name PIDView
extends Node3D
## Renders a SimPID as a panel-mount controller on a stand: faceplate
## with live SP / PV / OUT text straight from the record. E toggles
## auto/manual — the operator's hand switch.

var pid: SimPID
var _screen: Label3D


func setup(pid_: SimPID) -> void:
	pid = pid_
	# A field-mounted single-loop controller: post and bracket, an
	# enclosure with a bezelled face, the display recessed behind it, a
	# bargraph strip, a keypad row between the two glands, a sunshade,
	# and a nameplate.
	var dark := ViewUtil.flat(Color(0.16, 0.17, 0.19))
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	ViewUtil.box(self, Vector3(0.08, 1.1, 0.08), Vector3(0, 0.55, 0), dark)
	ViewUtil.box(self, Vector3(0.16, 0.04, 0.16), Vector3(0, 0.02, 0), dark)
	ViewUtil.box(self, Vector3(0.2, 0.12, 0.1), Vector3(0, 1.08, -0.04), steel)
	ViewUtil.box(self, Vector3(0.44, 0.60, 0.14), Vector3(0, 1.35, 0),
		ViewUtil.flat(Color(0.13, 0.14, 0.16)))
	ViewUtil.box(self, Vector3(0.40, 0.56, 0.01), Vector3(0, 1.35, 0.072),
		ViewUtil.flat(Color(0.22, 0.23, 0.26)))
	ViewUtil.box(self, Vector3(0.36, 0.44, 0.02), Vector3(0, 1.38, 0.075),
		ViewUtil.glow(Color(0.05, 0.10, 0.08), 0.4))
	ViewUtil.box(self, Vector3(0.5, 0.02, 0.22), Vector3(0, 1.67, 0.04), steel)
	ViewUtil.box(self, Vector3(0.02, 0.36, 0.006), Vector3(-0.185, 1.40, 0.085), ViewUtil.flat(Color(0.10, 0.30, 0.20)))
	ViewUtil.box(self, Vector3(0.02, 0.18, 0.006), Vector3(-0.185, 1.31, 0.088), ViewUtil.glow(Color(0.2, 0.9, 0.4), 0.8))
	for i in 4:
		ViewUtil.box(self, Vector3(0.035, 0.03, 0.012), Vector3(-0.075 + i * 0.05, 1.115, 0.082),
			ViewUtil.flat([Color(0.85, 0.20, 0.15), Color(0.20, 0.70, 0.35), Color(0.30, 0.32, 0.36), Color(0.30, 0.32, 0.36)][i]))
	for gx: float in [-0.14, 0.14]:
		var boss := ViewUtil.cylinder(self, 0.02, 0.04, Vector3(gx, 1.12, 0.07), dark)
		boss.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.14, 0.035, 0.004), Vector3(0.08, 1.62, 0.08), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	_screen = Label3D.new()
	_screen.position = Vector3(0, 1.38, 0.09)
	_screen.font_size = 30
	_screen.pixel_size = 0.0028
	_screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen.modulate = Color(0.55, 0.95, 0.65)
	_screen.visibility_range_end = 25.0
	add_child(_screen)
	ViewUtil.label(self, pid.comp_name, Vector3(0, 1.78, 0))
	ViewUtil.interact_body(self, Vector3(0.55, 0.9, 0.35), Vector3(0, 1.3, 0))


func _process(_delta: float) -> void:
	_screen.text = "SP %.1f\nPV %.1f\nOUT %.0f%%\n%s" % [
		pid.sp, pid.pv.value, pid.output, pid.mode.to_upper()]


func describe() -> String:
	return "%s — PID (E toggles auto/manual)\nSP %.1f · PV %.1f · OUT %.0f %% · Kp %.1f Ki %.2f Kd %.2f" % [
		pid.comp_name, pid.sp, pid.pv.value, pid.output, pid.kp, pid.ki, pid.kd]


func use() -> void:
	pid.set_mode("manual" if pid.mode == "auto" else "auto")
	if pid.mode == "manual":
		pid.manual_out = pid.output  # bumpless: hold the last output
