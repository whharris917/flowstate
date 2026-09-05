class_name CrystallizerView
extends Node3D
## Renders a SimCrystallizer: a cooled, agitated vessel with a coolant
## jacket, a slow sweep agitator that genuinely turns when the drive is
## powered, and a sight strip that goes from clear liquor to a dense
## white slurry as real crystals come out of solution.
##
## Every visual here is driven off sim state: the strip height is the
## inventory, its colour is the solids fraction, and the frost band on
## the jacket tracks how far below ambient the batch actually is.

var crystallizer: SimCrystallizer
var _shaft: Node3D
var _strip: MeshInstance3D
var _frost: MeshInstance3D
var _label: Label3D
var _motor: EquipmentAudio
var _nucleated: bool = false
var _alarm_t: float = 0.0


func setup(crystallizer_: SimCrystallizer) -> void:
	crystallizer = crystallizer_
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	steel.metallic = 0.5
	steel.roughness = 0.32
	var jacket := ViewUtil.flat(Color(0.38, 0.48, 0.58))
	ViewUtil.cylinder(self, 0.80, 0.1, Vector3(0, 0.05, 0),
		ViewUtil.flat(Color(0.34, 0.35, 0.37)))
	for leg_angle in range(4):
		var ang := TAU / 4.0 * leg_angle + 0.4
		ViewUtil.box(self, Vector3(0.11, 0.42, 0.11),
			Vector3(cos(ang) * 0.58, 0.21, sin(ang) * 0.58),
			ViewUtil.flat(Color(0.20, 0.21, 0.23)))
	ViewUtil.cylinder(self, 0.72, 1.7, Vector3(0, 1.15, 0), steel)
	# Coolant jacket, and a frost band that thickens as it gets cold.
	ViewUtil.cylinder(self, 0.78, 1.0, Vector3(0, 0.95, 0), jacket)
	_frost = ViewUtil.cylinder(self, 0.79, 0.9, Vector3(0, 0.95, 0),
		ViewUtil.flat(Color(0.85, 0.92, 0.97)))
	var head := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.72
	dome.height = 0.7
	head.mesh = dome
	head.material_override = steel
	head.position = Vector3(0, 2.0, 0)
	add_child(head)
	# Vessel furniture: cladding bands on the jacket, two flanged
	# coolant connections, a manway on the head, a round sight port,
	# sample valves at the two taps, the drive's fan cowl, a nameplate.
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	var bolt_mat := ViewUtil.flat(Color(0.35, 0.36, 0.38))
	var band := ViewUtil.flat(Color(0.70, 0.73, 0.76))
	for i in 3:
		ViewUtil.cylinder(self, 0.79, 0.02, Vector3(0, 0.6 + i * 0.35, 0), band)
	for jn: Array in [[0.6, 0.3], [1.3, -0.3]]:
		var jy := float(jn[0])
		var jz := float(jn[1])
		var neck := ViewUtil.cylinder(self, 0.045, 0.16, Vector3(0.84, jy, jz), jacket)
		neck.rotation_degrees = Vector3(0, 0, 90)
		var flange := ViewUtil.cylinder(self, 0.08, 0.03, Vector3(0.925, jy, jz), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	var mw := Vector3(0.0, 2.22, -0.38)
	ViewUtil.cylinder(self, 0.17, 0.06, mw, steel)
	ViewUtil.cylinder(self, 0.21, 0.03, mw + Vector3(0, 0.045, 0), steel)
	for i in 12:
		var a := TAU / 12.0 * i
		ViewUtil.cylinder(self, 0.011, 0.03, mw + Vector3(cos(a) * 0.19, 0.07, sin(a) * 0.19), bolt_mat)
	var sight := ViewUtil.cylinder(self, 0.12, 0.05, Vector3(0.3, 1.55, 0.68), steel)
	sight.rotation_degrees = Vector3(90, 0, 0)
	var glass := ViewUtil.cylinder(self, 0.09, 0.01, Vector3(0.3, 1.55, 0.71), ViewUtil.flat(Color(0.80, 0.88, 0.92, 0.5)))
	glass.rotation_degrees = Vector3(90, 0, 0)
	for ty: float in [1.1, 1.6]:
		var sv := ViewUtil.cylinder(self, 0.03, 0.08, Vector3(-0.78, ty - 0.08, 0), steel)
		sv.rotation_degrees = Vector3(0, 0, 90)
		ViewUtil.box(self, Vector3(0.02, 0.06, 0.02), Vector3(-0.8, ty - 0.04, 0), ViewUtil.flat(Color(0.75, 0.20, 0.15)))
	ViewUtil.cylinder(self, 0.19, 0.05, Vector3(0, 2.68, 0), dark)
	ViewUtil.box(self, Vector3(0.22, 0.10, 0.005), Vector3(-0.35, 1.85, 0.62), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	# Slow sweep agitator: a crystallizer turns lazily, not like a
	# reactor. The shaft only moves when the drive is really powered.
	ViewUtil.cylinder(self, 0.18, 0.32, Vector3(0, 2.5, 0),
		ViewUtil.flat(Color(0.30, 0.45, 0.55)))
	_shaft = Node3D.new()
	_shaft.position = Vector3(0, 2.3, 0)
	add_child(_shaft)
	ViewUtil.cylinder(_shaft, 0.032, 0.28, Vector3.ZERO,
		ViewUtil.flat(Color(0.45, 0.47, 0.50)))
	ViewUtil.box(_shaft, Vector3(0.9, 0.03, 0.07), Vector3(0, -0.11, 0),
		ViewUtil.flat(Color(0.45, 0.47, 0.50)))
	# Sight strip.
	ViewUtil.box(self, Vector3(0.1, 1.7, 0.03), Vector3(0, 1.15, 0.735),
		ViewUtil.flat(Color(0.30, 0.31, 0.33)))
	_strip = ViewUtil.box(self, Vector3(0.05, 1.0, 0.03), Vector3.ZERO,
		ViewUtil.glow(Color(0.55, 0.72, 0.85), 0.3))
	_label = ViewUtil.label(self, "", Vector3(0, 2.75, 0))
	_label.font_size = 28
	ViewUtil.label(self, crystallizer.comp_name, Vector3(0, 3.0, 0))
	ViewUtil.interact_body(self, Vector3(1.7, 2.4, 1.7), Vector3(0, 1.2, 0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 2.5, 0), -14.0, 0.55)


func _process(delta: float) -> void:
	if crystallizer.agitating:
		_shaft.rotate_y(delta * 1.8)   # slow sweep, not a reactor whisk
	_motor.set_running(crystallizer.agitating)

	var frac := clampf(crystallizer.volume_l / crystallizer.capacity_l, 0.0, 1.0)
	var column := maxf(1.66 * frac, 0.005)
	_strip.scale = Vector3(1, column, 1)
	_strip.position = Vector3(0, 0.32 + column / 2.0, 0.745)
	# Clear liquor through to dense white slurry, straight off the real
	# solids fraction.
	var mat := _strip.material_override as StandardMaterial3D
	var tint := Color(0.45, 0.66, 0.82).lerp(Color(0.94, 0.95, 0.97),
		clampf(crystallizer.solids_frac * 2.5, 0.0, 1.0))
	mat.albedo_color = tint
	mat.emission = tint

	# Frost on the jacket: how far below ambient the batch actually is.
	var chill := clampf(
		(SimStream.AMBIENT_C - crystallizer.temp_c) / 15.0, 0.0, 1.0)
	var frost_mat := _frost.material_override as StandardMaterial3D
	frost_mat.albedo_color = Color(0.85, 0.92, 0.97, chill)
	_frost.visible = chill > 0.02
	_frost.scale = Vector3(1, 0.15 + 0.85 * chill, 1)

	_label.text = "%.0f °C · %.0f %% solids" % [
		crystallizer.temp_c, crystallizer.solids_frac * 100.0]

	# The batch first dropping crystals is worth hearing: a single
	# chime on the real nucleation edge, with hysteresis so a batch
	# hovering at the boundary does not chatter.
	if crystallizer.solids_frac >= 0.02 and not _nucleated:
		_nucleated = true
		EquipmentAudio.play_once(self, "res://audio/beep.wav",
			Vector3(0, 2.6, 0), -9.0, 1.35)
	elif crystallizer.solids_frac < 0.005:
		_nucleated = false

	if frac > 0.95:
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = 1.6
			EquipmentAudio.play_once(self, "res://audio/beep.wav",
				Vector3(0, 2.6, 0), -6.0, 1.0)
	else:
		_alarm_t = 0.0


func describe() -> String:
	var state := "supersaturated" if crystallizer.supersaturation > 0.0 else "undersaturated"
	return "%s — cooling crystallizer\n%.0f / %.0f L · %.1f °C · solids %.1f %%\n%s (saturation %.1f %% at this temperature)\nagitator %s" % [
		crystallizer.comp_name, crystallizer.volume_l, crystallizer.capacity_l,
		crystallizer.temp_c, crystallizer.solids_frac * 100.0, state,
		crystallizer.saturation_frac * 100.0,
		"RUNNING" if crystallizer.agitating else "OFF (crystallizing slowly!)"]


func use() -> void:
	pass
