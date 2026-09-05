class_name VialFillerView
extends Node3D
## Renders a SimVialFiller: a stainless base cabinet under a glazed
## isolator with glove ports; inside, an indexing conveyor of vials, a
## fill needle that dips while the dose is drawn, and a capper ram
## that presses each closure home. The conveyor really indexes with
## the machine state; the counter is the sim's lifetime total.
## E starts/stops the machine.

const SLOT_PITCH := 0.32
const SLOTS := 6
const BED_Y := 1.02

var filler: SimVialFiller
var _label: Label3D
var _count_label: Label3D
var _vials: Node3D
var _needle: Node3D
var _ram: Node3D
var _last_state: String = "idle"
var _last_count: int = 0
var _anim_t: float = 0.0


func setup(filler_: SimVialFiller) -> void:
	filler = filler_
	var steel := ViewUtil.flat(Color(0.72, 0.74, 0.77))
	steel.metallic = 0.55
	steel.roughness = 0.3
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	var glass := ViewUtil.flat(Color(0.75, 0.85, 0.92, 0.22))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Base cabinet with kick space.
	ViewUtil.box(self, Vector3(2.2, 0.1, 0.9), Vector3(0, 0.05, 0), dark)
	ViewUtil.box(self, Vector3(2.3, 0.75, 1.0), Vector3(0, 0.52, 0), steel)
	# Isolator frame and glazing, y 0.9 -> 1.95.
	for corner: Vector2 in [Vector2(-1.15, -0.5), Vector2(1.15, -0.5),
			Vector2(-1.15, 0.5), Vector2(1.15, 0.5)]:
		ViewUtil.box(self, Vector3(0.06, 1.05, 0.06),
			Vector3(corner.x, 1.42, corner.y), dark)
	ViewUtil.box(self, Vector3(2.36, 0.06, 1.06), Vector3(0, 1.97, 0), dark)
	ViewUtil.box(self, Vector3(2.3, 1.0, 0.03), Vector3(0, 1.44, 0.5), glass)
	ViewUtil.box(self, Vector3(2.3, 1.0, 0.03), Vector3(0, 1.44, -0.5), glass)
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.03, 1.0, 0.95), Vector3(side * 1.14, 1.44, 0), glass)
	# Glove ports on the front glazing.
	for port_x: float in [-0.45, 0.45]:
		var ring := ViewUtil.cylinder(self, 0.14, 0.05, Vector3(port_x, 1.32, 0.51), dark)
		ring.rotation_degrees = Vector3(90, 0, 0)
		var glove := ViewUtil.cylinder(self, 0.10, 0.08, Vector3(port_x, 1.32, 0.55),
			ViewUtil.flat(Color(0.55, 0.55, 0.58)))
		glove.rotation_degrees = Vector3(90, 0, 0)

	# Isolator furniture: the HEPA housing on top with two fan cowls and
	# an exhaust duct, a Magnehelic gauge, the control panel with its
	# screen and keys on the base, a light tower at the corner, and a
	# nameplate.
	ViewUtil.box(self, Vector3(2.0, 0.3, 0.8), Vector3(0, 2.15, 0), ViewUtil.flat(Color(0.86, 0.87, 0.85)))
	for i in 12:
		ViewUtil.box(self, Vector3(0.015, 0.3, 0.7), Vector3(-0.9 + i * 0.16, 2.15, 0), ViewUtil.flat(Color(0.62, 0.64, 0.66)))
	for cx: float in [-0.6, 0.6]:
		ViewUtil.cylinder(self, 0.18, 0.12, Vector3(cx, 2.36, 0), ViewUtil.flat(Color(0.62, 0.64, 0.66)))
		ViewUtil.cylinder(self, 0.12, 0.02, Vector3(cx, 2.43, 0), dark)
	ViewUtil.cylinder(self, 0.09, 0.5, Vector3(0.6, 2.65, 0), ViewUtil.flat(Color(0.62, 0.64, 0.66)))
	var duct := ViewUtil.cylinder(self, 0.09, 0.9, Vector3(0.6, 2.9, -0.45), ViewUtil.flat(Color(0.62, 0.64, 0.66)))
	duct.rotation_degrees = Vector3(90, 0, 0)
	var mg := ViewUtil.cylinder(self, 0.07, 0.04, Vector3(-1.0, 1.85, 0.53), dark)
	mg.rotation_degrees = Vector3(90, 0, 0)
	var mf := ViewUtil.cylinder(self, 0.058, 0.006, Vector3(-1.0, 1.85, 0.553), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	mf.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.44, 0.34, 0.05), Vector3(0.6, 0.62, 0.52), ViewUtil.flat(Color(0.62, 0.63, 0.66)))
	ViewUtil.box(self, Vector3(0.32, 0.18, 0.01), Vector3(0.6, 0.67, 0.55), ViewUtil.glow(Color(0.35, 0.75, 0.95), 0.6))
	for i in 5:
		ViewUtil.box(self, Vector3(0.04, 0.03, 0.01), Vector3(0.45 + i * 0.07, 0.5, 0.55), dark)
	ViewUtil.cylinder(self, 0.02, 0.35, Vector3(1.05, 2.15, 0.4), dark)
	for i in 3:
		ViewUtil.cylinder(self, 0.045, 0.07, Vector3(1.05, 2.36 + i * 0.075, 0.4),
			[ViewUtil.flat(Color(0.20, 0.70, 0.35)), ViewUtil.flat(Color(0.95, 0.70, 0.15)), ViewUtil.flat(Color(0.85, 0.20, 0.15))][i])
	ViewUtil.box(self, Vector3(0.28, 0.10, 0.005), Vector3(-0.6, 0.62, 0.503), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	# Conveyor bed and the vial train.
	ViewUtil.box(self, Vector3(2.0, 0.06, 0.22), Vector3(0, BED_Y - 0.05, 0), dark)
	_vials = Node3D.new()
	add_child(_vials)
	var vial_mat := ViewUtil.flat(Color(0.85, 0.90, 0.95, 0.7))
	vial_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for slot in range(SLOTS):
		var vial := ViewUtil.cylinder(_vials, 0.035, 0.11,
			Vector3(_slot_x(slot), BED_Y + 0.055, 0), vial_mat)
		vial.set_meta("slot", slot)
		# Capped vials (past the capper) get a little grey closure.
		if slot >= 4:
			ViewUtil.cylinder(_vials, 0.028, 0.02,
				Vector3(_slot_x(slot), BED_Y + 0.12, 0), dark)

	# Fill head over station 2: bridge, reservoir, dipping needle.
	ViewUtil.box(self, Vector3(0.1, 0.7, 0.1), Vector3(_slot_x(2), 1.55, -0.3), steel)
	ViewUtil.box(self, Vector3(0.3, 0.1, 0.44), Vector3(_slot_x(2), 1.85, -0.08), steel)
	_needle = Node3D.new()
	_needle.position = Vector3(_slot_x(2), 1.5, 0)
	add_child(_needle)
	ViewUtil.cylinder(_needle, 0.015, 0.5, Vector3.ZERO,
		ViewUtil.flat(Color(0.45, 0.47, 0.50)))
	# Capper over station 4: frame and press ram.
	ViewUtil.box(self, Vector3(0.1, 0.7, 0.1), Vector3(_slot_x(4), 1.55, -0.3), steel)
	_ram = Node3D.new()
	_ram.position = Vector3(_slot_x(4), 1.62, 0)
	add_child(_ram)
	ViewUtil.box(_ram, Vector3(0.12, 0.3, 0.12), Vector3.ZERO, dark)
	ViewUtil.cylinder(_ram, 0.045, 0.14, Vector3(0, -0.2, 0),
		ViewUtil.flat(Color(0.55, 0.30, 0.16)))

	_label = ViewUtil.label(self, "", Vector3(0, 2.25, 0))
	_label.font_size = 28
	_count_label = ViewUtil.label(self, "", Vector3(1.0, 1.7, 0.52))
	_count_label.font_size = 30
	_count_label.modulate = Color(0.4, 0.95, 0.55)
	ViewUtil.label(self, filler.comp_name, Vector3(0, 2.46, 0))
	ViewUtil.interact_body(self, Vector3(2.4, 2.0, 1.1), Vector3(0, 1.0, 0))
	_last_state = filler.state
	_last_count = filler.vials_done


func _slot_x(slot: int) -> float:
	return -0.85 + SLOT_PITCH * slot


func _process(delta: float) -> void:
	_label.text = "%s" % ("STOPPED" if not filler.is_on
		else ("STARVED" if filler.state == "idle" else filler.state.to_upper()))
	_count_label.text = "%d" % filler.vials_done
	# Machine events, straight off the state edges.
	if filler.state != _last_state:
		_last_state = filler.state
		_anim_t = 0.0
		match filler.state:
			"index":
				EquipmentAudio.play_once(self, "res://audio/servo.wav",
					Vector3(0, BED_Y, 0), -10.0, randf_range(0.97, 1.03))
			"fill":
				EquipmentAudio.play_once(self, "res://audio/valve_air.wav",
					Vector3(_slot_x(2), 1.3, 0), -18.0, 1.5)
			"cap":
				EquipmentAudio.play_once(self, "res://audio/clunk.wav",
					Vector3(_slot_x(4), 1.4, 0), -14.0, 1.35)
	if filler.vials_done != _last_count:
		_last_count = filler.vials_done
		if _last_count % 50 == 0:
			EquipmentAudio.play_once(self, "res://audio/beep.wav",
				Vector3(1.0, 1.7, 0.5), -12.0, 1.2)
	# Animation follows the live state: the conveyor slides one pitch
	# during index (then logically shifts back), the needle dips for
	# the dose, the ram presses the cap.
	_anim_t += delta
	_vials.position.x = 0.0
	_needle.position.y = 1.5
	_ram.position.y = 1.62
	match filler.state:
		"index":
			_vials.position.x = SLOT_PITCH * clampf(_anim_t / SimVialFiller.INDEX_S, 0.0, 1.0)
		"fill":
			_needle.position.y = 1.5 - 0.28 * sin(PI * clampf(
				_anim_t / SimVialFiller.FILL_S, 0.0, 1.0))
		"cap":
			_ram.position.y = 1.62 - 0.30 * sin(PI * clampf(
				_anim_t / SimVialFiller.CAP_S, 0.0, 1.0))


func describe() -> String:
	return "%s — vial filler/capper, %.0f mL dose (E starts/stops)\n%s · %d vials filled" % [
		filler.comp_name, SimVialFiller.VIAL_ML,
		"RUNNING" if filler.state != "idle" else ("STARVED or unpowered" if filler.is_on else "stopped"),
		filler.vials_done]


func use() -> void:
	filler.is_on = not filler.is_on
