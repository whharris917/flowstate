class_name VacLockView
extends Node3D
## Renders a SimVacuumLock: vertical chamber on legs with a dished
## head, a big main air valve block up top, a side-mounted vacuum pump
## pod, and a conical bottom with a condensate sight glass. Every
## sound is a cycle event: the pump whines through evacuation, the
## vent valve blasts once per pressure step, the drainer trips with a
## clunk and gurgles the condensate out. E starts/stops the cycle.

var lock: SimVacuumLock
var _label: Label3D
var _glass: MeshInstance3D
var _pump_audio: EquipmentAudio
var _gurgle: EquipmentAudio
var _puff: VaporPlume
var _last_bursts: int = 0
var _last_state: String = "idle"


func setup(lock_: SimVacuumLock) -> void:
	lock = lock_
	var steel := ViewUtil.flat(Color(0.66, 0.68, 0.71))
	steel.metallic = 0.45
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	for leg_angle in range(3):
		var ang := TAU / 3.0 * leg_angle + 0.5
		ViewUtil.box(self, Vector3(0.1, 0.55, 0.1),
			Vector3(cos(ang) * 0.44, 0.27, sin(ang) * 0.44), dark)
	# Conical bottom, chamber, dished head.
	var cone := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.55
	cone_mesh.bottom_radius = 0.12
	cone_mesh.height = 0.45
	cone.mesh = cone_mesh
	cone.material_override = steel
	cone.position = Vector3(0, 0.72, 0)
	add_child(cone)
	ViewUtil.cylinder(self, 0.55, 1.25, Vector3(0, 1.57, 0), steel)
	var head := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.55
	dome.height = 0.55
	head.mesh = dome
	head.material_override = steel
	head.position = Vector3(0, 2.2, 0)
	add_child(head)
	# Main air valve block and vent horn on the head.
	ViewUtil.box(self, Vector3(0.28, 0.26, 0.28), Vector3(0, 2.5, 0),
		ViewUtil.flat(Color(0.20, 0.45, 0.30)))
	var horn := MeshInstance3D.new()
	var horn_mesh := CylinderMesh.new()
	horn_mesh.top_radius = 0.16
	horn_mesh.bottom_radius = 0.07
	horn_mesh.height = 0.28
	horn.mesh = horn_mesh
	horn.material_override = dark
	horn.position = Vector3(0, 2.76, 0)
	add_child(horn)
	# Vacuum pump pod on the side, with its little motor barrel.
	ViewUtil.box(self, Vector3(0.4, 0.35, 0.45), Vector3(-0.75, 1.0, 0), dark)
	var barrel := ViewUtil.cylinder(self, 0.13, 0.4, Vector3(-0.75, 1.32, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16)))
	barrel.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.cylinder(self, 0.05, 0.5, Vector3(-0.62, 1.75, 0), steel)
	# Condensate sight glass on the cone, driven by the real inventory.
	ViewUtil.box(self, Vector3(0.09, 0.42, 0.03), Vector3(0, 0.78, 0.47),
		ViewUtil.flat(Color(0.30, 0.31, 0.33)))
	_glass = ViewUtil.box(self, Vector3(0.05, 0.1, 0.03), Vector3.ZERO,
		ViewUtil.glow(Color(0.16, 0.47, 0.84), 0.35))
	_label = ViewUtil.label(self, "", Vector3(0, 3.0, 0))
	_label.font_size = 28
	ViewUtil.label(self, lock.comp_name, Vector3(0, 3.22, 0))
	ViewUtil.interact_body(self, Vector3(1.4, 2.6, 1.4), Vector3(0, 1.3, 0))
	_pump_audio = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(-0.75, 1.2, 0), -11.0, 1.35)
	_gurgle = EquipmentAudio.make(self, "res://audio/gurgle_loop.wav",
		Vector3(0, 0.6, 0.4), -7.0, 1.0)
	_puff = VaporPlume.make(self, Vector3(0, 2.95, 0), 0.6, true)
	_last_bursts = lock.vent_bursts_done
	_last_state = lock.state


func _process(_delta: float) -> void:
	_label.text = "%s · %.0f kPa" % [lock.state.to_upper(), lock.press_pa / 1000.0]
	_pump_audio.set_running(lock.state == "evacuate")
	_gurgle.set_running(lock.state == "drain" and lock.draining_lps > 0.0)
	# One blast per real vent step of the main air valve.
	if lock.vent_bursts_done != _last_bursts:
		_last_bursts = lock.vent_bursts_done
		EquipmentAudio.play_once(self, "res://audio/vent_blast.wav",
			Vector3(0, 2.76, 0), -6.0, randf_range(0.95, 1.05))
		_puff.puff()
	# The drainer tripping open and the vacuum valve reseating are
	# mechanical events.
	if lock.state != _last_state:
		if lock.state == "drain":
			EquipmentAudio.play_once(self, "res://audio/clunk.wav",
				Vector3(0, 0.6, 0), -10.0, 0.9)
		elif lock.state == "evacuate" and _last_state != "idle":
			EquipmentAudio.play_once(self, "res://audio/clunk.wav",
				Vector3(0, 2.5, 0), -10.0, 1.2)
		_last_state = lock.state
	var frac := clampf(lock.condensate_l / SimVacuumLock.CONDENSATE_PER_CYCLE_L, 0.0, 1.0)
	var column := maxf(0.40 * frac, 0.005)
	_glass.scale = Vector3(1, column / 0.1, 1)
	_glass.position = Vector3(0, 0.58 + column / 2.0, 0.485)


func describe() -> String:
	return "%s — vacuum lock (E starts/stops the cycle)\n%s · %.1f kPa · condensate %.1f L · %d cycles" % [
		lock.comp_name, lock.state.to_upper(), lock.press_pa / 1000.0,
		lock.condensate_l, lock.cycles]


func use() -> void:
	lock.is_on = not lock.is_on
