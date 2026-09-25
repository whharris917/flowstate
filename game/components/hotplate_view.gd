class_name HotplateView
extends BenchView
## Renders a SimHotplate: a white enamel body with a square ceramic
## plate on top, two knobs (heat, stir) on the sloping front, an amber
## lamp lit while the element is on (it cycles with the thermostat, and
## the relay clicks each time), a green lamp while it stirs, and a
## display showing the setpoint and what the probe reads. The probe
## hangs from a rod at the back into the vessel on the plate. The stir
## motor hums while it turns.

var plate: SimHotplate
var _heat_lamp: StandardMaterial3D
var _stir_lamp: StandardMaterial3D
var _plate_mat: StandardMaterial3D
var _display: Label3D
var _probe: MeshInstance3D
var _motor: EquipmentAudio
var _was_heating := false
var _last_rpm := 400.0


func _build() -> void:
	plate = record as SimHotplate
	var enamel := ViewUtil.painted(Color(0.90, 0.90, 0.88))
	var dark := ViewUtil.matte(Color(0.12, 0.12, 0.13))
	# Body: 20 x 30 cm, the plate end raised, the controls on a slope
	# at the front (-z).
	ViewUtil.box(self, Vector3(0.20, HOTPLATE_TOP - 0.012, 0.22), Vector3(0, (HOTPLATE_TOP - 0.012) / 2.0, 0.03), enamel)
	var slope := ViewUtil.box(self, Vector3(0.20, 0.07, 0.09), Vector3(0, 0.035, -0.115), enamel)
	slope.rotation.x = -0.35
	_plate_mat = ViewUtil.matte(Color(0.93, 0.93, 0.91))
	_plate_mat.roughness = 0.4
	ViewUtil.box(self, Vector3(0.18, 0.012, 0.18), Vector3(0, HOTPLATE_TOP - 0.006, 0.03), _plate_mat)
	for x: float in [-0.055, 0.055]:
		var knob := ViewUtil.cylinder(self, 0.016, 0.02, Vector3(x, 0.05, -0.155), dark)
		knob.rotation.x = PI / 2.0 - 0.35
	_heat_lamp = ViewUtil.glow(Color(1.0, 0.55, 0.1), 0.0)
	_stir_lamp = ViewUtil.glow(Color(0.2, 0.9, 0.35), 0.0)
	ViewUtil.cylinder(self, 0.004, 0.004, Vector3(-0.055, 0.082, -0.138), _heat_lamp).rotation.x = PI / 2.0 - 0.35
	ViewUtil.cylinder(self, 0.004, 0.004, Vector3(0.055, 0.082, -0.138), _stir_lamp).rotation.x = PI / 2.0 - 0.35
	_display = Label3D.new()
	_display.font_size = 28
	_display.pixel_size = 0.0006
	_display.modulate = Color(1.0, 0.45, 0.2)
	_display.outline_size = 0
	_display.position = Vector3(0, 0.058, -0.152)
	_display.rotation = Vector3(-0.35, PI, 0)
	_display.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(_display)
	ViewUtil.box(self, Vector3(0.07, 0.022, 0.002), Vector3(0, 0.058, -0.150), dark).rotation.x = -0.35
	# The probe stand: a rod at the back corner, an arm over the plate,
	# the probe hanging from it into whatever stands there.
	var steel := ViewUtil.steel()
	ViewUtil.cylinder(self, 0.005, 0.42, Vector3(0.085, 0.21, 0.13), steel)
	ViewUtil.box(self, Vector3(0.09, 0.008, 0.008), Vector3(0.04, 0.40, 0.13), steel)
	ViewUtil.box(self, Vector3(0.008, 0.008, 0.10), Vector3(0.0, 0.40, 0.08), steel)
	_probe = MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.0025
	rod.bottom_radius = 0.0025
	rod.height = 1.0
	_probe.mesh = rod
	_probe.material_override = steel
	add_child(_probe)
	var tag := ViewUtil.label(self, plate.comp_name, Vector3(0, 0.5, 0.03))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.21, HOTPLATE_TOP, 0.31), Vector3(0, HOTPLATE_TOP / 2.0, 0.0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav", Vector3(0, 0.05, 0.03), -24.0, 2.2)


func radius() -> float:
	return 0.16


func _process(_delta: float) -> void:
	if plate == null:
		return
	_heat_lamp.emission_energy_multiplier = 1.4 if plate.heater_on else 0.0
	_heat_lamp.albedo_color = Color(1.0, 0.55, 0.1) if plate.heater_on else Color(0.3, 0.2, 0.1)
	var stirring := plate.stir_rpm > 0.0
	_stir_lamp.emission_energy_multiplier = 1.2 if stirring else 0.0
	_stir_lamp.albedo_color = Color(0.2, 0.9, 0.35) if stirring else Color(0.1, 0.2, 0.12)
	_motor.set_running(stirring)
	if plate.heater_on != _was_heating:
		_was_heating = plate.heater_on
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3(0, 0.05, -0.1), -14.0,
			1.1 if plate.heater_on else 0.95)
	var set_text := "%d" % int(round(plate.setpoint_c)) if plate.setpoint_c > SimHotplate.AMBIENT_C else "OFF"
	_display.text = "%s  %.1f°C" % [set_text, plate.probe_c]
	# A plate much above the room shows it: the ceramic warms toward a
	# dull tan, as a hot one does, so a hot plate is not invisible.
	var hot := clampf((plate.plate_c - 60.0) / 300.0, 0.0, 1.0)
	_plate_mat.albedo_color = Color(0.93, 0.93, 0.91).lerp(Color(0.80, 0.70, 0.58), hot)
	# The probe dips to near the bottom of the vessel on the plate, or
	# hangs short with nothing there.
	var bottom := HOTPLATE_TOP + 0.05
	if plate.load != null:
		bottom = HOTPLATE_TOP + 0.012
	var top := 0.40
	_probe.position = Vector3(0.0, (top + bottom) / 2.0, 0.03)
	_probe.scale = Vector3(1, top - bottom, 1)


func use() -> void:
	if plate.stir_rpm > 0.0:
		_last_rpm = plate.stir_rpm
		plate.stir_rpm = 0.0
	else:
		plate.stir_rpm = _last_rpm


func describe() -> String:
	var heat := "heat off" if plate.setpoint_c <= SimHotplate.AMBIENT_C \
		else "set %d °C%s" % [int(round(plate.setpoint_c)), " · element on" if plate.heater_on else ""]
	var stir := "stirring at %d rpm" % int(plate.stir_rpm) if plate.stir_rpm > 0.0 else "not stirring"
	var probe := "probe %.1f °C in the vessel on it" % plate.probe_c if plate.load != null \
		else "nothing on the plate · plate %.0f °C" % plate.plate_c
	return "%s — hotplate stirrer\n%s · %s\n%s\n[E] stirrer on/off · double-click to set heat and speed" % [
		plate.comp_name, heat, stir, probe]
