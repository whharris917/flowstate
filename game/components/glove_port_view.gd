class_name GlovePortView
extends Node3D
## One isolator glove port: ring, sleeve, and an engage/release toggle.
## Placeholder for the real glove-manipulation vignette (GDD 3.4) —
## engagement state is view-side only for now and is flagged as such.

var engaged := false
var index: int


func setup(index_: int) -> void:
	index = index_
	var ring := ViewUtil.cylinder(self, 0.16, 0.06, Vector3.ZERO,
		ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	ring.rotation_degrees = Vector3(90, 0, 0)
	var glove := ViewUtil.cylinder(self, 0.11, 0.5, Vector3(0, 0, -0.28),
		ViewUtil.flat(Color(0.10, 0.10, 0.11)))
	glove.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.interact_body(self, Vector3(0.35, 0.35, 0.3), Vector3.ZERO)


func describe() -> String:
	return "glove port %d — %s\n[E] %s" % [index,
		"hands in" if engaged else "empty",
		"withdraw" if engaged else "reach in"]


func use() -> void:
	engaged = not engaged
