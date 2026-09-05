class_name RelayView
extends Node3D
## Renders a SimRelay: an enclosure on the wall with a coil lamp.

var relay: SimRelay
var _lamp: MeshInstance3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _was_energized: bool = false


func setup(relay_: SimRelay) -> void:
	relay = relay_
	# A field relay enclosure: body, a door with hinges, latch and
	# screws, a window with the coil lamp behind it, a nameplate, and a
	# gland boss where each of the two circuits lands.
	var grey := ViewUtil.flat(Color(0.72, 0.71, 0.66))
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	ViewUtil.box(self, Vector3(0.45, 0.6, 0.18), Vector3.ZERO, grey)
	ViewUtil.box(self, Vector3(0.41, 0.56, 0.015), Vector3(0, 0, 0.095), ViewUtil.flat(Color(0.78, 0.77, 0.72)))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var screw := ViewUtil.cylinder(self, 0.01, 0.01, Vector3(corner.x * 0.18, corner.y * 0.25, 0.105), steel)
		screw.rotation_degrees = Vector3(90, 0, 0)
	for hy: float in [-0.18, 0.18]:
		ViewUtil.box(self, Vector3(0.025, 0.06, 0.03), Vector3(-0.225, hy, 0.08), steel)
	ViewUtil.box(self, Vector3(0.03, 0.08, 0.02), Vector3(0.19, 0.0, 0.11), steel)
	ViewUtil.box(self, Vector3(0.24, 0.2, 0.012), Vector3(0, 0.14, 0.10), dark)
	ViewUtil.box(self, Vector3(0.2, 0.16, 0.004), Vector3(0, 0.14, 0.108),
		ViewUtil.flat(Color(0.35, 0.40, 0.45, 0.6)))
	ViewUtil.box(self, Vector3(0.16, 0.045, 0.004), Vector3(0, -0.06, 0.105), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	for gx: float in [-0.13, 0.13]:
		var boss := ViewUtil.cylinder(self, 0.022, 0.04, Vector3(gx, -0.2, 0.10), dark)
		boss.rotation_degrees = Vector3(90, 0, 0)
	_lamp_on = ViewUtil.glow(Color(0.91, 0.63, 0.0))
	_lamp_off = ViewUtil.flat(Color(0.3, 0.28, 0.2))
	_lamp = ViewUtil.box(self, Vector3(0.06, 0.06, 0.03), Vector3(0, 0.14, 0.108), _lamp_off)
	ViewUtil.label(self, relay.comp_name, Vector3(0, 0.55, 0))
	ViewUtil.interact_body(self, Vector3(0.5, 0.65, 0.25), Vector3.ZERO)
	# Freestanding rack (node sits at ~y 1.58 world; local -1.58 is floor).
	ViewUtil.box(self, Vector3(0.9, 0.9, 0.06), Vector3(0, 0, -0.13),
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	for post_x: float in [-0.35, 0.35]:
		ViewUtil.box(self, Vector3(0.1, 2.15, 0.1), Vector3(post_x, -0.5, -0.13),
			ViewUtil.flat(Color(0.16, 0.17, 0.19)))


func _process(_delta: float) -> void:
	_lamp.material_override = _lamp_on if relay.energized else _lamp_off
	if relay.energized != _was_energized:
		_was_energized = relay.energized
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav",
			Vector3(0, 0.1, 0.1), -6.0, 1.0 if relay.energized else 0.9)


func describe() -> String:
	return "%s — coil %s\n%d cycles" % [
		relay.comp_name, "ENERGIZED" if relay.energized else "dropped", relay.cycles]


func use() -> void:
	pass
