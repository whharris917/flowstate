class_name WireView
extends Node3D
## A straight conduit between two points that lights up with its signal.
## value_getter returns the live signal (0/1) or flow; the wire glows
## when it is hot. Render only — the wire's truth lives in the kernel.

var _mesh: MeshInstance3D
var _hot: StandardMaterial3D
var _cold: StandardMaterial3D
var _getter: Callable


func setup(from: Vector3, to: Vector3, getter: Callable, hot_color: Color,
		thickness: float = 0.03) -> void:
	_getter = getter
	_hot = ViewUtil.glow(hot_color, 1.2)
	_cold = ViewUtil.flat(Color(0.30, 0.30, 0.32))
	var length := from.distance_to(to)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, length)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = _cold
	add_child(_mesh)
	position = (from + to) / 2.0
	if not from.is_equal_approx(to):
		look_at_from_position(position, to, Vector3.UP if absf(from.direction_to(to).y) < 0.99 else Vector3.RIGHT)


func _process(_delta: float) -> void:
	_mesh.material_override = _hot if _getter.call() > 0.5 else _cold
