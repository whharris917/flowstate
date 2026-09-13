class_name ControlStationView
extends Node3D
## A local control station: an enclosure on a post with a row of
## pushbuttons and a row of pilot lights, each a real record the plant
## owns through the station. Every button is its own interaction
## target (E presses it), every light reads its own lamp circuit. The
## circuits leave on gland bosses along the right flank, where the
## plant lands their wires.

const BOX := Vector3(0.44, 0.34, 0.16)
const POST_H := 1.15

const LENS := {
	"green": Color(0.10, 0.80, 0.35), "red": Color(0.90, 0.20, 0.15),
	"amber": Color(0.95, 0.70, 0.15), "white": Color(0.95, 0.95, 0.90), "blue": Color(0.25, 0.55, 0.95),
}

var station_name: String
var _devices: Array[Node3D] = []


## A pushbutton on the face: cap, guard ring, legend plate. E presses it.
class ButtonNode extends Node3D:
	var button: SimPushbutton
	var legend: String
	var _cap: MeshInstance3D
	var _rest_z: float
	var _was_pressed := false

	func build(button_: SimPushbutton, legend_: String, color: Color) -> void:
		button = button_
		legend = legend_
		var ring := ViewUtil.cylinder(self, 0.05, 0.02, Vector3(0, 0, 0.01), ViewUtil.flat(Color(0.20, 0.21, 0.23)))
		ring.rotation_degrees = Vector3(90, 0, 0)
		if button.normally_closed:
			# A mushroom head for the STOP, as convention has it.
			_cap = ViewUtil.cylinder(self, 0.045, 0.03, Vector3(0, 0, 0.035), ViewUtil.flat(color))
		else:
			_cap = ViewUtil.cylinder(self, 0.03, 0.025, Vector3(0, 0, 0.03), ViewUtil.flat(color))
		_cap.rotation_degrees = Vector3(90, 0, 0)
		_rest_z = _cap.position.z
		var plate := ViewUtil.plate(self, legend, Vector3(0, -0.07, 0.02))
		plate.font_size = 20
		plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		ViewUtil.interact_body(self, Vector3(0.11, 0.14, 0.1), Vector3(0, -0.02, 0.03))

	func _process(_delta: float) -> void:
		_cap.position.z = _rest_z - (0.012 if button.pressed else 0.0)
		if button.pressed and not _was_pressed:
			EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3.ZERO, -8.0, 1.3)
		_was_pressed = button.pressed

	func describe() -> String:
		return "%s — %s pushbutton, %s (E presses)\n%s · contact %s · %d presses" % [
			button.comp_name, legend, "normally closed" if button.normally_closed else "normally open",
			"PRESSED" if button.pressed else "released", "made" if button.contact.value > 0.5 else "open",
			button.presses]

	func use() -> void:
		button.press()


## A pilot light on the face: bezel and lens, lit from its record.
class LightNode extends Node3D:
	var light: SimPilotLight
	var legend: String
	var _lens: MeshInstance3D
	var _on: StandardMaterial3D
	var _off: StandardMaterial3D

	func build(light_: SimPilotLight, legend_: String, color: Color) -> void:
		light = light_
		legend = legend_
		var bezel := ViewUtil.cylinder(self, 0.042, 0.02, Vector3(0, 0, 0.01), ViewUtil.flat(Color(0.55, 0.57, 0.60)))
		bezel.rotation_degrees = Vector3(90, 0, 0)
		_on = ViewUtil.glow(color, 1.6)
		_off = ViewUtil.flat(color.darkened(0.6))
		_lens = ViewUtil.cylinder(self, 0.032, 0.03, Vector3(0, 0, 0.03), _off)
		_lens.rotation_degrees = Vector3(90, 0, 0)
		var plate := ViewUtil.plate(self, legend, Vector3(0, -0.065, 0.02))
		plate.font_size = 20
		plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		ViewUtil.interact_body(self, Vector3(0.1, 0.12, 0.08), Vector3(0, -0.02, 0.03))

	func _process(_delta: float) -> void:
		_lens.material_override = _on if light.lit else _off

	func describe() -> String:
		return "%s — %s pilot light, %s\n%s" % [light.comp_name, legend, light.color, "LIT" if light.lit else "dark"]

	func use() -> void:
		pass


## devices: [{"record": SimComponent, "legend": String, "color": String}]
## in face order; buttons take the upper row, lights the lower.
func setup(name_: String, devices: Array, on_post: bool) -> void:
	station_name = name_
	var grey := ViewUtil.flat(Color(0.72, 0.71, 0.66))
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	if on_post:
		ViewUtil.box(self, Vector3(0.08, POST_H, 0.08), Vector3(0, -POST_H / 2.0, -0.04), dark)
		ViewUtil.box(self, Vector3(0.3, 0.04, 0.16), Vector3(0, -POST_H - 0.02, -0.04), dark)
	ViewUtil.box(self, BOX, Vector3(0, BOX.y / 2.0, 0), grey)
	ViewUtil.box(self, Vector3(BOX.x - 0.03, BOX.y - 0.03, 0.012), Vector3(0, BOX.y / 2.0, BOX.z / 2.0 + 0.004),
		ViewUtil.flat(Color(0.78, 0.77, 0.72)))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var screw := ViewUtil.cylinder(self, 0.008, 0.01, Vector3(corner.x * (BOX.x / 2.0 - 0.025), BOX.y / 2.0 + corner.y * (BOX.y / 2.0 - 0.025), BOX.z / 2.0 + 0.014), steel)
		screw.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.2, 0.035, 0.004), Vector3(0, BOX.y - 0.03, BOX.z / 2.0 + 0.012), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	var buttons: Array = []
	var lights: Array = []
	for d: Dictionary in devices:
		if d["record"] is SimPushbutton:
			buttons.append(d)
		else:
			lights.append(d)
	_lay_row(buttons, BOX.y * 0.62, true)
	_lay_row(lights, BOX.y * 0.3, false)
	ViewUtil.label(self, station_name, Vector3(0, BOX.y + 0.14, 0))


func _lay_row(row: Array, y: float, is_button: bool) -> void:
	for i in row.size():
		var d: Dictionary = row[i]
		var x := -BOX.x / 2.0 + BOX.x * (i + 0.5) / row.size()
		var node: Node3D
		var color: Color = LENS.get(str(d.get("color", "green")), LENS["green"])
		if is_button:
			var b := ButtonNode.new()
			b.build(d["record"] as SimPushbutton, str(d.get("legend", "")), color)
			node = b
		else:
			var l := LightNode.new()
			l.build(d["record"] as SimPilotLight, str(d.get("legend", "")), color)
			node = l
		node.position = Vector3(x, y, BOX.z / 2.0 + 0.01)
		add_child(node)
		_devices.append(node)


func describe() -> String:
	return "%s — local control station\nAim at a button and press E." % station_name


func use() -> void:
	pass
