class_name PlantSolids
extends Node
## What the player bumps into: every piece of equipment, fitting, line
## and cable in the plant is solid, in the shape it is drawn. Each drawn
## thing gets one static body on SOLID_LAYER, a layer nothing but the
## player (and the camera's pull-in) looks at, so routing, picking and
## support never see it.
##
## Equipment is solid piece by piece: each primitive it was drawn with
## (MeshMerge keeps them as "sources") is a convex hull of its own, so an
## open frame stays open; a mesh drawn whole is one hull. A line is
## round segments along the path it is drawn on, at its drawn radius. A
## tray already stands on the support layer and gets nothing more.
##
## One rule keeps the shapes true: a thing's body is rebuilt whenever a
## mesh is added under it or taken away (a resize, a re-lay, a
## configure, a load), as the scene tree reports it, within a small
## time budget each frame, nearest the player first. The plant's list
## of things is compared twice a second for new ones. A body is a child
## of the thing, so a move carries it. Moving parts count where they stood
## when the body was built. A thing being carried has no body, so it
## cannot shove the player carrying it.

const SOLID_LAYER := 32
const BUDGET_USEC := 2000
const REFRESH := 0.5
const BODY_META := "solid_body"
const MAX_HULL_POINTS := 256
const RING := 12                # points round a hull's circle

var plant: Plant

var _dirty: Dictionary = {}        # things to look at again; may be freed meanwhile
var _signatures: Dictionary = {}   # instance id -> signature at the last build
var _roots: Dictionary = {}        # the plant's things at the last refresh
var _refresh_in := 0.0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_changed)
	get_tree().node_removed.connect(_on_node_changed)


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = REFRESH
		_refresh()
	if _dirty.is_empty():
		return
	var start := Time.get_ticks_usec()
	var order := _nearest_first(_dirty.keys())
	while not order.is_empty() and Time.get_ticks_usec() - start < BUDGET_USEC:
		var root: Node3D = order.pop_back()
		_dirty.erase(root)
		if root.is_inside_tree():
			_check(root)


## A mesh arriving or leaving under a thing marks that thing for a
## rebuild.
func _on_node_changed(node: Node) -> void:
	if not node is MeshInstance3D:
		return
	var up := node.get_parent()
	while up != null and up != plant:
		if _roots.has(up):
			_dirty[up] = true
			return
		up = up.get_parent()


## The plant's things now: new ones are marked, gone ones forgotten.
func _refresh() -> void:
	var now: Dictionary = {}
	for root in plant.solid_roots():
		now[root] = true
		if not _roots.has(root):
			_dirty[root] = true
	_roots = now
	for root: Variant in _dirty.keys():
		if not is_instance_valid(root) or not _roots.has(root):
			_dirty.erase(root)
	var alive: Dictionary = {}
	for root: Node3D in _roots:
		alive[root.get_instance_id()] = true
	for id: int in _signatures.keys():
		if not alive.has(id):
			_signatures.erase(id)


## The marked things still standing, the nearest last.
func _nearest_first(roots: Array) -> Array:
	var eye := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		eye = camera.global_position
	var valid := roots.filter(func(r: Variant) -> bool: return is_instance_valid(r))
	valid.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(eye) > b.global_position.distance_squared_to(eye))
	return valid


## Carried equipment gives its body up, and has it back when set down.
func set_carried(root: Node3D, carried: bool) -> void:
	if carried:
		root.set_meta("carried", true)
	elif root.has_meta("carried"):
		root.remove_meta("carried")
	_dirty[root] = true


func _check(root: Node3D) -> void:
	var id := root.get_instance_id()
	if root.has_meta("carried"):
		_clear(root)
		_signatures[id] = -1
		return
	if root is PipeView:
		_check_line(root as PipeView)
		return
	var parts: Array[MeshInstance3D] = []
	_parts(root, root, parts)
	var signature := parts.size()
	for part in parts:
		signature = signature * 31 + part.get_instance_id()
		signature = signature * 31 + part.mesh.get_rid().get_id()
		var fitting := part.get_parent()
		if fitting != root and fitting.has_meta("port_name"):
			signature = signature * 31 + hash((fitting as Node3D).position)
	if _signatures.has(id) and int(_signatures[id]) == signature:
		return
	_signatures[id] = signature
	_build(root, parts)


