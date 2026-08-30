class_name SuiteDoorView
extends Node3D
## A sliding cleanroom door. Its open/closed truth lives in the
## SimAirCascade door registry; this view animates the leaf and lets
## the player toggle it with E. No interlocks yet — Tier 0 doors.
## The DP gauges will tell you why interlocks exist.

const WIDTH := 1.2
const HEIGHT := 2.2

var cascade: SimAirCascade
var door_id: String
var label_text: String
var _leaf: MeshInstance3D
var _block_shape: CollisionShape3D
var _slide: float = 0.0  # 0 closed, 1 open


func setup(cascade_: SimAirCascade, door_id_: String, label_: String) -> void:
	cascade = cascade_
	door_id = door_id_
	label_text = label_
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.1, HEIGHT + 0.2, 0.16),
			Vector3(0, HEIGHT / 2.0, side * (WIDTH / 2.0 + 0.05)),
			ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	ViewUtil.box(self, Vector3(0.1, 0.1, WIDTH + 0.2),
		Vector3(0, HEIGHT + 0.15, 0), ViewUtil.flat(Color(0.16, 0.17, 0.19)))
	var leaf_mat := ViewUtil.flat(Color(0.88, 0.90, 0.92))
	leaf_mat.metallic = 0.3
	leaf_mat.roughness = 0.4
	_leaf = ViewUtil.box(self, Vector3(0.08, HEIGHT, WIDTH), Vector3(0, HEIGHT / 2.0, 0), leaf_mat)
	# Porthole window.
	var window_mat := ViewUtil.flat(Color(0.6, 0.75, 0.85, 0.5))
	window_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ViewUtil.box(_leaf, Vector3(0.09, 0.5, 0.35), Vector3(0, 0.25, 0), window_mat)
	ViewUtil.label(self, label_text, Vector3(0, HEIGHT + 0.45, 0))
	ViewUtil.interact_body(self, Vector3(0.4, HEIGHT, WIDTH), Vector3(0, HEIGHT / 2.0, 0))
	# A closed door is solid; the shape disables while it stands open.
	var blocker := StaticBody3D.new()
	_block_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, HEIGHT, WIDTH)
	_block_shape.shape = box
	blocker.add_child(_block_shape)
	blocker.position = Vector3(0, HEIGHT / 2.0, 0)
	add_child(blocker)


func _process(delta: float) -> void:
	var target := 1.0 if cascade.is_door_open(door_id) else 0.0
	_slide = move_toward(_slide, target, delta * 2.0)
	_leaf.position.z = _slide * WIDTH * 0.95
	_block_shape.set_deferred("disabled", _slide > 0.6)


func describe() -> String:
	return "%s — %s\n[E] %s" % [label_text,
		"OPEN" if cascade.is_door_open(door_id) else "closed",
		"close" if cascade.is_door_open(door_id) else "open"]


func use() -> void:
	cascade.set_door(door_id, not cascade.is_door_open(door_id))
