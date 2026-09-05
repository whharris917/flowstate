class_name DryerView
extends Node3D
## Renders a SimDryer: a heated tumbling drum on a skid. The drum turns
## only when the machine is really running, and the vapour plume above
## the vent is throttled by the actual evaporation rate — no plume when
## the cake is already dry, however hot the duty.

var dryer: SimDryer
var _drum: Node3D
var _label: Label3D
var _motor: EquipmentAudio
var _plume: VaporPlume
var _was_running: bool = false


func setup(dryer_: SimDryer) -> void:
	dryer = dryer_
	var steel := ViewUtil.flat(Color(0.58, 0.62, 0.66))
	steel.metallic = 0.45
	steel.roughness = 0.4
	var shell := ViewUtil.flat(Color(0.50, 0.44, 0.38))
	# Skid and end frames.
	ViewUtil.box(self, Vector3(1.6, 0.12, 1.1), Vector3(0, 0.06, 0),
		ViewUtil.flat(Color(0.24, 0.25, 0.27)))
	for side in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.1, 0.95, 0.9), Vector3(0.72 * side, 0.55, 0),
			ViewUtil.flat(Color(0.28, 0.29, 0.31)))
	# The drum itself, lying on its side and turning about X.
	_drum = Node3D.new()
	_drum.position = Vector3(0, 1.05, 0)
	add_child(_drum)
	var barrel := ViewUtil.cylinder(_drum, 0.44, 1.25, Vector3.ZERO, shell)
	barrel.rotation_degrees = Vector3(0, 0, 90)
	# Lifter flights inside, visible as ribs on the shell.
	for i in range(4):
		var ang := TAU / 4.0 * i
		var rib := ViewUtil.box(_drum, Vector3(1.2, 0.04, 0.1),
			Vector3(0, cos(ang) * 0.44, sin(ang) * 0.44), steel)
		rib.rotation = Vector3(ang, 0, 0)
	# Heating band and the vapour vent.
	ViewUtil.cylinder(self, 0.47, 0.3, Vector3(0, 1.05, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16))).rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.09, 0.45, Vector3(0, 1.6, 0), steel)
	# Machine furniture: trunnion rollers under the drum, a ring gear
	# with the drive motor at the power fitting, the heater control box
	# at the duty fitting, a cyclone on the vent, an inspection door on
	# the drum end, and a nameplate on the frame.
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	for rx: float in [-0.45, 0.45]:
		for rz: float in [-0.3, 0.3]:
			var roller := ViewUtil.cylinder(self, 0.08, 0.14, Vector3(rx, 0.6, rz), dark)
			roller.rotation_degrees = Vector3(0, 0, 90)
			ViewUtil.box(self, Vector3(0.12, 0.35, 0.08), Vector3(rx, 0.35, rz), ViewUtil.flat(Color(0.28, 0.29, 0.31)))
	var gear := ViewUtil.cylinder(self, 0.49, 0.06, Vector3(-0.35, 1.05, 0), dark)
	gear.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.26, 0.24, 0.26), Vector3(-0.3, 0.44, 0.52), ViewUtil.flat(Color(0.16, 0.36, 0.62)))
	var motor := ViewUtil.cylinder(self, 0.12, 0.3, Vector3(-0.3, 0.44, 0.52), ViewUtil.flat(Color(0.16, 0.36, 0.62)))
	motor.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.cylinder(self, 0.05, 0.08, Vector3(-0.3, 0.62, 0.52), steel)
	ViewUtil.box(self, Vector3(0.22, 0.22, 0.12), Vector3(0.3, 0.42, 0.55), ViewUtil.flat(Color(0.62, 0.63, 0.66)))
	ViewUtil.box(self, Vector3(0.12, 0.05, 0.005), Vector3(0.3, 0.46, 0.612), ViewUtil.glow(Color(0.35, 0.75, 0.95), 0.6))
	ViewUtil.cylinder(self, 0.16, 0.22, Vector3(0, 1.93, 0), steel)
	var cone := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.16
	cone_mesh.bottom_radius = 0.05
	cone_mesh.height = 0.2
	cone.mesh = cone_mesh
	cone.material_override = steel
	cone.position = Vector3(0, 1.72, 0)
	add_child(cone)
	ViewUtil.cylinder(self, 0.05, 0.3, Vector3(0, 2.18, 0), steel)
	var door := ViewUtil.cylinder(self, 0.2, 0.04, Vector3(0.79, 1.05, 0), steel)
	door.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.box(self, Vector3(0.04, 0.06, 0.14), Vector3(0.81, 1.05, 0.12), dark)
	ViewUtil.box(self, Vector3(0.005, 0.10, 0.22), Vector3(-0.775, 0.85, 0.3), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	_label = ViewUtil.label(self, "", Vector3(0, 2.0, 0))
	_label.font_size = 26
	ViewUtil.label(self, dryer.comp_name, Vector3(0, 2.25, 0))
	ViewUtil.interact_body(self, Vector3(1.7, 1.7, 1.2), Vector3(0, 0.85, 0))
	_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 1.05, 0), -13.0, 0.7)
	_plume = VaporPlume.make(self, Vector3(0, 1.85, 0), 0.7)


func _process(delta: float) -> void:
	if dryer.running:
		_drum.rotate_x(delta * 2.2)
	_motor.set_running(dryer.running)
	# The plume is the evaporation rate, not the run state: a dry cake
	# under full duty makes no vapour.
	_plume.set_strength(clampf(dryer.evap_lps / 0.5, 0.0, 1.0))
	_label.text = "%.2f L/s off" % dryer.evap_lps if dryer.evap_lps > 0.001 \
		else ("running dry" if dryer.running else "stopped")
	if dryer.running and not _was_running:
		EquipmentAudio.play_once(self, "res://audio/clunk.wav",
			Vector3(0, 1.05, 0), -7.0, 0.85)
	elif _was_running and not dryer.running:
		EquipmentAudio.play_once(self, "res://audio/clunk.wav",
			Vector3(0, 1.05, 0), -8.0, 0.7)
	_was_running = dryer.running


func describe() -> String:
	var cake := dryer.product.stream
	return "%s — cake dryer\n%s · evaporating %.3f L/s · %.1f L driven off\ncake out: %s" % [
		dryer.comp_name, "RUNNING" if dryer.running else "STOPPED",
		dryer.evap_lps, dryer.dried_l, cake.describe()]


func use() -> void:
	dryer.is_on = not dryer.is_on
	EquipmentAudio.play_once(self, "res://audio/clunk.wav",
		Vector3(0, 1.0, 0.6), -6.0, 1.0)
