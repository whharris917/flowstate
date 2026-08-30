class_name BuildController
extends Node
## Build and connect modes. B toggles build (Tab flips between the
## equipment and structure pages of the graphical hotbar, number keys
## pick, R rotates, click places), C toggles connect (click an output
## port, lay waypoints, finish on an input port — the kernel's wiring
## rules and the support rule both get a veto), X removes player-placed
## equipment, structure, or a routed run. The placement ghost is the
## asset's real geometry, tinted by validity; the route preview is
## real translucent pipe.

enum Mode { NORMAL, PLACE, CONNECT }

const GRID := 0.5
const REACH := 7.0

var mode: Mode = Mode.NORMAL
var page: int = 0             # 0 = equipment, 1 = structure
var catalog_index: int = 0
var rot_y: float = 0.0

var player: Player
var plant: Plant
var hud: Hud
var menu: BuildMenu
var icons: AssetIcons

var _ghost: Node3D = null
var _ghost_type := ""
var _ghost_mat: StandardMaterial3D
var _ghost_valid := false
var _ghost_pos := Vector3.ZERO
var _pending_marker: StaticBody3D = null
var _waypoints: Array[Vector3] = []   # global space while routing
var _route_node: Node3D
var _route_mat: StandardMaterial3D
var _last_route: Array[Vector3] = []
var _route_ok := true
var _route_span := 0.0


func setup(player_: Player, plant_: Plant, hud_: Hud) -> void:
	player = player_
	plant = plant_
	hud = hud_
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.2, 0.8, 0.3, 0.45)
	_route_node = Node3D.new()
	add_child(_route_node)
	_route_mat = StandardMaterial3D.new()
	_route_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	icons = AssetIcons.new()
	add_child(icons)
	var all_types: Array = []
	for entry: Dictionary in PlantFactory.CATALOG + StructureFactory.CATALOG:
		all_types.append(entry["type"])
	icons.generate(all_types)  # fire and forget; cards fill in as renders land
	menu = BuildMenu.new()
	menu.visible = false
	hud.add_child(menu)
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
	_clear_ghost()
	_pending_marker = null
	_waypoints.clear()
	_clear_route()
	# Connect mode lets the interact ray see port markers (layer 2)
	# alongside the world (1), interact volumes (4), and runs (8).
	player.ray.collision_mask = (1 | 2 | 4 | 8) if mode == Mode.CONNECT else (1 | 4 | 8)
	_route_ok = true
	_route_span = 0.0
	_update_hud()


func _update_hud() -> void:
	match mode:
		Mode.NORMAL:
			menu.visible = false
			hud.set_mode_text("B build · C connect · X remove")
		Mode.PLACE:
			var page_name := "EQUIPMENT — Tab for structure" if page == 0 \
				else "STRUCTURE — Tab for equipment"
			menu.show_page(page_name, _catalog(), icons, catalog_index)
			hud.set_mode_text("BUILD — click place · R rotate · B/Esc exit")
		Mode.CONNECT:
			menu.visible = false
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
		_clear_route()


## ---- route preview -------------------------------------------------------

func _update_route_preview() -> void:
	var aim := _aim_point()
	var sparse: Array = [_pending_marker.global_position]
	sparse.append_array(_waypoints)
	if aim != Vector3.INF:
		sparse.append(aim)
	if sparse.size() < 2:
		_clear_route()
		return
	var path := PipeRoute.orthogonalize(sparse)
	if path.size() < 2:
		_clear_route()
		return
	var check := SupportCheck.evaluate(path,
		player.camera.get_world_3d().direct_space_state)
	var ok := bool(check["ok"])
	var span := float(check["max_span"])
	if ok != _route_ok or absf(span - _route_span) > 0.05:
		_route_ok = ok
		_route_span = span
		_update_hud()
	var kind: SimTypes.PortKind = _pending_marker.get_meta("kind")
	var base_color: Color = PlantFactory.KIND_COLORS[kind] if ok else Color(0.9, 0.2, 0.15)
	_route_mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.6)
	if path != _last_route:
		_last_route = path
		_rebuild_route(path, kind)


## Real translucent pipe as the preview — same radii and elbows the
## committed run will have.
func _rebuild_route(path: Array[Vector3], kind: SimTypes.PortKind) -> void:
	for old in _route_node.get_children():
		old.queue_free()
	var is_process := kind == SimTypes.PortKind.PROCESS_FLOW \
		or kind == SimTypes.PortKind.PROCESS_LEVEL
	var radius := 0.07 if is_process else 0.025
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
		inst.material_override = _route_mat
		_route_node.add_child(inst)
		inst.global_position = (from + to) / 2.0
		var direction := (to - from).normalized()
		if absf(direction.y) < 0.99:
			inst.look_at(to, Vector3.UP)
			inst.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		if i > 0:
			var elbow := SphereMesh.new()
			elbow.radius = radius * 1.2
			elbow.height = radius * 2.4
			var joint := MeshInstance3D.new()
			joint.mesh = elbow
			joint.material_override = _route_mat
			_route_node.add_child(joint)
			joint.global_position = from


func _clear_route() -> void:
	if _route_node == null:
		return
	for old in _route_node.get_children():
		old.queue_free()
	_last_route = []


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


## ---- placement ghost -----------------------------------------------------

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_type = ""


## The ghost is the asset's actual geometry, tinted translucent.
func _refresh_ghost_asset() -> void:
	var type_id := _current_type()
	if type_id == _ghost_type and _ghost != null:
		return
	_clear_ghost()
	_ghost = AssetPreview.build(type_id)
	if _ghost == null:
		return
	AssetPreview.tint(_ghost, _ghost_mat)
	_ghost.visible = false
	add_child(_ghost)
	_ghost_type = type_id


func _update_ghost() -> void:
	_refresh_ghost_asset()
	if _ghost == null:
		return
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
	_ghost.global_position = _ghost_pos + Vector3(0, AssetPreview.base_offset(type_id), 0)
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
	_ghost_mat.albedo_color = Color(0.25, 0.85, 0.35, 0.45) if _ghost_valid \
		else Color(0.9, 0.25, 0.2, 0.45)


func _catalog() -> Array[Dictionary]:
	return PlantFactory.CATALOG if page == 0 else StructureFactory.CATALOG


func _current_type() -> String:
	return _catalog()[catalog_index]["type"]


func _current_footprint() -> Vector3:
	return PlantFactory.FOOTPRINTS[_current_type()] if page == 0 \
		else StructureFactory.SIZES[_current_type()]


## ---- actions -------------------------------------------------------------

func _try_place() -> void:
	if _ghost == null or not _ghost.visible or not _ghost_valid:
		var reason := "can't place here"
		if page == 1 and _ghost != null and _ghost.visible:
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
	_clear_route()
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
