class_name EditGizmo
extends Node3D
## In-world handles for M edit mode (director's design, 2026-09-05):
## the equipment stays exactly as it is, at its real size, and grows
## handles — a ring round a tank for its diameter, a post above it for
## its height, crossed double-headed arrows at its base to move it
## along world X, world Z, or freely from the centre cube. Each handle
## is a StaticBody3D on LAYER, which the interact ray sees only in edit
## mode, carrying meta "handle". The maths of a drag lives in static
## functions so the headless smoke can check it without a camera.

const LAYER := 16
const GRID := 0.5
const SIZE_STEP := 0.1
const MIN_H := 0.5
const MAX_H := 12.0
const MIN_D := 0.4
const MAX_D := 6.0
const ARM := 1.3          # half-length of a move arrow
const RING_GAP := 0.15    # ring radius beyond the shell
const RING_SEGMENTS := 24

var view: Node3D = null
var tank: SimTank = null
var base_y_offset := 0.0   # the view sits this far above its placement point
var _move_meshes: Array[MeshInstance3D] = []
var _move_mats: Array[StandardMaterial3D] = []
var _blocked_mat: StandardMaterial3D = ViewUtil.glow(Color(0.95, 0.25, 0.2), 1.2)


func setup(view_: Node3D, tank_: SimTank, base_y_offset_: float = 0.0) -> void:
	view = view_
	tank = tank_
	base_y_offset = base_y_offset_
	refresh()


## The placement point the handles sit on: the view's origin less its
## mounting offset, in world space.
func base() -> Vector3:
	return view.global_position - Vector3(0, base_y_offset, 0)


## Rebuild the handles around the equipment's current size and spot.
func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_move_meshes.clear()
	_move_mats.clear()
	global_position = base()
	rotation = Vector3.ZERO
	_build_move()
	if tank != null:
		_build_ring()
		_build_post()


## The move arrows turn red while the spot under them is taken.
func set_blocked(blocked: bool) -> void:
	for i in _move_meshes.size():
		_move_meshes[i].material_override = _blocked_mat if blocked else _move_mats[i]


## ---- the raw geometry of a drag ------------------------------------------

static func raw_diameter(base_: Vector3, hit: Vector3) -> float:
	return 2.0 * Vector2(hit.x - base_.x, hit.z - base_.z).length()


static func diameter_from(base_: Vector3, hit: Vector3, offset: float = 0.0) -> float:
	return clampf(snappedf(raw_diameter(base_, hit) + offset, SIZE_STEP), MIN_D, MAX_D)


static func raw_height(base_: Vector3, hit: Vector3) -> float:
	return hit.y - base_.y


static func height_from(base_: Vector3, hit: Vector3, offset: float = 0.0) -> float:
	return clampf(snappedf(raw_height(base_, hit) + offset, SIZE_STEP), MIN_H, MAX_H)


## Where the equipment goes for a hit on the ground plane: the grabbed
## point stays under the crosshair (offset), snapped to the build grid,
## constrained to one axis by the arrow that was grabbed.
static func move_target(base_: Vector3, hit: Vector3, offset: Vector3, handle: String) -> Vector3:
	var target := base_
	if handle != "move_z":
		target.x = snappedf(hit.x + offset.x, GRID)
	if handle != "move_x":
		target.z = snappedf(hit.z + offset.z, GRID)
	return target


## ---- handles ----------------------------------------------------------------

