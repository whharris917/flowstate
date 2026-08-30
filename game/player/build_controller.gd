class_name BuildController
extends Node
## Build and connect modes. B toggles build (Tab flips between the
## equipment and structure pages, number keys pick, R rotates, click
## places), C toggles connect (click an output port, lay waypoints,
## finish on an input port — the kernel's wiring rules and the support
## rule both get a veto), X removes player-placed equipment, structure,
## or a routed run. The ghost is grid-snapped and colored by validity.

enum Mode { NORMAL, PLACE, CONNECT }

const GRID := 0.5
const REACH := 7.0

var mode: Mode = Mode.NORMAL
var page: int = 0             # 0 = equipment, 1 = structure
var catalog_index: int = 0
var rot_y: float = 0.0
var _route_ok := true
var _route_span := 0.0

var player: Player
var plant: Plant
var hud: Hud

var _ghost: MeshInstance3D
var _ghost_valid := false
var _ghost_pos := Vector3.ZERO
var _pending_marker: StaticBody3D = null
var _waypoints: Array[Vector3] = []   # global space while routing
var _preview: MeshInstance3D
var _preview_mat: StandardMaterial3D


func setup(player_: Player, plant_: Plant, hud_: Hud) -> void:
	player = player_
	plant = plant_
	hud = hud_
	var mesh := BoxMesh.new()
	_ghost = MeshInstance3D.new()
	_ghost.mesh = mesh
	_ghost.visible = false
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.8, 0.3, 0.35)
	_ghost.material_override = mat
	add_child(_ghost)
	_preview = MeshInstance3D.new()
	_preview.mesh = ImmediateMesh.new()
	_preview_mat = StandardMaterial3D.new()
	_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview.material_override = _preview_mat
	add_child(_preview)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		_set_mode(Mode.NORMAL if mode == Mode.PLACE else Mode.PLACE)
	elif event.is_action_pressed("connect_mode"):
		_set_mode(Mode.NORMAL if mode == Mode.CONNECT else Mode.CONNECT)
	elif event.is_action_pressed("ui_cancel"):
		_set_mode(Mode.NORMAL)
	elif event.is_action_pressed("catalog_page") and mode == Mode.PLACE:
		page = (page + 1) % 2
		catalog_index = 0
		_update_hud()
	elif event.is_action_pressed("rotate_item") and mode == Mode.PLACE:
		rot_y = wrapf(rot_y + PI / 2.0, 0.0, TAU)
	elif event.is_action_pressed("rotate_item") and mode == Mode.CONNECT:
		if not _waypoints.is_empty():
			_waypoints.pop_back()
			_update_hud()
	elif event.is_action_pressed("delete_item"):
		_try_delete()
	elif mode == Mode.PLACE and event.is_action_pressed("place"):
		_try_place()
	elif mode == Mode.CONNECT and event.is_action_pressed("place"):
		_try_pick_port()
	else:
		for i in range(_catalog().size()):
			if event.is_action_pressed("catalog_%d" % (i + 1)):
				catalog_index = i
				if mode != Mode.PLACE:
					_set_mode(Mode.PLACE)
				_update_hud()
				return


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_ghost.visible = false
	_pending_marker = null
	_waypoints.clear()
	(_preview.mesh as ImmediateMesh).clear_surfaces()
	# Connect mode lets the interact ray see port markers (layer 2)
	# alongside the world (1), interact volumes (4), and runs (8).
	player.ray.collision_mask = (1 | 2 | 4 | 8) if mode == Mode.CONNECT else (1 | 4 | 8)
	_route_ok = true
	_route_span = 0.0
	_update_hud()


