class_name PIDView
extends Node3D
## Renders a SimPID as a panel-mount controller on a stand: faceplate
## with live SP / PV / OUT text straight from the record. E toggles
## auto/manual — the operator's hand switch.

var pid: SimPID
var _screen: Label3D


func setup(pid_: SimPID) -> void:
	pid = pid_
	ViewUtil.box(self, Vector3(0.08, 1.1, 0.08), Vector3(0, 0.55, 0),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	ViewUtil.box(self, Vector3(0.44, 0.60, 0.14), Vector3(0, 1.35, 0),
		ViewUtil.flat(Color(0.13, 0.14, 0.16)))
	ViewUtil.box(self, Vector3(0.36, 0.44, 0.02), Vector3(0, 1.38, 0.075),
		ViewUtil.glow(Color(0.05, 0.10, 0.08), 0.4))
	_screen = Label3D.new()
	_screen.position = Vector3(0, 1.38, 0.09)
	_screen.font_size = 30
	_screen.pixel_size = 0.0028
	_screen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_screen.modulate = Color(0.55, 0.95, 0.65)
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
