class_name PipeView
## A routed multi-segment run — process pipe, signal conduit, or cable
## tray — rendered as oriented segments with fittings, glowing when a
## live wire backs it. Render only: a wire run's truth is the kernel
## wire it visualizes; an infrastructure run is support you laid down.
## Segments carry thin colliders (layer 8 for wire runs so pipe never
## supports pipe; layer 1 for infrastructure so trays and racks DO
## support what's routed along them). set_supports() draws the clamp
## brackets the support rule found, or paints the run alarm-red when
## an unsupported span is over the limit.
extends Node3D

const ALARM := Color(0.9, 0.2, 0.15)

var _getter: Callable
var _desc: String
var _hot: StandardMaterial3D
var _cold: StandardMaterial3D
var _bad: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _brackets: Array[Node3D] = []
var _collider_rids: Array[RID] = []
var _was_hot := false
var _unsupported := false


func setup(path: Array[Vector3], getter: Callable, color: Color, radius: float,
		desc: String = "", style: String = "pipe", collider_layer: int = 8) -> void:
	_getter = getter
	_desc = desc
	_hot = ViewUtil.glow(color, 1.1)
	_cold = ViewUtil.flat(color.lerp(Color(0.35, 0.35, 0.37), 0.55)) if style == "pipe" \
		else ViewUtil.flat(color)
	_bad = ViewUtil.glow(ALARM, 1.3)
	for i in range(path.size() - 1):
		var from := path[i]
		var to := path[i + 1]
		if from.distance_to(to) < 0.005:
			continue
		var seg := segment_node(from, to, radius, style, _cold)
		add_child(seg)
		_collect_meshes(seg)
		if collider_layer > 0:
			_segment_collider(from, to, maxf(radius * 2.5, 0.12), collider_layer)
		if i > 0:
			var joint := joint_node(from, radius, style, _cold)
			if joint != null:
				add_child(joint)
				_collect_meshes(joint)


## One oriented segment: a cylinder for pipe/conduit, a channel with
## side rails for cable tray. Static so route previews can share it.
static func segment_node(from: Vector3, to: Vector3, radius: float,
		style: String, mat: StandardMaterial3D) -> Node3D:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var root := Node3D.new()
	root.position = (from + to) / 2.0
	root.basis = _segment_basis(direction)
	if style == "tray":
		var width := radius * 2.0
		var base := MeshInstance3D.new()
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(width, 0.05, length)
		base.mesh = base_mesh
		base.material_override = mat
		root.add_child(base)
		for side: float in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(0.04, 0.11, length)
			rail.mesh = rail_mesh
			rail.material_override = mat
			rail.position = Vector3(side * (width / 2.0 - 0.02), 0.05, 0)
			root.add_child(rail)
	else:
		var inst := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		inst.mesh = mesh
		inst.material_override = mat
		# Cylinder axis is Y; map it onto the segment direction (-Z of
		# the looking_at basis).
		inst.basis = Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
		root.add_child(inst)
	return root


static func joint_node(at: Vector3, radius: float, style: String,
		mat: StandardMaterial3D) -> Node3D:
	if style == "tray":
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(radius * 2.0, 0.11, radius * 2.0)
		box.mesh = mesh
		box.material_override = mat
		box.position = at
		return box
	var joint := MeshInstance3D.new()
	var elbow := SphereMesh.new()
	elbow.radius = radius * 1.2
	elbow.height = radius * 2.4
	joint.mesh = elbow
	joint.material_override = mat
	joint.position = at
	return joint


static func _segment_basis(direction: Vector3) -> Basis:
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(direction, up)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)


## Thin box collider along one segment: the interact ray sees it
## (describe / X removes the run); on layer 1 it is also real support.
func _segment_collider(from: Vector3, to: Vector3, thickness: float, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
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
	_collider_rids.append(body.get_rid())


## This run's own collider RIDs — excluded when it validates itself.
func collider_rids() -> Array[RID]:
	return _collider_rids


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
		strut.basis = _segment_basis(direction) * Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
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