func _update_hud() -> void:
	match mode:
		Mode.NORMAL:
			hud.set_mode_text("B build · C connect · X remove")
		Mode.PLACE:
			var lines: Array[String] = []
			var catalog := _catalog()
			for i in range(catalog.size()):
				var entry: Dictionary = catalog[i]
				var marker := "> " if i == catalog_index else "  "
				lines.append("%s%d %s" % [marker, i + 1, entry["label"]])
			var page_name := "equipment" if page == 0 else "structure"
			hud.set_mode_text("BUILD [%s] — click place · R rotate · Tab page · B/Esc exit\n%s"
				% [page_name, "\n".join(lines)])
		Mode.CONNECT:
			var step := "click an OUTPUT port (cube)" if _pending_marker == null \
				else "lay the run: click surfaces for waypoints (%d), finish on an INPUT port (sphere) · R undo point" \
				% _waypoints.size()
			var support := "" if _pending_marker == null else \
				("\nsupport OK (span %.1f m)" % _route_span if _route_ok
				else "\nUNSUPPORTED — span %.1f m over %.1f m max: route along structure" \
				% [_route_span, SupportCheck.MAX_SPAN])
			hud.set_mode_text("CONNECT — %s · C/Esc exit%s" % [step, support])


func _physics_process(_delta: float) -> void:
	if mode == Mode.PLACE:
		_update_ghost()
	elif mode == Mode.CONNECT and _pending_marker != null:
		_update_route_preview()
	else:
		(_preview.mesh as ImmediateMesh).clear_surfaces()


func _update_route_preview() -> void:
	var im := _preview.mesh as ImmediateMesh
	im.clear_surfaces()
	var aim := _aim_point()
	var sparse: Array = [_pending_marker.global_position]
	sparse.append_array(_waypoints)
	if aim != Vector3.INF:
		sparse.append(aim)
	if sparse.size() < 2:
		return
	var path := PipeRoute.orthogonalize(sparse)
	if path.size() < 2:
		return
	var check := SupportCheck.evaluate(path,
		player.camera.get_world_3d().direct_space_state)
	var ok := bool(check["ok"])
	var span := float(check["max_span"])
	if ok != _route_ok or absf(span - _route_span) > 0.05:
		_route_ok = ok
		_route_span = span
		var kind: SimTypes.PortKind = _pending_marker.get_meta("kind")
		_preview_mat.albedo_color = PlantFactory.KIND_COLORS[kind] if ok \
			else Color(0.9, 0.2, 0.15)
		_update_hud()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in path:
		im.surface_add_vertex(point)
	im.surface_end()


## Where a clicked waypoint would land: the aimed surface, pushed out
## along its normal, grid-snapped. INF when aiming at nothing.
func _aim_point() -> Vector3:
	if not player.ray.is_colliding():
		return Vector3.INF
	var collider := player.ray.get_collider() as Node
	if collider.has_meta("port_name"):
		return (collider as Node3D).global_position
	var normal := player.ray.get_collision_normal()
	var point := player.ray.get_collision_point() + normal * 0.09
	return Vector3(snappedf(point.x, 0.25), snappedf(point.y, 0.25), snappedf(point.z, 0.25))


func _update_ghost() -> void:
	var camera := player.camera
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * (REACH + player.zoom_offset()), 1)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		_ghost.visible = false
		_ghost_valid = false
		return
	var type_id := _current_type()
	var footprint := _current_footprint()
	var point := hit["position"] as Vector3
	_ghost_pos = Vector3(snappedf(point.x, GRID), point.y, snappedf(point.z, GRID))
	(_ghost.mesh as BoxMesh).size = footprint
	_ghost.global_position = _ghost_pos + Vector3(0, footprint.y / 2.0 + 0.02, 0)
	_ghost.rotation.y = rot_y
	_ghost.visible = true

	var shape := BoxShape3D.new()
	shape.size = footprint * 0.9
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = shape
	overlap.transform = Transform3D(Basis.from_euler(Vector3(0, rot_y, 0)),
		_ghost_pos + Vector3(0, footprint.y / 2.0 + 0.06, 0))
	# World geometry (1) plus interact volumes (4), which stand in for
	# the space equipment occupies.
	overlap.collision_mask = 1 | 4
	overlap.exclude = [player.get_rid()]
	_ghost_valid = space.intersect_shape(overlap, 1).is_empty()
	if _ghost_valid and page == 1:
		_ghost_valid = StructureFactory.placement_ok(type_id, _ghost_pos, rot_y, space) == ""
	(_ghost.material_override as StandardMaterial3D).albedo_color = \
		Color(0.2, 0.8, 0.3, 0.35) if _ghost_valid else Color(0.9, 0.25, 0.2, 0.35)


