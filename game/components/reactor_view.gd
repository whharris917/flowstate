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
	_label.text = "%.0f °C · %.0f %% pure" % [reactor.temp_c, reactor.purity_frac * 100.0]


func describe() -> String:
	return "%s — stirred reactor\n%.0f / %.0f L · %.1f °C · purity %.1f %% · agitator %s\noverflowed %.1f L" % [
		reactor.comp_name, reactor.volume_l, reactor.capacity_l, reactor.temp_c,
		reactor.purity_frac * 100.0, "RUNNING" if reactor.agitating else "OFF (unmixed!)",
		reactor.overflowed_l]


func use() -> void:
	pass
