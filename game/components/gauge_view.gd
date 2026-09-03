class_name GaugeView
extends Node3D
## Renders a SimGauge. Free-standing, it is a round dial on a pedestal;
## mounted on a vessel, it is a transmitter housing on the shell with
## the dial on its face. The needle angle and the printed value are the
## record's actual reading, nothing else.

var gauge: SimGauge
var mounted: bool = false
var _needle_root: Node3D
var _value_label: Label3D


func setup(gauge_: SimGauge, mounted_: bool = false) -> void:
	gauge = gauge_
	mounted = mounted_
	if mounted:
		_build_mounted()
	else:
		_build_pedestal()


## A dial on a post, for anything that stands in the plant: an inline
## flow meter, a pressure gauge on a tapping.
func _build_pedestal() -> void:
	ViewUtil.box(self, Vector3(0.08, 1.2, 0.08), Vector3(0, 0.6, 0),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	if gauge.kind == "flow":
		# The line runs through it: a short spool at the base with the
		# element in it, flanged both ends.
		var steel := ViewUtil.flat(Color(0.45, 0.47, 0.50))
		var spool := ViewUtil.cylinder(self, 0.07, 0.5, Vector3(0, 0.32, 0), steel)
		spool.rotation_degrees = Vector3(0, 0, 90)
		ViewUtil.box(self, Vector3(0.22, 0.2, 0.2), Vector3(0, 0.32, 0),
			ViewUtil.flat(Color(0.30, 0.31, 0.33)))
	_build_dial(Vector3(0, 1.32, 0), Vector3(0, 1.02, 0.06))
	ViewUtil.label(self, gauge.comp_name, Vector3(0, 1.68, 0))
	ViewUtil.interact_body(self, Vector3(0.55, 0.6, 0.3), Vector3(0, 1.3, 0))


## A transmitter on the shell. Local +x is the outward normal of the
## vessel at the mount, so the housing sits proud of the shell and the
## dial faces out; the signal gland is underneath.
func _build_mounted() -> void:
	var housing := ViewUtil.box(self, Vector3(0.14, 0.34, 0.30), Vector3(0.07, 0, 0),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	housing.rotation_degrees = Vector3.ZERO
	var dial := Node3D.new()
	dial.position = Vector3(0.14, 0.02, 0)
	dial.rotation_degrees = Vector3(0, 90, 0)  # face along +x
	add_child(dial)
	_build_dial_into(dial, Vector3.ZERO, Vector3(0, -0.2, 0.06), 0.11)
	ViewUtil.label(self, gauge.comp_name, Vector3(0.1, 0.36, 0))
	ViewUtil.interact_body(self, Vector3(0.3, 0.4, 0.36), Vector3(0.1, 0, 0))


func _build_dial(center: Vector3, label_pos: Vector3) -> void:
	_build_dial_into(self, center, label_pos, 0.22)


func _build_dial_into(parent: Node3D, center: Vector3, label_pos: Vector3, radius: float) -> void:
	var face := ViewUtil.cylinder(parent, radius, 0.06, center,
		ViewUtil.flat(Color(0.92, 0.92, 0.90)))
	face.rotation_degrees = Vector3(90, 0, 0)
	var rim := ViewUtil.cylinder(parent, radius + 0.02, 0.04, center + Vector3(0, 0, -0.012),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	rim.rotation_degrees = Vector3(90, 0, 0)
	_needle_root = Node3D.new()
	_needle_root.position = center + Vector3(0, 0, 0.045)
	parent.add_child(_needle_root)
	ViewUtil.box(_needle_root, Vector3(0.02, radius * 0.77, 0.015), Vector3(0, radius * 0.34, 0),
		ViewUtil.flat(Color(0.85, 0.20, 0.15)))
	_value_label = ViewUtil.label(parent, "", label_pos)
	_value_label.font_size = 30 if radius > 0.15 else 22


func _process(_delta: float) -> void:
	var frac := clampf(gauge.reading / gauge.full_scale(), 0.0, 1.0)
	# Zero at 7 o'clock, full scale at 5 o'clock, like a real dial.
	_needle_root.rotation_degrees = Vector3(0, 0, 135.0 - 270.0 * frac)
	_value_label.text = "%.1f %s" % [gauge.reading, gauge.units()]


func describe() -> String:
	var wired := "wired" if gauge.is_wired() else "NOT CONNECTED"
	if mounted:
		wired = "on the vessel"
	return "%s — %.2f %s (%s)\nfull scale %.0f %s" % [
		gauge.comp_name, gauge.reading, gauge.units(), wired,
		gauge.full_scale(), gauge.units()]


## One line for the vessel it is mounted on to repeat.
func summary() -> String:
	return "%s %.1f %s" % [gauge.comp_name, gauge.reading, gauge.units()]


func use() -> void:
	pass