func _catalog() -> Array[Dictionary]:
	return PlantFactory.CATALOG if page == 0 else StructureFactory.CATALOG


func _current_type() -> String:
	return _catalog()[catalog_index]["type"]


func _current_footprint() -> Vector3:
	return PlantFactory.FOOTPRINTS[_current_type()] if page == 0 \
		else StructureFactory.SIZES[_current_type()]


func _try_place() -> void:
	if not _ghost.visible or not _ghost_valid:
		var reason := "can't place here"
		if page == 1 and _ghost.visible:
			var bearing := StructureFactory.placement_ok(_current_type(), _ghost_pos, rot_y,
				player.camera.get_world_3d().direct_space_state)
			if bearing != "":
				reason = bearing
		hud.toast(reason)
		return
	if page == 1:
		var name_ := plant.unique_struct_name(_current_type())
		if plant.place_structure(_current_type(), name_, _ghost_pos, rot_y):
			hud.toast("placed %s" % name_)
		return
	var record := plant.place_new(_current_type(), _ghost_pos, rot_y)
	if record != null:
		hud.toast("placed %s" % record.comp_name)


func _try_pick_port() -> void:
	var collider := player.ray.get_collider() if player.ray.is_colliding() else null
	if collider == null:
		return
	var node := collider as Node
	if not node.has_meta("port_name"):
		# A surface click while routing lays a waypoint.
		if _pending_marker != null:
			var aim := _aim_point()
			if aim != Vector3.INF:
				_waypoints.append(aim)
				_update_hud()
		return
	var marker := collider as StaticBody3D
	if _pending_marker == null:
		if bool(marker.get_meta("is_input")):
			hud.toast("start from an OUTPUT port (cube)")
			return
		_pending_marker = marker
		var kind: SimTypes.PortKind = marker.get_meta("kind")
		_preview_mat.albedo_color = PlantFactory.KIND_COLORS[kind]
		_update_hud()
		return
	if not bool(marker.get_meta("is_input")):
		hud.toast("finish on an INPUT port (sphere)")
		return
	# The support rule gets its veto before the kernel does. Routing
	# state is kept so the run can be fixed with more waypoints.
	var final_sparse: Array = [_pending_marker.global_position]
	final_sparse.append_array(_waypoints)
	final_sparse.append((marker as Node3D).global_position)
	var check := SupportCheck.evaluate(PipeRoute.orthogonalize(final_sparse),
		player.camera.get_world_3d().direct_space_state)
	if not bool(check["ok"]):
		hud.toast("unsupported span %.1f m (max %.1f) — route along structure"
			% [float(check["max_span"]), SupportCheck.MAX_SPAN])
		return
	var local_points: Array = []
	for point in _waypoints:
		local_points.append(plant.to_local(point))
	var error := plant.connect_equipment(
		str(_pending_marker.get_meta("record_name")), str(_pending_marker.get_meta("port_name")),
		str(marker.get_meta("record_name")), str(marker.get_meta("port_name")),
		local_points)
	hud.toast("connected" if error == "" else error)
	_pending_marker = null
	_waypoints.clear()
	_update_hud()


func _try_delete() -> void:
	var view := player.look_view()
	if view == null:
		return
	if view is PipeView:
		hud.toast("removed run" if plant.remove_run(view as PipeView) else "can't remove that run")
		return
	if view.has_meta("structure_name"):
		var struct_name := str(view.get_meta("structure_name"))
		if plant.remove_structure(struct_name):
			hud.toast("removed %s — runs it carried re-check" % struct_name)
		return
	if not view.has_meta("record_name"):
		return
	var name_ := str(view.get_meta("record_name"))
	if plant.remove_equipment(name_):
		hud.toast("removed %s" % name_)
	else:
		hud.toast("%s is commissioned equipment — can't remove" % name_)
