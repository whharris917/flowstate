class_name PipeView
## A routed multi-segment run — process pipe or signal conduit —
## rendered as cylinders with elbow fittings, glowing when live.
## Render only: the run's truth is the kernel wire it visualizes.
## Segments carry thin colliders on layer 8 so the run can be aimed at
## (describe, X to remove). set_supports() draws the clamp brackets
## the support rule found, or paints the whole run alarm-red when it
## has an over-long unsupported span.
extends Node3D

const ALARM := Color(0.9, 0.2, 0.15)

var _getter: Callable
var _desc: String
var _hot: StandardMaterial3D
var _cold: StandardMaterial3D
var _bad: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _brackets: Array[Node3D] = []
var _was_hot := false
var _unsupported := false


func setup(path: Array[Vector3], getter: Callable, color: Color, radius: float,
		desc: String = "") -> void:
	_getter = getter
	_desc = desc
	_hot = ViewUtil.glow(color, 1.1)
	_cold = ViewUtil.flat(color.lerp(Color(0.35, 0.35, 0.37), 0.55))
	_bad = ViewUtil.glow(ALARM, 1.3)
	for i in range(path.size() - 1):
		var from := path[i]
		var to := path[i + 1]
		var length := from.distance_to(to)
		if length < 0.005:
			continue
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _cold
		add_child(inst)
		inst.position = (from + to) / 2.0
		var direction := (to - from).normalized()
		if absf(direction.y) < 0.99:
			inst.look_at(to + global_position, Vector3.UP)
			inst.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		_meshes.append(inst)
		_segment_collider(from, to, maxf(radius * 2.5, 0.12))
		if i > 0:
			var elbow := SphereMesh.new()
			elbow.radius = radius * 1.2
			elbow.height = radius * 2.4
			var joint := MeshInstance3D.new()
			joint.mesh = elbow
			joint.material_override = _cold
			joint.position = from
			add_child(joint)
			_meshes.append(joint)


## Thin box collider along one segment, layer 8: the interact ray sees
## it (describe / X removes the run) but nothing collides with it and
## the support rule never counts pipe as supporting pipe.
func _segment_collider(from: Vector3, to: Vector3, thickness: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var delta := to - from
	box.size = Vector3(maxf(absf(delta.x), thickness), maxf(absf(delta.y), thickness),
		maxf(absf(delta.z), thickness))
	shape.shape = box
	body.add_child(shape)
	body.position = (from + to) / 2.0
	body.set_meta("view", self)
	add_child(body)


## Redraw the clamp hardware from a fresh support evaluation. Points
## are local to this node's parent (the plant).
func set_supports(brackets: Array, unsupported: bool) -> void:
	for old in _brackets:
		old.queue_free()
	_brackets.clear()
	_unsupported = unsupported
	_was_hot = not _was_hot  # force a material refresh next frame
	var mat := ViewUtil.flat(Color(0.22, 0.23, 0.26))
	for bracket: Dictionary in brackets:
		var from: Vector3 = bracket["from"]
		var to: Vector3 = bracket["to"]
		var length := from.distance_to(to)
		if length < 0.02:
			continue
		var strut := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.03
		mesh.bottom_radius = 0.03
		mesh.height = length
		strut.mesh = mesh
		strut.material_override = mat
		add_child(strut)
		strut.position = (from + to) / 2.0
		var direction := (to - from).normalized()
		if absf(direction.y) < 0.99:
			strut.look_at(to + global_position, Vector3.UP)
			strut.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		_brackets.append(strut)
		var foot := MeshInstance3D.new()
		var pad := BoxMesh.new()
		pad.size = Vector3(0.12, 0.03, 0.12)
		foot.mesh = pad
		foot.material_override = mat
		add_child(foot)
		foot.position = to
		if absf(direction.y) < 0.5:  # side-anchored: stand the pad up
			foot.rotation = Vector3(0, 0, PI / 2.0) if absf(direction.x) > 0.5 \
				else Vector3(PI / 2.0, 0, 0)
		_brackets.append(foot)


func describe() -> String:
	var state := "UNSUPPORTED SPAN — add structure" if _unsupported else "supported"
	return "%s\n%s (X removes the run)" % [_desc, state]


func _process(_delta: float) -> void:
	var hot: bool = _getter.call() > 0.5
	if hot == _was_hot and not _meshes.is_empty() and _meshes[0].material_override != null:
		return
	_was_hot = hot
	var mat := _bad if _unsupported else (_hot if hot else _cold)
	for inst in _meshes:
		inst.material_override = mat
