class_name HeatExchangerView
extends Node3D
## Renders a SimHeatExchanger: shell-and-tube on saddles with colored
## channel heads and a live duty readout; hisses softly under load.

var hx: SimHeatExchanger
var _label: Label3D
var _hiss: EquipmentAudio
var _trap_t: float = 4.5


func setup(hx_: SimHeatExchanger) -> void:
	hx = hx_
	var steel := ViewUtil.flat(Color(0.62, 0.64, 0.67))
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	for saddle_x: float in [-0.5, 0.5]:
		ViewUtil.box(self, Vector3(0.22, 0.32, 0.6), Vector3(saddle_x, 0.16, 0), dark)
	var shell := ViewUtil.cylinder(self, 0.30, 1.6, Vector3(0, 0.45, 0), steel)
	shell.rotation_degrees = Vector3(0, 0, 90)
	for head: Array in [[-0.87, Color(0.55, 0.30, 0.16)], [0.87, Color(0.20, 0.42, 0.65)]]:
		var channel := ViewUtil.cylinder(self, 0.32, 0.18, Vector3(head[0], 0.45, 0),
			ViewUtil.flat(head[1]))
		channel.rotation_degrees = Vector3(0, 0, 90)
	for flange_x: float in [-0.78, 0.78]:
		var ring := ViewUtil.cylinder(self, 0.35, 0.05, Vector3(flange_x, 0.45, 0), steel)
		ring.rotation_degrees = Vector3(0, 0, 90)
	_label = ViewUtil.label(self, "", Vector3(0, 1.0, 0))
	_label.font_size = 26
	ViewUtil.label(self, hx.comp_name, Vector3(0, 1.2, 0))
	ViewUtil.interact_body(self, Vector3(1.9, 0.9, 0.75), Vector3(0, 0.45, 0))
	_hiss = EquipmentAudio.make(self, "res://audio/steam_loop.wav",
		Vector3(0, 0.75, 0), -20.0, 0.9)


func _process(delta: float) -> void:
	_label.text = "%.0f kW" % hx.duty_kw
	_hiss.set_running(hx.duty_kw > 10.0)
	# Condensate trap on the channel head: cycles only under real load,
	# offset from the boiler's trap so the two never sync up.
	if hx.duty_kw > 10.0:
		_trap_t -= delta
		if _trap_t <= 0.0:
			_trap_t = 9.0
			EquipmentAudio.play_once(self, "res://audio/trap_burst.wav",
				Vector3(0.87, 0.25, 0), -14.0, randf_range(0.8, 0.9))


func describe() -> String:
	return "%s — heat exchanger\nsteam %.2f kg/s · duty %.0f kW (max %.0f)" % [
		hx.comp_name, hx.steam_in.value, hx.duty_kw, hx.max_duty_kw]


func use() -> void:
	pass