## The visible meshes drawn for root, not those of another root inside
## it, nor anything that is itself a collision body's (a gizmo's cube).
func _parts(node: Node, root: Node3D, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child != root and _roots.has(child):
			continue
		if child.has_meta(BODY_META) or child is CollisionObject3D and not child.has_meta("port_name"):
			continue
		if child is MeshInstance3D:
			var inst := child as MeshInstance3D
			if inst.mesh != null and inst.is_visible_in_tree():
				out.append(inst)
		_parts(child, root, out)


func _build(root: Node3D, parts: Array[MeshInstance3D]) -> void:
	_clear(root)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.set_meta(BODY_META, true)
	var owner_id := body.create_shape_owner(body)
	var to_root := root.global_transform.affine_inverse()
	var points_of: Dictionary = {}   # mesh -> its hull points, once per build
	for part in parts:
		var xf := to_root * part.global_transform
		if part.has_meta("sources"):
			for source: Array in part.get_meta("sources"):
				_hull(body, owner_id, xf * (source[1] as Transform3D), source[0] as Mesh, points_of)
		else:
			_hull(body, owner_id, xf, part.mesh, points_of)
	if body.shape_owner_get_shape_count(owner_id) == 0:
		body.free()
		return
	root.add_child(body)


## A convex hull round one piece, in the root's space.
func _hull(body: StaticBody3D, owner_id: int, xf: Transform3D, mesh: Mesh,
		points_of: Dictionary) -> void:
	if mesh == null:
		return
	if not points_of.has(mesh):
		points_of[mesh] = _outline(mesh)
	var points: PackedVector3Array = points_of[mesh]
	if points.size() < 4:
		return
	var shape := ConvexPolygonShape3D.new()
	shape.points = xf * points
	body.shape_owner_add_shape(owner_id, shape)


## The points a piece's hull goes round, in its own space. A primitive's
## come from its dimensions; reading a mesh's vertices back from the
## graphics card costs a millisecond or more, so only a mesh built by
## hand is read, thinned to MAX_HULL_POINTS.
static func _outline(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh is BoxMesh:
		var half := (mesh as BoxMesh).size / 2.0
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]:
					out.append(Vector3(x, y, z))
	elif mesh is CylinderMesh:
		var cylinder := mesh as CylinderMesh
		_ring(out, cylinder.top_radius, cylinder.height / 2.0)
		_ring(out, cylinder.bottom_radius, -cylinder.height / 2.0)
	elif mesh is CapsuleMesh:
		var capsule := mesh as CapsuleMesh
		var reach := maxf(capsule.height / 2.0 - capsule.radius, 0.0)
		_dome(out, capsule.radius, capsule.radius, reach, 1.0)
		_dome(out, capsule.radius, capsule.radius, -reach, -1.0)
	elif mesh is SphereMesh:
		var sphere := mesh as SphereMesh
		if sphere.is_hemisphere:
			_dome(out, sphere.radius, sphere.height, 0.0, 1.0)
		else:
			_dome(out, sphere.radius, sphere.height / 2.0, 0.0, 1.0)
			_dome(out, sphere.radius, sphere.height / 2.0, 0.0, -1.0)
	elif mesh is TorusMesh:
		var torus := mesh as TorusMesh
		var tube := (torus.outer_radius - torus.inner_radius) / 2.0
		_ring(out, torus.outer_radius, tube)
		_ring(out, torus.outer_radius, -tube)
	elif mesh is PrismMesh:
		var prism := mesh as PrismMesh
		var half := prism.size / 2.0
		for x: float in [-half.x, half.x]:
			for z: float in [-half.z, half.z]:
				out.append(Vector3(x, -half.y, z))
		var apex := (prism.left_to_right - 0.5) * prism.size.x
		out.append(Vector3(apex, half.y, -half.z))
		out.append(Vector3(apex, half.y, half.z))
	elif mesh is PrimitiveMesh:
		var box := mesh.get_aabb().grow(0.005)   # a plane, a quad, text: its box
		for i in 8:
			out.append(box.get_endpoint(i))
	elif mesh.get_surface_count() > 0:
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var stride := maxi(ceili(float(vertices.size()) / MAX_HULL_POINTS), 1)
		for i in range(0, vertices.size(), stride):
			out.append(vertices[i])
	return out


static func _ring(out: PackedVector3Array, radius: float, y: float) -> void:
	if radius <= 0.0005:
		out.append(Vector3(0, y, 0))
		return
	for k in RING:
		var angle := TAU * k / RING
		out.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))


## Half an ellipsoid: rings from the equator at y0 toward the pole on
## the side sign_ points to.
static func _dome(out: PackedVector3Array, radius: float, half_height: float, y0: float,
		sign_: float) -> void:
	for level in 4:
		var angle := PI / 2.0 * level / 4.0
		_ring(out, radius * cos(angle), y0 + sign_ * half_height * sin(angle))
	out.append(Vector3(0, y0 + sign_ * half_height, 0))


func _check_line(line: PipeView) -> void:
	var id := line.get_instance_id()
	if line.style() == "tray":
		_signatures[id] = 0
		return
	var drawn := line.path()
	var signature := hash([drawn, line.radius(), line.style(), line.is_visible_in_tree()])
	if _signatures.has(id) and int(_signatures[id]) == signature:
		return
	_signatures[id] = signature
	_clear(line)
	if not line.is_visible_in_tree() or drawn.size() < 2:
		return
	var points := CableDrape.curve(drawn) if line.style() == "cable" else drawn
	var to_line := line.global_transform.affine_inverse() * line.get_parent_node_3d().global_transform
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.set_meta(BODY_META, true)
	var radius := line.radius()
	for i in points.size() - 1:
		var a := to_line * points[i]
		var b := to_line * points[i + 1]
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = length + 2.0 * radius
		var holder := CollisionShape3D.new()
		holder.shape = capsule
		var along := (b - a) / length
		var side := along.cross(Vector3.UP if absf(along.y) < 0.99 else Vector3.RIGHT).normalized()
		holder.transform = Transform3D(Basis(side, along, side.cross(along)), (a + b) / 2.0)
		body.add_child(holder)
	line.add_child(body)


func _clear(root: Node3D) -> void:
	for child in root.get_children():
		if child.has_meta(BODY_META):
			root.remove_child(child)
			child.queue_free()
