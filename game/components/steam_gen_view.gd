class_name SteamGenView
extends Node3D
## Renders a SimSteamGen: horizontal drum on saddles, firebox that
## glows when firing, stack, gauge glass, live pressure label. E
## toggles firing. Rumbles and hisses with real production.

var boiler: SimSteamGen
var _fire_mat: StandardMaterial3D
var _label: Label3D
var _rumble: EquipmentAudio
var _hiss: EquipmentAudio
var _trap_t: float = 2.0
var _plume: VaporPlume


func setup(boiler_: SimSteamGen) -> void:
	boiler = boiler_
	var steel := ViewUtil.flat(Color(0.58, 0.60, 0.63))
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	for saddle_x: float in [-0.55, 0.55]:
		ViewUtil.box(self, Vector3(0.3, 0.5, 1.0), Vector3(saddle_x, 0.25, 0), dark)
	var drum := ViewUtil.cylinder(self, 0.55, 1.8, Vector3(0, 0.8, 0), steel)
	drum.rotation_degrees = Vector3(0, 0, 90)
	for cap_x: float in [-0.9, 0.9]:
		var head := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = 0.55
		dome.height = 0.6
		head.mesh = dome
		head.material_override = steel
		head.position = Vector3(cap_x, 0.8, 0)
		head.rotation_degrees = Vector3(0, 0, -90 if cap_x > 0 else 90)
		add_child(head)
	# Firebox with a live glow, and the stack.
	_fire_mat = ViewUtil.glow(Color(0.9, 0.35, 0.08), 0.0)
	ViewUtil.box(self, Vector3(0.7, 0.35, 0.5), Vector3(0.35, 0.3, 0.45), dark)
	ViewUtil.box(self, Vector3(0.5, 0.2, 0.06), Vector3(0.35, 0.3, 0.71), _fire_mat)
	ViewUtil.cylinder(self, 0.12, 1.4, Vector3(-0.6, 2.0, 0), dark)
	# Drum furniture: a steam nozzle neck under the steam fitting, a
	# safety valve with its lever, a pressure gauge on the drum face, a
	# bolted manhole on the right head, the burner blower on the
	# firebox with its fuel line, and a nameplate.
	var brass := ViewUtil.flat(Color(0.78, 0.62, 0.30))
	var bolt_mat := ViewUtil.flat(Color(0.35, 0.36, 0.38))
	ViewUtil.cylinder(self, 0.08, 0.16, Vector3(0.35, 1.32, 0), steel)
	ViewUtil.cylinder(self, 0.12, 0.03, Vector3(0.35, 1.39, 0), steel)
	ViewUtil.cylinder(self, 0.035, 0.14, Vector3(0.7, 1.38, 0.2), steel)
	ViewUtil.cylinder(self, 0.06, 0.12, Vector3(0.7, 1.5, 0.2), brass)
	ViewUtil.box(self, Vector3(0.16, 0.015, 0.02), Vector3(0.77, 1.57, 0.2), steel)
	var pg := ViewUtil.cylinder(self, 0.07, 0.03, Vector3(-0.35, 1.02, 0.56), dark)
	pg.rotation_degrees = Vector3(90, 0, 0)
	var pf := ViewUtil.cylinder(self, 0.058, 0.006, Vector3(-0.35, 1.02, 0.576), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	pf.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.006, 0.045, 0.004), Vector3(-0.35, 1.04, 0.58), ViewUtil.flat(Color(0.85, 0.20, 0.15)))
	var manhole := ViewUtil.cylinder(self, 0.2, 0.05, Vector3(1.22, 0.9, 0), steel)
	manhole.rotation_degrees = Vector3(0, 0, 90)
	for i in 10:
		var a := TAU / 10.0 * i
		var bolt := ViewUtil.cylinder(self, 0.012, 0.03, Vector3(1.25, 0.9 + cos(a) * 0.17, sin(a) * 0.17), bolt_mat)
		bolt.rotation_degrees = Vector3(0, 0, 90)
	var blower := ViewUtil.cylinder(self, 0.13, 0.16, Vector3(0.55, 0.38, 0.79), dark)
	blower.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.cylinder(self, 0.05, 0.1, Vector3(0.55, 0.38, 0.92), ViewUtil.flat(Color(0.30, 0.31, 0.34)))
	var fuel := ViewUtil.cylinder(self, 0.02, 0.5, Vector3(0.2, 0.2, 0.75), brass)
	fuel.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.24, 0.10, 0.005), Vector3(-0.1, 0.55, 0.553), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	# Gauge glass on the drum face.
	ViewUtil.box(self, Vector3(0.05, 0.5, 0.04), Vector3(0.2, 0.8, 0.56),
		ViewUtil.flat(Color(0.80, 0.88, 0.92, 0.5)))
	_label = ViewUtil.label(self, "", Vector3(0, 1.65, 0))
	_label.font_size = 28
	ViewUtil.label(self, boiler.comp_name, Vector3(0, 1.88, 0))
	ViewUtil.interact_body(self, Vector3(2.0, 1.5, 1.2), Vector3(0, 0.75, 0))
	_rumble = EquipmentAudio.make(self, "res://audio/boiler_loop.wav",
		Vector3(0.2, 0.6, 0), -6.0, 1.0)
	_hiss = EquipmentAudio.make(self, "res://audio/steam_loop.wav",
		Vector3(0.35, 1.35, 0), -16.0, 1.1)
	_plume = VaporPlume.make(self, Vector3(-0.6, 2.75, 0), 1.0)


func _process(delta: float) -> void:
	_label.text = "%.0f kPa %s" % [boiler.press_pa / 1000.0,
		"· FIRING" if boiler.making else ("· dry!" if boiler.is_on else "· off")]
	_fire_mat.emission_energy_multiplier = 2.0 if boiler.making else 0.0
	_rumble.set_running(boiler.making)
	_hiss.set_running(boiler.making)
	_plume.set_strength(1.0 if boiler.making else 0.0)
	# The drum trap cycles while steam is being made — quicker as the
	# real header pressure builds, so the rhythm reads plant state.
	if boiler.making:
		_trap_t -= delta
		if _trap_t <= 0.0:
			var press_frac := clampf(boiler.press_pa / SimSteamGen.PRESS_FULL_PA, 0.0, 1.0)
			_trap_t = 7.0 - 4.5 * press_frac
			EquipmentAudio.play_once(self, "res://audio/trap_burst.wav",
				Vector3(-0.9, 0.45, 0.3), -10.0, randf_range(0.95, 1.05))


func describe() -> String:
	var state := "FIRING" if boiler.making else ("ON but starved" if boiler.is_on else "off")
	return "%s — steam generator, %.2f kg/s rated (E fires/stops)\n%s · header %.0f kPa · starved %.1f s" % [
		boiler.comp_name, boiler.rated_kgps, state, boiler.press_pa / 1000.0, boiler.starve_s]


func use() -> void:
	boiler.is_on = not boiler.is_on
