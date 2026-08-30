class_name PipeView
## A routed multi-segment run — process pipe or signal conduit —
## rendered as cylinders with elbow fittings, glowing when live.
## Render only: the run's truth is the kernel wire it visualizes.
extends Node3D

var _getter: Callable
var _hot: StandardMaterial3D
var _cold: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _was_hot := false


func setup(path: Array[Vector3], getter: Callable, color: Color, radius: float) -> void:
	_getter = getter
	_hot = ViewUtil.glow(color, 1.1)
	_cold = ViewUtil.flat(color.lerp(Color(0.35, 0.35, 0.37), 0.55))
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


func _process(_delta: float) -> void:
	var hot: bool = _getter.call() > 0.5
	if hot == _was_hot and not _meshes.is_empty() and _meshes[0].material_override != null:
		return
	_was_hot = hot
	for inst in _meshes:
		inst.material_override = _hot if hot else _cold
