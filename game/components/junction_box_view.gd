class_name JunctionBoxView
extends Node3D
## A field junction box: a small enclosure on a post where an area's
## instrument and valve circuits land on terminals and leave together
## in one multicore cable, the way a real plant gathers its field
## wiring instead of running every conduit home. The box owns terminal
## records (one scan late, like any terminal); this node only stands
## it up. Field wires land on the left flank markers, the multicore on
## the right.

const BOX := Vector3(0.42, 0.52, 0.18)
const POST_H := 1.1

var jb_name: String
var channels: int = 12
var _door: MeshInstance3D


func setup(name_: String, channels_: int, on_post: bool) -> void:
	jb_name = name_
	channels = channels_
	var grey := ViewUtil.flat(Color(0.62, 0.63, 0.66))
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	if on_post:
		ViewUtil.box(self, Vector3(0.08, POST_H, 0.08), Vector3(0, -POST_H / 2.0, -0.05), dark)
		ViewUtil.box(self, Vector3(0.36, 0.04, 0.16), Vector3(0, -POST_H - 0.02, -0.05), dark)
	# Body, door with screws, hinges, a nameplate, and a gland plate
	# along the bottom with one gland per channel that has a wire.
	ViewUtil.box(self, BOX, Vector3(0, BOX.y / 2.0, 0), grey)
	_door = ViewUtil.box(self, Vector3(BOX.x - 0.04, BOX.y - 0.04, 0.02),
		Vector3(0, BOX.y / 2.0, BOX.z / 2.0 + 0.005), ViewUtil.flat(Color(0.68, 0.69, 0.72)))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var screw := ViewUtil.cylinder(self, 0.012, 0.01,
			Vector3(corner.x * (BOX.x / 2.0 - 0.04), BOX.y / 2.0 + corner.y * (BOX.y / 2.0 - 0.04), BOX.z / 2.0 + 0.02), steel)
		screw.rotation_degrees = Vector3(90, 0, 0)
	for hy: float in [0.12, BOX.y - 0.12]:
		ViewUtil.box(self, Vector3(0.03, 0.06, 0.03), Vector3(-BOX.x / 2.0 - 0.005, hy, BOX.z / 2.0 - 0.01), steel)
	ViewUtil.box(self, Vector3(0.22, 0.06, 0.005), Vector3(0, BOX.y - 0.09, BOX.z / 2.0 + 0.018),
		ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	var plate := ViewUtil.box(self, Vector3(BOX.x - 0.06, 0.02, BOX.z - 0.04), Vector3(0, -0.01, 0), steel)
	plate.name = "gland_plate"
	var count := mini(channels, 12)
	for i in count:
		var x := -BOX.x / 2.0 + 0.05 + (BOX.x - 0.10) * (i + 0.5) / count
		var gland := ViewUtil.cylinder(self, 0.011, 0.05, Vector3(x, -0.035, 0.02), dark)
		gland.name = "gland_%d" % i
	ViewUtil.label(self, jb_name, Vector3(0, BOX.y + 0.16, 0))
	ViewUtil.interact_body(self, Vector3(BOX.x + 0.1, BOX.y + 0.1, BOX.z + 0.1), Vector3(0, BOX.y / 2.0, 0))


func describe() -> String:
	return "%s — junction box, %d terminals\nField circuits land on the left, the multicore leaves on the right; each terminal is one scan late." % [
		jb_name, channels]


func use() -> void:
	pass
