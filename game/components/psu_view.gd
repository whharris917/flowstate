class_name PsuView
extends Node3D
## Renders a SimPowerSupply: a finned converter box on a stand,
## 480VAC in one side, 24VDC out the other, with a live DC-OK lamp.

var psu: SimPowerSupply
var _lamp: MeshInstance3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D


func setup(psu_: SimPowerSupply) -> void:
	psu = psu_
	ViewUtil.box(self, Vector3(0.08, 1.0, 0.08), Vector3(0, 0.5, 0),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	ViewUtil.box(self, Vector3(0.5, 0.5, 0.28), Vector3(0, 1.2, 0),
		ViewUtil.flat(Color(0.35, 0.55, 0.40)))
	for i in range(5):
		ViewUtil.box(self, Vector3(0.5, 0.06, 0.02), Vector3(0, 1.02 + i * 0.09, 0.15),
			ViewUtil.flat(Color(0.28, 0.44, 0.32)))
	_lamp_on = ViewUtil.glow(Color(0.30, 0.95, 0.45), 1.6)
	_lamp_off = ViewUtil.flat(Color(0.20, 0.30, 0.22))
	_lamp = ViewUtil.box(self, Vector3(0.07, 0.07, 0.03), Vector3(0.15, 1.38, 0.15), _lamp_off)
	var tag := ViewUtil.label(self, "480VAC → 24VDC", Vector3(0, 1.62, 0))
	tag.font_size = 24
	ViewUtil.label(self, psu.comp_name, Vector3(0, 1.80, 0))
	ViewUtil.interact_body(self, Vector3(0.6, 1.5, 0.4), Vector3(0, 0.85, 0))


func _process(_delta: float) -> void:
	_lamp.material_override = _lamp_on if psu.dc_out.value > 0.5 else _lamp_off


func describe() -> String:
	var state := "DC OK" if psu.dc_out.value > 0.5 else ("AC in, starting" \
		if psu.ac_in.value > 0.5 else "DEAD — no 480VAC feed")
	return "%s — control power supply\n%s" % [psu.comp_name, state]


func use() -> void:
	pass