func _build_move() -> void:
	var y := 0.08
	var red := ViewUtil.glow(Color(0.90, 0.30, 0.25), 0.9)
	var blue := ViewUtil.glow(Color(0.30, 0.55, 0.95), 0.9)
	var gold := ViewUtil.glow(Color(0.95, 0.80, 0.30), 0.9)
	# X arrow: shaft plus a cone each end.
	_move_part(ViewUtil.box(self, Vector3(2.0 * ARM, 0.05, 0.05), Vector3(0, y, 0), red), red)
	_move_part(_cone(Vector3(ARM + 0.12, y, 0), Vector3(0, 0, -PI / 2.0), red), red)
	_move_part(_cone(Vector3(-ARM - 0.12, y, 0), Vector3(0, 0, PI / 2.0), red), red)
	# Z arrow.
	_move_part(ViewUtil.box(self, Vector3(0.05, 0.05, 2.0 * ARM), Vector3(0, y, 0), blue), blue)
	_move_part(_cone(Vector3(0, y, ARM + 0.12), Vector3(PI / 2.0, 0, 0), blue), blue)
	_move_part(_cone(Vector3(0, y, -ARM - 0.12), Vector3(-PI / 2.0, 0, 0), blue), blue)
	# Centre cube: free movement.
	_move_part(ViewUtil.box(self, Vector3(0.16, 0.16, 0.16), Vector3(0, y, 0), gold), gold)
	# Colliders: each arm in two halves so the centre cube wins at the
	# crossing, the cube its own.
	var half := ARM + 0.24 - 0.2
	var x_body := _handle("move_x")
	_shape(x_body, Vector3(half, 0.2, 0.2), Vector3(0.2 + half / 2.0, y, 0))
	_shape(x_body, Vector3(half, 0.2, 0.2), Vector3(-0.2 - half / 2.0, y, 0))
	var z_body := _handle("move_z")
	_shape(z_body, Vector3(0.2, 0.2, half), Vector3(0, y, 0.2 + half / 2.0))
	_shape(z_body, Vector3(0.2, 0.2, half), Vector3(0, y, -0.2 - half / 2.0))
	_shape(_handle("move_xz"), Vector3(0.3, 0.3, 0.3), Vector3(0, y, 0))


func _build_ring() -> void:
	var radius := tank.diameter_m / 2.0 + RING_GAP
	var y := tank.height_m * 0.5
	var cyan := ViewUtil.glow(Color(0.35, 0.85, 0.90), 1.0)
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.03
	torus.outer_radius = radius + 0.03
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.material_override = cyan
	mesh.position = Vector3(0, y, 0)
	add_child(mesh)
	# Four grab knobs so the ring reads as a handle from any side.
	for i in 4:
		var a := TAU / 4.0 * i + PI / 4.0
		ViewUtil.box(self, Vector3(0.14, 0.14, 0.14),
			Vector3(radius * cos(a), y, radius * sin(a)), cyan)
	var body := _handle("ring")
	var seg := TAU * radius / RING_SEGMENTS * 1.15
	for i in RING_SEGMENTS:
		var a := TAU / RING_SEGMENTS * i
		var shape := _shape(body, Vector3(seg, 0.16, 0.16),
			Vector3(radius * cos(a), y, radius * sin(a)))
		shape.rotation.y = -(a + PI / 2.0)


func _build_post() -> void:
	var top := tank.height_m
	var green := ViewUtil.glow(Color(0.45, 0.90, 0.45), 1.0)
	ViewUtil.cylinder(self, 0.03, 0.7, Vector3(0, top + 0.35, 0), green)
	_cone(Vector3(0, top + 0.78, 0), Vector3.ZERO, green)
	_cone(Vector3(0, top - 0.08, 0), Vector3(PI, 0, 0), green)
	_shape(_handle("post"), Vector3(0.3, 1.0, 0.3), Vector3(0, top + 0.4, 0))


func _cone(pos: Vector3, rot: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.24
	var mesh := MeshInstance3D.new()
	mesh.mesh = cone
	mesh.material_override = mat
	mesh.position = pos
	mesh.rotation = rot
	add_child(mesh)
	return mesh


func _move_part(mesh: MeshInstance3D, mat: StandardMaterial3D) -> void:
	_move_meshes.append(mesh)
	_move_mats.append(mat)


func _handle(kind: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.set_meta("handle", kind)
	add_child(body)
	return body


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	return shape
