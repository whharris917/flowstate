class_name LegGizmo
extends Node3D
## The selection of one straight of a line (director, 2026-09-13:
## per-leg selection): a translucent sleeve along the leg, and a cube
## handle at each of its ends that is a corner the player may move —
## the stubs and the fittings' own points are not. Handles live on
## EditGizmo.LAYER like the equipment gizmo's, so the same drag picks
## them. Positions are plant-local; the gizmo sits under the plant.

const HANDLE := 0.22

var pipe: PipeView = null
var leg := -1
var path: Array[Vector3] = []
var corners: Array = []          # the line's own corners (Plant.wire_corners)
var _slots: Array[int] = []      # path index -> its corner's slot, or -1
var _handles: Array[StaticBody3D] = []
var _hover: MeshInstance3D = null   # where a grab on the straight would put a corner
var _sleeve: MeshInstance3D = null


var locks: Array = []   # the line's locked waypoints, plant-local


func setup(pipe_: PipeView, leg_: int, path_: Array[Vector3], corners_: Array, locks_: Array = []) -> void:
	pipe = pipe_
	leg = leg_
	refresh(path_, corners_, locks_)


## Rebuild round the leg as it is now laid. A rendered corner is the
## player's to move when one of the line's own corners lies within a
## lane's width of it; a lane sidestep or a bridge ramp has none.
func refresh(path_: Array[Vector3], corners_: Array, locks_: Array = []) -> void:
	path = path_
	corners = corners_
	locks = locks_
	_slots.clear()
	for i in path.size():
		var slot := -1
		var nearest := 0.6
		for k in corners.size():
			var d := (corners[k] as Vector3).distance_to(path[i])
			if d < nearest:
				nearest = d
				slot = k
		_slots.append(slot)
	for child in get_children():
		child.queue_free()
	_handles.clear()
	_sleeve = null
	_hover = null
	if leg < 0 or leg >= path.size() - 1:
		return
	var a := path[leg]
	var b := path[leg + 1]
	var length := a.distance_to(b)
	if length < 0.01:
		return
	# The sleeve: unshaded, translucent, a little fatter than the pipe.
	var mesh := CylinderMesh.new()
	mesh.top_radius = pipe.radius() + 0.05
	mesh.bottom_radius = mesh.top_radius
	mesh.height = length
	mesh.radial_segments = 16
	_sleeve = MeshInstance3D.new()
	_sleeve.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.35, 0.8, 1.0, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sleeve.material_override = mat
	_sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sleeve)
	_sleeve.position = (a + b) / 2.0
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_sleeve.basis = Basis.looking_at(dir, up) * Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
	# A cube at every corner of the whole line, not only the selected
	# straight's ends (director, 2026-09-19: "clicking any pipe segment
	# should show the gold cube handles for all corners on the whole
	# continuous pipe"); the middle cubes went the same day. A handle is
	# named by its path index.
	for index in path.size():
		if movable_corner(index):
			# A locked corner is steel-grey; the rest gold.
			var color := Color(0.55, 0.60, 0.68) if is_locked(index) else Color(0.95, 0.80, 0.30)
			_make_handle("pt%d" % index, path[index], HANDLE, color)
	# The hover cube: shown on the straight under the crosshair, so it is
	# clear a press there makes a corner and drags it (director, 2026-09-19).
	_hover = MeshInstance3D.new()
	var hover_mesh := BoxMesh.new()
	# Wider than the pipe, and drawn over it: inside the pipe it was
	# half hidden (director, 2026-09-19).
	hover_mesh.size = Vector3.ONE * maxf(HANDLE * 0.55, pipe.radius() * 2.0 + 0.05)
	_hover.mesh = hover_mesh
	var hover_mat := ViewUtil.glow(Color(1.0, 0.95, 0.75), 0.9)
	hover_mat.no_depth_test = true
	hover_mat.render_priority = 2
	_hover.material_override = hover_mat
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)


## Show the hover cube at a point of the leg, or hide it (Vector3.INF).
func set_hover(at: Vector3) -> void:
	if _hover == null:
		return
	if at == Vector3.INF:
		_hover.visible = false
		return
	_hover.position = at
	_hover.visible = true


func _make_handle(name_: String, at: Vector3, size: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = EditGizmo.LAYER
	body.collision_mask = 0
	body.set_meta("handle", name_)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size
	shape.shape = box
	body.add_child(shape)
	var cube := MeshInstance3D.new()
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3.ONE * size
	cube.mesh = cube_mesh
	cube.material_override = ViewUtil.glow(color, 0.9)
	body.add_child(cube)
	body.position = at
	add_child(body)
	_handles.append(body)


## A point the player may move: every corner of the line as laid but
## the two fittings — a stub end too, since pulling the end of a
## straight at a fitting puts a corner there (director, 2026-09-19:
## "the end of the straight segment closer to the pump doesn't have a
## gold cube"). A stub itself stays: its far end is the fitting.
func movable_corner(index: int) -> bool:
	return index >= 1 and index <= path.size() - 2


## Is the path point a locked waypoint (through a lane's shift)?
func is_locked(index: int) -> bool:
	var p: Vector3 = path[index]
	for lock: Vector3 in locks:
		if Vector2(lock.x - p.x, lock.z - p.z).length() < 0.75 and absf(lock.y - p.y) < 0.3:
			return true
	return false


## The corner a handle stands on: the path index in its name ("pt5");
## "grab" stands before the selected leg's end, for ordering.
func corner_index(handle: String) -> int:
	if handle.begins_with("pt"):
		return int(handle.substr(2))
	return leg + 1


## Where a handle's drag starts from: its corner.
func drag_origin(handle: String) -> Vector3:
	var index := corner_index(handle)
	return path[index] if index >= 0 and index < path.size() else Vector3.INF


## The slot in `corners` behind a path index, or -1.
func corner_slot(index: int) -> int:
	return _slots[index] if index >= 0 and index < _slots.size() else -1
