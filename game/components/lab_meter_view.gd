class_name LabMeterView
extends BenchView
## Renders a SimLabMeter: a benchtop pH and temperature meter, its
## display reading what the probe reads, and an electrode on a swing arm
## reaching to its right (+x). A vessel standing where the electrode
## hangs has the electrode in it.

var meter: SimLabMeter
var _display: Label3D


func _build() -> void:
	meter = record as SimLabMeter
	var case_mat := ViewUtil.painted(Color(0.28, 0.32, 0.36))
	var dark := ViewUtil.matte(Color(0.08, 0.09, 0.10))
	ViewUtil.box(self, Vector3(0.16, 0.05, 0.20), Vector3(0, 0.025, 0), case_mat)
	var face := ViewUtil.box(self, Vector3(0.16, 0.06, 0.10), Vector3(0, 0.07, 0.03), case_mat)
	face.rotation.x = 0.5
	var screen := ViewUtil.box(self, Vector3(0.11, 0.045, 0.003), Vector3(0, 0.074, -0.004), dark)
	screen.rotation.x = 0.5
	_display = Label3D.new()
	_display.font_size = 30
	_display.pixel_size = 0.0007
	_display.modulate = Color(0.55, 0.95, 0.6)
	_display.outline_size = 0
	_display.position = Vector3(0, 0.074, -0.007)
	_display.rotation = Vector3(0.5, PI, 0)
	add_child(_display)
	# The electrode arm: a post at the right rear, an arm to the probe's
	# point, the electrode hanging to a bench's height below it.
	var steel := ViewUtil.steel()
	ViewUtil.cylinder(self, 0.005, 0.28, Vector3(0.09, 0.14, 0.07), steel)
	ViewUtil.box(self, Vector3(METER_REACH.x - 0.09 + 0.01, 0.01, 0.012),
		Vector3((METER_REACH.x + 0.09) / 2.0, 0.27, 0.07), steel)
	ViewUtil.box(self, Vector3(0.012, 0.01, 0.07), Vector3(METER_REACH.x, 0.27, 0.035), steel)
	var electrode := ViewUtil.cylinder(self, 0.006, 0.20, METER_REACH + Vector3(0, 0.17, 0), ViewUtil.flat(Color(0.8, 0.88, 0.92, 0.5)))
	electrode.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ViewUtil.cylinder(self, 0.008, 0.03, METER_REACH + Vector3(0, 0.26, 0), dark)
	var tag := ViewUtil.label(self, meter.comp_name, Vector3(0, 0.25, 0))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.17, 0.12, 0.21), Vector3(0, 0.06, 0))


func radius() -> float:
	return 0.11


func _process(_delta: float) -> void:
	if meter == null:
		return
	var ph := "pH --.--" if is_nan(meter.ph) else "pH %5.2f" % meter.ph
	var temp := "--.- °C" if is_nan(meter.temp_c) else "%.1f °C" % meter.temp_c
	_display.text = "%s\n%s" % [ph, temp]


func describe() -> String:
	var where := "electrode in %s" % meter.target.comp_name if meter.target != null \
		else "electrode in nothing · stand a vessel under it"
	var ph := "no reading" if is_nan(meter.ph) else "pH %.2f" % meter.ph
	var temp := "" if is_nan(meter.temp_c) else " · %.1f °C" % meter.temp_c
	return "%s — pH and temperature meter\n%s\n%s%s" % [meter.comp_name, where, ph, temp]
