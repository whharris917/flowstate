class_name ReactorView
extends Node3D
## Renders a SimReactor: jacketed vessel with dished head, agitator
## motor pod whose shaft genuinely turns when the drive is powered, a
## sight strip driven by the real inventory, and a live temperature /
## purity readout. Hums when agitating.

var reactor: SimReactor
var _shaft: Node3D
var _strip: MeshInstance3D
var _label: Label3D
var _motor: EquipmentAudio
var _at_temp: bool = false
var _pure: bool = false
var _alarm_t: float = 0.0


func setup(reactor_: SimReactor) -> void:
	reactor = reactor_
	var steel := ViewUtil.flat(Color(0.60, 0.64, 0.68))
	steel.metallic = 0.5
	steel.roughness = 0.35
	var jacket := ViewUtil.flat(Color(0.44, 0.50, 0.56))
	ViewUtil.cylinder(self, 0.84, 0.1, Vector3(0, 0.05, 0),
		ViewUtil.flat(Color(0.34, 0.35, 0.37)))
	for leg_angle in range(4):
		var ang := TAU / 4.0 * leg_angle + 0.4
		ViewUtil.box(self, Vector3(0.12, 0.5, 0.12),
			Vector3(cos(ang) * 0.62, 0.25, sin(ang) * 0.62),
			ViewUtil.flat(Color(0.20, 0.21, 0.23)))
	ViewUtil.cylinder(self, 0.78, 1.9, Vector3(0, 1.35, 0), steel)
	ViewUtil.cylinder(self, 0.84, 1.1, Vector3(0, 1.1, 0), jacket)  # heating jacket
	var head := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.78
	dome.height = 0.8
	head.mesh = dome
	head.material_override = steel
	head.position = Vector3(0, 2.3, 0)
	add_child(head)
	# Agitator: motor pod, shaft that spins with the real drive state.
	ViewUtil.cylinder(self, 0.2, 0.35, Vector3(0, 2.85, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16)))
	_shaft = Node3D.new()
	_shaft.position = Vector3(0, 2.62, 0)
	add_child(_shaft)
	ViewUtil.cylinder(_shaft, 0.035, 0.3, Vector3.ZERO,
		ViewUtil.flat(Color(0.45, 0.47, 0.50)))
	ViewUtil.box(_shaft, Vector3(0.34, 0.03, 0.08), Vector3(0, -0.1, 0),
		ViewUtil.flat(Color(0.45, 0.47, 0.50)))
	# Vessel furniture: bolted head nozzles under the two feed
	# fittings, a manway with its davit on the head, a relief valve, a
	# pair of flanged jacket connections, the drive's fan cowl and
	# terminal box, and a nameplate.
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	var bolt_mat := ViewUtil.flat(Color(0.35, 0.36, 0.38))
	for nx: float in [-0.42, 0.42]:
		ViewUtil.cylinder(self, 0.07, 0.22, Vector3(nx, 2.31, 0), steel)
		ViewUtil.cylinder(self, 0.11, 0.03, Vector3(nx, 2.40, 0), steel)
		for i in 8:
			var a := TAU / 8.0 * i
			ViewUtil.cylinder(self, 0.01, 0.025, Vector3(nx + cos(a) * 0.09, 2.425, sin(a) * 0.09), bolt_mat)
	var mw := Vector3(0.0, 2.52, -0.42)
	ViewUtil.cylinder(self, 0.19, 0.06, mw, steel)
	ViewUtil.cylinder(self, 0.23, 0.03, mw + Vector3(0, 0.045, 0), steel)
	for i in 12:
		var a := TAU / 12.0 * i
		ViewUtil.cylinder(self, 0.012, 0.03, mw + Vector3(cos(a) * 0.21, 0.07, sin(a) * 0.21), bolt_mat)
	ViewUtil.box(self, Vector3(0.05, 0.55, 0.05), mw + Vector3(0.3, 0.25, 0), dark)
	ViewUtil.box(self, Vector3(0.36, 0.04, 0.04), mw + Vector3(0.12, 0.5, 0), dark)
	ViewUtil.cylinder(self, 0.04, 0.16, Vector3(0.3, 2.62, 0.38), steel)
	ViewUtil.cylinder(self, 0.07, 0.10, Vector3(0.3, 2.74, 0.38), ViewUtil.flat(Color(0.78, 0.62, 0.30)))
	ViewUtil.box(self, Vector3(0.14, 0.015, 0.02), Vector3(0.36, 2.80, 0.38), steel)
	for jn: Array in [[0.55, 0.3], [1.5, -0.3]]:
		var jz := float(jn[1])
		var jy := float(jn[0])
		var neck := ViewUtil.cylinder(self, 0.05, 0.18, Vector3(0.9, jy, jz), jacket)
		neck.rotation_degrees = Vector3(0, 0, 90)
		var flange := ViewUtil.cylinder(self, 0.085, 0.03, Vector3(0.985, jy, jz), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.21, 0.05, Vector3(0, 3.05, 0), dark)
	for i in 4:
		ViewUtil.cylinder(self, 0.215, 0.01, Vector3(0, 2.72 + i * 0.07, 0), ViewUtil.flat(Color(0.50, 0.28, 0.15)))
	ViewUtil.box(self, Vector3(0.12, 0.10, 0.08), Vector3(0.2, 2.85, 0.2), steel)
	ViewUtil.box(self, Vector3(0.24, 0.12, 0.005), Vector3(0.45, 1.9, 0.66), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	# Sight strip on the shell.
	ViewUtil.box(self, Vector3(0.1, 1.9, 0.03), Vector3(0, 1.35, 0.795),
		ViewUtil.flat(Color(0.30, 0.31, 0.33)))
	_strip = ViewUtil.box(self, Vector3(0.05, 1.0, 0.03), Vector3.ZERO,
		ViewUtil.glow(Color(0.85, 0.60, 0.20), 0.35))
	_label = ViewUtil.label(self, "", Vector3(0, 3.15, 0))
	_label.font_size = 28
	ViewUtil.label(self, reactor.comp_name, Vector3(0, 3.4, 0))
	ViewUtil.interact_body(self, Vector3(1.8, 2.6, 1.8), Vector3(0, 1.4, 0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 2.85, 0), -10.0, 0.8)


func _process(delta: float) -> void:
	if reactor.agitating:
		_shaft.rotate_y(delta * 6.0)
	_motor.set_running(reactor.agitating)
	var frac := clampf(reactor.volume_l / reactor.capacity_l, 0.0, 1.0)
	var column := maxf(1.86 * frac, 0.005)
	_strip.scale = Vector3(1, column, 1)
	_strip.position = Vector3(0, 0.42 + column / 2.0, 0.805)
	# The batch visibly changes color as it converts: reactant amber
	# through to product green, straight from the real purity.
	var mat := _strip.material_override as StandardMaterial3D
	var tint := Color(0.85, 0.55, 0.15).lerp(Color(0.15, 0.75, 0.40), reactor.purity_frac)
	mat.albedo_color = tint
	mat.emission = tint
	_label.text = "%.0f °C · %.0f %% pure" % [reactor.temp_c, reactor.purity_frac * 100.0]
	# Limit chimes with hysteresis: reaching reaction temperature, and
	# the batch clearing 90% purity, each announce themselves once.
	if reactor.temp_c >= SimReactor.REACT_MIN_C and not _at_temp:
		_at_temp = true
		EquipmentAudio.play_once(self, "res://audio/beep.wav",
			Vector3(0, 3.0, 0), -8.0, 0.75)
	elif reactor.temp_c < SimReactor.REACT_MIN_C - 3.0:
		_at_temp = false
	if reactor.purity_frac >= 0.9 and not _pure:
		_pure = true
		EquipmentAudio.play_once(self, "res://audio/beep.wav",
			Vector3(0, 3.0, 0), -8.0, 1.5)
	elif reactor.purity_frac < 0.87:
		_pure = false
	# High-level annunciator, same convention as tanks.
	if frac > 0.95:
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = 1.6
			EquipmentAudio.play_once(self, "res://audio/beep.wav",
				Vector3(0, 3.0, 0), -6.0, 1.0)
	else:
		_alarm_t = 0.0


func describe() -> String:
	return "%s — stirred reactor\n%.0f / %.0f L · %.1f °C · purity %.1f %% · agitator %s\noverflowed %.1f L" % [
		reactor.comp_name, reactor.volume_l, reactor.capacity_l, reactor.temp_c,
		reactor.purity_frac * 100.0, "RUNNING" if reactor.agitating else "OFF (unmixed!)",
		reactor.overflowed_l]


func use() -> void:
	pass
