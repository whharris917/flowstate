class_name CabinetView
extends Node3D
## The control cabinet enclosure: RAL-7035 shell with a swinging door,
## and inside — DIN rails carrying a power supply, the PLC CPU with
## its I/O cards, wire duct, and terminal strips. Field wiring lands
## on the flank markers (left in, right out); E swings the door open
## and brings up the schematic panel for the internal hookup.

const W := 1.3
const H := 2.0
const D := 0.6

var plc: SimPLC
var cabinet_name: String
var config_cb: Callable = Callable()

var _door: Node3D
var _door_open := false


func setup(plc_: SimPLC, name_: String) -> void:
	plc = plc_
	cabinet_name = name_
	var shell_mat := ViewUtil.flat(Color(0.80, 0.80, 0.77))
	var dark := ViewUtil.flat(Color(0.16, 0.17, 0.19))

	# Shell: back, sides, top, plinth. Collision is the full box less
	# the front face (the door visual covers the opening).
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W, H, D)
	shape.shape = box
	shape.position = Vector3(0, H / 2.0, 0)
	body.add_child(shape)
	add_child(body)
	ViewUtil.box(self, Vector3(W, H, 0.04), Vector3(0, H / 2.0, -D / 2.0 + 0.02), shell_mat)
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.04, H, D), Vector3(side * (W / 2.0 - 0.02), H / 2.0, 0), shell_mat)
	ViewUtil.box(self, Vector3(W, 0.04, D), Vector3(0, H - 0.02, 0), shell_mat)
	ViewUtil.box(self, Vector3(W, 0.1, D), Vector3(0, 0.05, 0), dark)

	_build_interior()

	# Door hinged on the left edge, swinging outward.
	_door = Node3D.new()
	_door.position = Vector3(-W / 2.0, H / 2.0 + 0.05, D / 2.0 - 0.02)
	add_child(_door)
	ViewUtil.box(_door, Vector3(W - 0.04, H - 0.14, 0.04), Vector3(W / 2.0 - 0.02, 0, 0),
		shell_mat)
	ViewUtil.box(_door, Vector3(0.05, 0.30, 0.06), Vector3(W - 0.14, 0, 0.03), dark)

	ViewUtil.label(self, cabinet_name, Vector3(0, H + 0.22, 0))
	var in_tag := ViewUtil.label(self, "FIELD IN", Vector3(-0.72, H + 0.02, 0.12))
	in_tag.font_size = 26
	var out_tag := ViewUtil.label(self, "FIELD OUT", Vector3(0.72, H + 0.02, 0.12))
	out_tag.font_size = 26
	ViewUtil.interact_body(self, Vector3(W + 0.15, H, D + 0.2), Vector3(0, H / 2.0, 0))


func _build_interior() -> void:
	var rail_mat := ViewUtil.flat(Color(0.62, 0.64, 0.66))
	var duct_mat := ViewUtil.flat(Color(0.75, 0.77, 0.70))
	var z := -D / 2.0 + 0.10
	for rail_y: float in [1.52, 1.05]:
		ViewUtil.box(self, Vector3(W - 0.24, 0.035, 0.02), Vector3(0, rail_y, z), rail_mat)
	# Power supply on the top rail.
	ViewUtil.box(self, Vector3(0.16, 0.24, 0.12), Vector3(-0.42, 1.55, z + 0.07),
		ViewUtil.flat(Color(0.35, 0.55, 0.40)))
	# PLC CPU and I/O cards.
	ViewUtil.box(self, Vector3(0.18, 0.26, 0.13), Vector3(-0.18, 1.55, z + 0.075),
		ViewUtil.flat(Color(0.15, 0.16, 0.20)))
	for i in range(4):
		var card := ViewUtil.box(self, Vector3(0.10, 0.24, 0.12),
			Vector3(-0.02 + 0.12 * (i + 1), 1.55, z + 0.07),
			ViewUtil.flat(Color(0.22, 0.24, 0.28) if i % 2 == 0 else Color(0.26, 0.28, 0.33)))
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Relay row on the second rail (future internal relays live here).
	for i in range(6):
		ViewUtil.box(self, Vector3(0.075, 0.14, 0.10),
			Vector3(-0.40 + 0.16 * i, 1.08, z + 0.06),
			ViewUtil.flat(Color(0.85, 0.55, 0.15) if i % 3 == 0 else Color(0.55, 0.57, 0.60)))
	# Wire duct: vertical channels each side, one horizontal mid.
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.09, 1.35, 0.07), Vector3(side * 0.56, 1.0, z + 0.045), duct_mat)
	ViewUtil.box(self, Vector3(W - 0.24, 0.09, 0.07), Vector3(0, 1.30, z + 0.045), duct_mat)
	# Terminal strips low in the cabinet: grey/blue alternating blocks.
	for row in range(2):
		for i in range(14):
			ViewUtil.box(self, Vector3(0.055, 0.09, 0.06),
				Vector3(-0.42 + 0.065 * i, 0.62 - 0.16 * row, z + 0.04),
				ViewUtil.flat(Color(0.25, 0.35, 0.65) if i % 4 == 3 else Color(0.72, 0.73, 0.75)))


func _physics_process(_delta: float) -> void:
	var target := -2.1 if _door_open else 0.0
	_door.rotation.y = lerpf(_door.rotation.y, target, 0.12)


func describe() -> String:
	return "%s — control cabinet (E opens)\nPLC: %d rung(s) · %d terminals wired inside" % [
		cabinet_name, plc.program.size(), _internal_count()]


func _internal_count() -> int:
	# The panel shows details; this is just a hint for the look text.
	return plc.program.size()


func use() -> void:
	if not _door_open:
		_door_open = true
		if config_cb.is_valid():
			config_cb.call(self)
	else:
		_door_open = false
