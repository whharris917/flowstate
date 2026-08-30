class_name CabinetView
extends Node3D
## The control cabinet enclosure. It starts EMPTY: shell, swinging
## door, three bare DIN rails and wire duct. Everything else — PSU,
## PLC, cards, relays, terminal strips, internal wiring — is built in
## the cabinet editor, and set_layout() renders whatever the editor
## placed. The 3D interior is display-only; E swings the door, and a
## floating EDIT button inside opens the editor.

const W := 1.3
const H := 2.0
const D := 0.6

var cabinet_name: String
var config_cb: Callable = Callable()

var _door: Node3D
var _door_open := false
var _edit_button: CabinetEditButton
var _contents: Node3D


func setup(name_: String) -> void:
	cabinet_name = name_
	var shell_mat := ViewUtil.flat(Color(0.80, 0.80, 0.77))
	var dark := ViewUtil.flat(Color(0.16, 0.17, 0.19))

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

	# The bare bones every cabinet ships with: back panel, DIN rails,
	# vertical wire duct either side.
	var rail_mat := ViewUtil.flat(Color(0.62, 0.64, 0.66))
	var duct_mat := ViewUtil.flat(Color(0.75, 0.77, 0.70))
	var z := -D / 2.0 + 0.10
	for rail_y: float in CabinetSpec.RAIL_Y:
		ViewUtil.box(self, Vector3(W - 0.24, 0.035, 0.02), Vector3(0, rail_y, z), rail_mat)
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.09, 1.45, 0.07), Vector3(side * 0.56, 1.05, z + 0.02), duct_mat)

	_contents = Node3D.new()
	add_child(_contents)

	_door = Node3D.new()
	_door.position = Vector3(-W / 2.0, H / 2.0 + 0.05, D / 2.0 - 0.02)
	add_child(_door)
	ViewUtil.box(_door, Vector3(W - 0.04, H - 0.14, 0.04), Vector3(W / 2.0 - 0.02, 0, 0), shell_mat)
	ViewUtil.box(_door, Vector3(0.05, 0.30, 0.06), Vector3(W - 0.14, 0, 0.03), dark)

	_edit_button = CabinetEditButton.new()
	_edit_button.position = Vector3(0, 1.35, D / 2.0 + 0.10)
	_edit_button.open_cb = func() -> void:
		if config_cb.is_valid():
			config_cb.call(self)
	add_child(_edit_button)
	_edit_button.build()
	_edit_button.visible = false

	ViewUtil.label(self, cabinet_name, Vector3(0, H + 0.22, 0))
	var in_tag := ViewUtil.label(self, "FIELD IN", Vector3(-0.72, H + 0.02, 0.12))
	in_tag.font_size = 26
	var out_tag := ViewUtil.label(self, "FIELD OUT", Vector3(0.72, H + 0.02, 0.12))
	out_tag.font_size = 26
	ViewUtil.interact_body(self, Vector3(W + 0.15, H, D + 0.2), Vector3(0, H / 2.0, 0))


## Rebuild the interior from the editor's layout: modules on their
## rails, internal wires dropped into the duct and run across.
## wire_specs: [{"a": Vector3, "b": Vector3, "color": Color}] local.
func set_layout(modules: Array, wire_specs: Array) -> void:
	for old in _contents.get_children():
		old.queue_free()
	for module_v: Variant in modules:
		var module := module_v as Dictionary
		var type_id := str(module["type"])
		var spec: Dictionary = CabinetSpec.MODULES[type_id]
		var units := CabinetSpec.units_of(type_id)
		var center := CabinetSpec.module_center(int(module["rail"]), int(module["slot"]), units)
		var size := Vector3(units * CabinetSpec.UNIT_W - 0.012,
			CabinetSpec.MODULE_H if not type_id.begins_with("tb") else 0.12,
			CabinetSpec.MODULE_D)
		ViewUtil.box(_contents, size, center, ViewUtil.flat(spec["color"]))
		if type_id.begins_with("card_"):
			for i in range(4):  # LED row
				var led := ViewUtil.box(_contents, Vector3(0.012, 0.012, 0.01),
					center + Vector3(-size.x / 2.0 + 0.02 + i * 0.02, size.y / 2.0 - 0.03, size.z / 2.0),
					ViewUtil.glow(Color(0.3, 0.9, 0.4), 0.8))
				led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif type_id.begins_with("tb"):
			var blocks := 8 if type_id == "tb8d" else 4
			for i in range(blocks):
				ViewUtil.box(_contents, Vector3(0.02, 0.13, 0.05),
					center + Vector3(-size.x / 2.0 + (i + 0.5) * size.x / blocks, 0.01, 0.04),
					ViewUtil.flat(Color(0.25, 0.35, 0.65) if type_id == "tb4a" else Color(0.78, 0.79, 0.80)))
		elif type_id == "plc":
			ViewUtil.box(_contents, Vector3(size.x - 0.03, 0.05, 0.01),
				center + Vector3(0, 0.05, size.z / 2.0), ViewUtil.glow(Color(0.2, 0.7, 0.4), 0.6))
		var tag := ViewUtil.label(_contents, str(spec["label"]),
			center + Vector3(0, size.y / 2.0 + 0.05, 0))
		tag.font_size = 18
		tag.pixel_size = 0.0022
	for wire_v: Variant in wire_specs:
		var wire := wire_v as Dictionary
		_draw_wire(wire["a"] as Vector3, wire["b"] as Vector3, wire["color"] as Color)


## One internal wire: drop from A into the duct below its rail, run
## across, rise to B. Thin boxes — panel wiring, not process pipe.
func _draw_wire(a: Vector3, b: Vector3, color: Color) -> void:
	var mat := ViewUtil.flat(color)
	var duct_y := minf(a.y, b.y) - CabinetSpec.DUCT_DROP
	var points: Array[Vector3] = [a, Vector3(a.x, duct_y, a.z),
		Vector3(b.x, duct_y, b.z), b]
	for i in range(points.size() - 1):
		var from := points[i]
		var to := points[i + 1]
		var mid := (from + to) / 2.0
		var delta := to - from
		ViewUtil.box(_contents, Vector3(maxf(absf(delta.x), 0.016),
			maxf(absf(delta.y), 0.016), maxf(absf(delta.z), 0.016)), mid, mat)


func _physics_process(_delta: float) -> void:
	var target := -2.1 if _door_open else 0.0
	_door.rotation.y = lerpf(_door.rotation.y, target, 0.12)
	_edit_button.visible = _door.rotation.y < -1.2


func describe() -> String:
	return "%s — control cabinet (E opens/closes the door)" % cabinet_name


func use() -> void:
	_door_open = not _door_open
