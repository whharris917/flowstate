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
	ViewUtil.box(self, Vector3(0.45, 0.6, 0.18), Vector3.ZERO,
		ViewUtil.flat(Color(0.72, 0.71, 0.66)))
	_lamp_on = ViewUtil.glow(Color(0.91, 0.63, 0.0))
	_lamp_off = ViewUtil.flat(Color(0.3, 0.28, 0.2))
	_lamp = ViewUtil.box(self, Vector3(0.08, 0.08, 0.05), Vector3(0, 0.14, 0.10), _lamp_off)
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
