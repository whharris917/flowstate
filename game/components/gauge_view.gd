class_name GaugeView
extends Node3D
## Renders a SimGauge: a round dial on a pedestal. The needle angle and
## the printed value are the record's actual reading, nothing else.

var gauge: SimGauge
var _needle_root: Node3D
var _value_label: Label3D


func setup(gauge_: SimGauge) -> void:
	gauge = gauge_
	ViewUtil.box(self, Vector3(0.08, 1.2, 0.08), Vector3(0, 0.6, 0),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	var face := ViewUtil.cylinder(self, 0.22, 0.06, Vector3(0, 1.32, 0),
		ViewUtil.flat(Color(0.92, 0.92, 0.90)))
	face.rotation_degrees = Vector3(90, 0, 0)
	var rim := ViewUtil.cylinder(self, 0.24, 0.04, Vector3(0, 1.32, -0.012),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	rim.rotation_degrees = Vector3(90, 0, 0)

	_needle_root = Node3D.new()
	_needle_root.position = Vector3(0, 1.32, 0.045)
	add_child(_needle_root)
	ViewUtil.box(_needle_root, Vector3(0.02, 0.17, 0.015), Vector3(0, 0.075, 0),
		ViewUtil.flat(Color(0.85, 0.20, 0.15)))

	_value_label = ViewUtil.label(self, "", Vector3(0, 1.02, 0.06))
	_value_label.font_size = 30
	ViewUtil.label(self, gauge.comp_name, Vector3(0, 1.68, 0))
	ViewUtil.interact_body(self, Vector3(0.55, 0.6, 0.3), Vector3(0, 1.3, 0))


func _process(_delta: float) -> void:
	var frac := clampf(gauge.reading / gauge.full_scale(), 0.0, 1.0)
	# Zero at 7 o'clock, full scale at 5 o'clock, like a real dial.
	_needle_root.rotation_degrees = Vector3(0, 0, 135.0 - 270.0 * frac)
	_value_label.text = "%.1f %s" % [gauge.reading, gauge.units()]


func describe() -> String:
	var wired := "wired" if gauge.is_wired() else "NOT CONNECTED"
	return "%s — %.2f %s (%s)\nfull scale %.0f %s" % [
		gauge.comp_name, gauge.reading, gauge.units(), wired,
		gauge.full_scale(), gauge.units()]


func use() -> void:
	pass
