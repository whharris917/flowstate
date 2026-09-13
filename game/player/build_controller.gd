class_name BuildController
extends Node
## Build and connect modes. B toggles build (Tab flips between the
## equipment and structure pages of the graphical hotbar, number keys
## pick, R rotates, click places), C toggles connect (click an output
## port, lay waypoints, finish on an input port — the kernel's wiring
## rules and the support rule both get a veto), X removes player-placed
## equipment, structure, or a routed run, M puts placed equipment into
## edit mode: in-world handles on the real thing (EditGizmo) for its
## size and its spot, dragged by aiming at one and holding click. The
## placement ghost is the asset's real geometry, tinted by validity;
## the route preview is real translucent pipe.

enum Mode { NORMAL, PLACE, CONNECT, EDIT }

const GRID := 0.5
const REACH := 7.0
const ALIGN_SNAP := 0.35     # pull-in distance onto a neighbor's axis
const ALIGN_RANGE := 24.0    # how far away an alignment partner may be

var mode: Mode = Mode.NORMAL
var page: int = 0             # 0 = equipment, 1 = structure
var catalog_index: int = 0
var rot_y: float = 0.0

var player: Player
var plant: Plant
var hud: Hud
var menu: BuildMenu
var icons: AssetIcons
var port_menu: DeviceMenu

var _ghost: Node3D = null
var _ghost_type := ""
var _ghost_mat: StandardMaterial3D
var _ghost_valid := false
var _ghost_pos := Vector3.ZERO
# Where a shell-mounted instrument would go: the vessel under the
# crosshair, and the height and bearing on its shell.
var _mount_host := ""
var _mount_frac := 0.5
var _mount_angle := 0.0
var _guide_mesh: MeshInstance3D
var _align_targets: Array[Vector3] = []
var _beam_ghost: MeshInstance3D
var _beam_anchor := Vector3.INF
var _beam_end := Vector3.INF
var _beam_len := 0.0
var _run_points: Array[Vector3] = []   # global space while laying a run
var _pending_marker: StaticBody3D = null
var _waypoints: Array[Vector3] = []   # global space while routing
var _route_node: Node3D
var _route_mat: StandardMaterial3D
var _last_route: Array[Vector3] = []
var _route_ok := true
var _route_span := 0.0
var _nozzle_grab: Dictionary = {}   # {view, port, was: {frac, angle}}
# Edit mode: the equipment under the handles, and the handle being dragged.
var _edit_name := ""
var _gizmo: EditGizmo = null
var _drag := ""
var _drag_offset_f := 0.0          # size the grab started at, less the raw hit
var _drag_offset_v := Vector3.ZERO  # base less the grab point, so it stays under the pointer
var _edit_cam: EditCamera = null
var _orbiting := false
var _panning := false
var _right_down := false
var _right_moved := false


func setup(player_: Player, plant_: Plant, hud_: Hud) -> void:
	player = player_
	plant = plant_
	hud = hud_
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.2, 0.8, 0.3, 0.45)
	_beam_ghost = MeshInstance3D.new()
	_beam_ghost.mesh = BoxMesh.new()
	_beam_ghost.material_override = _ghost_mat
	_beam_ghost.visible = false
	add_child(_beam_ghost)
	_guide_mesh = MeshInstance3D.new()
	_guide_mesh.mesh = ImmediateMesh.new()
	var guide_mat := StandardMaterial3D.new()
	guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guide_mat.albedo_color = Color(0.35, 0.9, 0.95, 0.9)
	_guide_mesh.material_override = guide_mat
	add_child(_guide_mesh)
	_route_node = Node3D.new()
	add_child(_route_node)
	_route_mat = StandardMaterial3D.new()
	_route_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	icons = AssetIcons.new()
	add_child(icons)
	var all_types: Array = []
	for entry: Dictionary in PlantFactory.CATALOG + PlantFactory.CATALOG_SEPARATION \
			+ PlantFactory.CATALOG_INSTRUMENTS \
			+ StructureFactory.CATALOG + StructureFactory.CATALOG_ROUTING \
			+ PlantFactory.CATALOG_CONTROL + PlantFactory.CATALOG_UTILITIES:
		all_types.append(entry["type"])
	icons.generate(all_types)  # fire and forget; cards fill in as renders land
	menu = BuildMenu.new()
	menu.visible = false
	hud.add_child(menu)
	port_menu = DeviceMenu.new()
	hud.add_child(port_menu)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		_set_mode(Mode.NORMAL if mode == Mode.PLACE else Mode.PLACE)
	elif event.is_action_pressed("connect_mode"):
		_set_mode(Mode.NORMAL if mode == Mode.CONNECT else Mode.CONNECT)
	elif event.is_action_pressed("ui_cancel"):
		_set_mode(Mode.NORMAL)
	elif event.is_action_pressed("catalog_page") and mode == Mode.PLACE:
		page = (page + 1) % 7
		catalog_index = 0
		_beam_anchor = Vector3.INF
		_run_points.clear()
		_clear_route()
		_update_hud()
	elif event.is_action_pressed("interact") and mode == Mode.PLACE and _is_run():
		_finish_run()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_item") and mode == Mode.PLACE:
		if _is_stretch() and _beam_anchor != Vector3.INF:
			_beam_anchor = Vector3.INF
			_update_hud()
		elif _is_run() and not _run_points.is_empty():
			_run_points.pop_back()
			_update_hud()
		else:
			rot_y = wrapf(rot_y + PI / 2.0, 0.0, TAU)
	elif event.is_action_pressed("rotate_item") and mode == Mode.CONNECT:
		if not _waypoints.is_empty():
			_waypoints.pop_back()
			_update_hud()
	elif event.is_action_pressed("move_port") and mode == Mode.CONNECT:
		_toggle_nozzle_grab()
	elif event.is_action_pressed("move_item"):
		_toggle_edit()
	elif mode == Mode.EDIT and _edit_mouse(event):
		get_viewport().set_input_as_handled()
	elif mode == Mode.EDIT and event.is_action_pressed("rotate_item"):
		_rotate_edited()
	elif mode == Mode.CONNECT and not _nozzle_grab.is_empty() \
			and event.is_action_pressed("place"):
		_commit_nozzle_grab()
	elif event.is_action_pressed("port_menu"):
		_open_port_menu()
	elif event.is_action_pressed("delete_item"):
		_try_delete()
	elif mode == Mode.PLACE and event.is_action_pressed("place"):
		_try_place()
	elif mode == Mode.CONNECT and event.is_action_pressed("place"):
		_try_pick_port()
	elif mode == Mode.NORMAL and event.is_action_pressed("place"):
		# Clicking a clickable affordance (the cabinet's EDIT button).
		var clicked := player.look_view()
		if clicked != null and clicked.has_method("use") \
				and player.ray.is_colliding() \
				and (player.ray.get_collider() as Node).has_meta("clickable"):
			clicked.call("use")
	else:
		for i in range(_catalog().size()):
			if event.is_action_pressed("catalog_%d" % (i + 1)):
				catalog_index = i
				_beam_anchor = Vector3.INF
				_run_points.clear()
				_clear_route()
				if mode != Mode.PLACE:
					_set_mode(Mode.PLACE)
				_update_hud()
				return


func _set_mode(new_mode: Mode) -> void:
	if not _nozzle_grab.is_empty():
		_toggle_nozzle_grab()  # cancel and restore
	mode = new_mode
	_end_edit()
	_clear_ghost()
	_beam_anchor = Vector3.INF
	_beam_ghost.visible = false
	_run_points.clear()
	(_guide_mesh.mesh as ImmediateMesh).clear_surfaces()
	_pending_marker = null
	_waypoints.clear()
	_clear_route()
	# Connect mode lets the interact ray see port markers (layer 2)
	# alongside the world (1), interact volumes (4), and runs (8); edit
	# mode, the gizmo's handles.
	player.ray.collision_mask = 1 | 4 | 8
	if mode == Mode.CONNECT:
		player.ray.collision_mask |= 2
	elif mode == Mode.EDIT:
		player.ray.collision_mask |= EditGizmo.LAYER
	_route_ok = true
	_route_span = 0.0
	_update_hud()


func _update_hud() -> void:
	match mode:
		Mode.NORMAL:
			menu.visible = false
			hud.set_mode_text("B build · C connect · M modify · X remove · right-click: I/O & configure")
		Mode.EDIT:
			menu.visible = false
			var handles := "arrows move it (red X, blue Z, gold cube free)"
			if plant.sim.get_component(_edit_name) is SimTank:
				handles = "ring = diameter · post = height · " + handles
			hud.set_mode_text("MODIFY %s — drag a handle: %s · middle-drag pan · shift+middle or right-drag orbit · wheel zoom · R rotate · M/Esc done"
				% [_edit_name, handles])
		Mode.PLACE:
			var page_names: Array[String] = ["EQUIPMENT", "SEPARATION", "INSTRUMENTS", "STRUCTURE",
				"ROUTING · FLOOR · SIGNS", "CONTROL", "UTILITIES"]
			var entries := _catalog()
			catalog_index = mini(catalog_index, maxi(entries.size() - 1, 0))
			var heading := "%s — Tab for %s" % [page_names[page], page_names[(page + 1) % 7]]
			if entries.is_empty():
				heading += "  ·  nothing unlocked here yet — J for the journal"
			menu.show_page(heading, entries, icons, catalog_index)
			if _is_stretch():
				var spec: Dictionary = StructureFactory.STRETCH[_current_type()]
				var step := "click a supported START point" if _beam_anchor == Vector3.INF \
					else "click the END point (max %.0f m) · R restart" % float(spec["max"])
				hud.set_mode_text("STRETCH — %s · B/Esc exit" % step)
			elif _is_run():
				var support := "" if _run_points.size() < 2 else \
					("\nsupport OK (span %.1f m)" % _route_span if _route_ok
					else "\nUNSUPPORTED — span %.1f m over %.1f m max" \
					% [_route_span, SupportCheck.MAX_SPAN])
				hud.set_mode_text("RUN — click surfaces to lay points (%d) · E finish · R undo · B/Esc exit%s"
					% [_run_points.size(), support])
			else:
				hud.set_mode_text("BUILD — click place · R rotate · B/Esc exit")
		Mode.CONNECT:
			menu.visible = false
			var step := "click an outlet fitting · G moves a vessel nozzle" if _pending_marker == null \
				else "lay the run: click surfaces for waypoints (%d), finish on an inlet fitting · R undo point" \
				% _waypoints.size()
			var support := "" if _pending_marker == null else \
				("\nsupport OK (span %.1f m)" % _route_span if _route_ok
				else "\nUNSUPPORTED — span %.1f m over %.1f m max: route along structure" \
				% [_route_span, SupportCheck.MAX_SPAN])
			hud.set_mode_text("CONNECT — %s · C/Esc exit%s" % [step, support])


func _physics_process(_delta: float) -> void:
	if not _nozzle_grab.is_empty():
		plant._finish_scans()  # a grab moves a nozzle's elevation in the sim
		_update_nozzle_grab()
		return
	if mode == Mode.PLACE:
		_update_ghost()
	elif mode == Mode.CONNECT and _pending_marker != null:
		_update_route_preview()
	elif mode == Mode.EDIT:
		if _drag != "":
			_update_drag()
	else:
		_clear_route()


## ---- nozzle relocation (G in connect mode) --------------------------------

func _toggle_nozzle_grab() -> void:
	if not _nozzle_grab.is_empty():
		# Cancel: restore the original spot.
		var view := _nozzle_grab["view"] as TankView
		var was: Dictionary = _nozzle_grab["was"]
		view.set_nozzle(str(_nozzle_grab["port"]), float(was["frac"]), float(was["angle"]))
		_nozzle_grab = {}
		hud.toast("nozzle move cancelled")
		return
	var collider := player.aimed_collider()
	if collider == null or not collider.has_meta("movable"):
		hud.toast("aim at a vessel nozzle to move it")
		return
	var view := collider.get_meta("owner_view") as TankView
	var port := str(collider.get_meta("port_name"))
	_nozzle_grab = {"view": view, "port": port,
		"was": (view.nozzles[port] as Dictionary).duplicate()}
	hud.toast("moving %s — aim on the shell, click to weld, G cancels" % port)


func _update_nozzle_grab() -> void:
	var view := _nozzle_grab["view"] as TankView
	if not player.ray.is_colliding():
		return
	var collider := player.ray.get_collider() as Node
	# Only spots on this vessel count: its interact volume stands in
	# for the shell, and the nozzle being carried is on the shell too.
	if collider == null:
		return
	var on_vessel: bool = (collider.has_meta("view") and collider.get_meta("view") == view) \
		or (collider.has_meta("owner_view") and collider.get_meta("owner_view") == view)
	if not on_vessel:
		return
	var local: Vector3 = view.to_local(player.ray.get_collision_point())
	var angle := atan2(local.z, local.x)
	var frac := clampf(local.y / view.tank.height_m, 0.04, 0.97)
	view.set_nozzle(str(_nozzle_grab["port"]), frac, angle)


func _commit_nozzle_grab() -> void:
	var view := _nozzle_grab["view"] as TankView
	var record_name := view.tank.comp_name
	var port := str(_nozzle_grab["port"])
	_nozzle_grab = {}
	plant.refresh_wires_of(record_name)
	hud.toast("welded %s in place" % port)


## ---- route preview -------------------------------------------------------

func _update_route_preview() -> void:
	var aim := _aim_point()
	var tail: Array = []
	tail.append_array(_waypoints)
	if aim != Vector3.INF:
		tail.append(aim)
	if tail.is_empty():
		_clear_route()
		return
	var path := PipeRoute.routed_open(_pending_marker.global_position,
		_pending_marker.global_basis.x.normalized(), tail)
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
		var is_process := kind == SimTypes.PortKind.PROCESS_MATERIAL \
			or kind == SimTypes.PortKind.PROCESS_LEVEL
		_rebuild_route(path, 0.07 if is_process else 0.025, "pipe")


## Standalone run laying: the preview is the run itself, stretched to
## the aim point; clicks pin points, E commits.
func _update_run_preview() -> void:
	var aim := _aim_point()
	var sparse: Array = []
	sparse.append_array(_run_points)
	if aim != Vector3.INF and (_run_points.is_empty()
			or aim.distance_to(_run_points[_run_points.size() - 1]) > 0.01):
		sparse.append(aim)
	if sparse.size() < 2:
		_clear_route()
		return
	var path := PipeRoute.lay(sparse)
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
	var spec: Dictionary = StructureFactory.RUNS[_current_type()]
	var base_color: Color = spec["color"] if ok else Color(0.9, 0.2, 0.15)
	_route_mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.6)
	if path != _last_route:
		_last_route = path
		_rebuild_route(path, spec["radius"], spec["style"])


## Real translucent geometry as the preview — the same segments and
## fittings the committed run will have.
func _rebuild_route(path: Array[Vector3], radius: float, style: String) -> void:
	for old in _route_node.get_children():
		old.queue_free()
	for i in range(path.size() - 1):
		if path[i].distance_to(path[i + 1]) < 0.005:
			continue
		_route_node.add_child(PipeView.segment_node(path[i], path[i + 1], radius, style, _route_mat))
		if i > 0:
			var joint := PipeView.joint_node(path[i], radius, style, _route_mat)
			if joint != null:
				_route_node.add_child(joint)


func _clear_route() -> void:
	if _route_node == null:
		return
	for old in _route_node.get_children():
		old.queue_free()
	_last_route = []


## Where a clicked waypoint would land: the aimed surface, pushed out
## along its normal, grid-snapped. INF when aiming at nothing.
func _aim_point() -> Vector3:
	var collider := player.aimed_collider()
	if collider == null:
		return Vector3.INF
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


func _is_stretch() -> bool:
	return StructureFactory.STRETCH.has(_current_type())


func _is_run() -> bool:
	return StructureFactory.RUNS.has(_current_type())


## The world point the placement ray lands on, or empty. Aiming at a
## column magnetizes to its top center — the natural beam seat.
func _place_hit() -> Dictionary:
	var camera := player.camera
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * (REACH + player.zoom_offset()), 1)
	query.exclude = [player.get_rid()]
	return space.intersect_ray(query)


func _update_ghost() -> void:
	if _is_stretch() or _is_run():
		if _ghost != null:
			_ghost.visible = false
		(_guide_mesh.mesh as ImmediateMesh).clear_surfaces()
		if _is_stretch():
			_update_stretch_ghost()
		else:
			_beam_ghost.visible = false
			_update_run_preview()
		return
	_beam_ghost.visible = false
	_clear_route()
	if _current_type() == "":
		_clear_ghost()
		_ghost_valid = false
		return
	_refresh_ghost_asset()
	if _ghost == null:
		return
	if _is_mountable():
		_update_mount_ghost()
		return
	var space := player.camera.get_world_3d().direct_space_state
	var hit := _place_hit()
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		_ghost.visible = false
		_ghost_valid = false
		(_guide_mesh.mesh as ImmediateMesh).clear_surfaces()
		return
	var type_id := _current_type()
	var footprint := _current_footprint()
	var point := hit["position"] as Vector3
	_ghost_pos = Vector3(snappedf(point.x, GRID), point.y, snappedf(point.z, GRID))
	_ghost_pos = _apply_alignment(_ghost_pos)
	_ghost.global_position = _ghost_pos + Vector3(0, AssetPreview.base_offset(type_id), 0)
	_ghost.rotation.y = rot_y
	_ghost.visible = true

	_ghost_valid = _footprint_clear(footprint, _ghost_pos, rot_y, null)
	if _ghost_valid and not _is_equipment_page():
		_ghost_valid = StructureFactory.placement_ok(type_id, _ghost_pos, rot_y, space) == ""
	_ghost_mat.albedo_color = Color(0.25, 0.85, 0.35, 0.45) if _ghost_valid \
		else Color(0.9, 0.25, 0.2, 0.45)


## A level instrument goes on a vessel: the ghost sticks to the shell
## under the crosshair, at that height and bearing, facing out.
func _update_mount_ghost() -> void:
	(_guide_mesh.mesh as ImmediateMesh).clear_surfaces()
	var host := player.look_view() as TankView
	if host == null or not player.ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		_mount_host = ""
		return
	var local := host.to_local(player.ray.get_collision_point())
	_mount_angle = atan2(local.z, local.x)
	_mount_frac = clampf(local.y / host.tank.height_m, 0.06, 0.94)
	_mount_host = host.tank.comp_name
	var dir := Vector3(cos(_mount_angle), 0, sin(_mount_angle))
	_ghost.global_position = host.to_global(dir * (host.tank.diameter_m / 2.0)
		+ Vector3(0, host.tank.height_m * _mount_frac, 0))
	_ghost.global_basis = host.global_basis * Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	_ghost.visible = true
	_ghost_valid = true
	_ghost_mat.albedo_color = Color(0.25, 0.85, 0.35, 0.45)


func _is_mountable() -> bool:
	return _is_equipment_page() and PlantFactory.MOUNTABLE.has(_current_type())


## Pull the ghost onto a neighbor's x or z axis when close, and draw
## cyan guide lines to whatever it aligned with.
func _apply_alignment(pos: Vector3) -> Vector3:
	_align_targets.clear()
	var best_x := ALIGN_SNAP
	var best_z := ALIGN_SNAP
	var x_target := Vector3.INF
	var z_target := Vector3.INF
	for cand in _alignment_candidates():
		var planar := Vector2(cand.x - pos.x, cand.z - pos.z).length()
		if planar < 0.6 or planar > ALIGN_RANGE:
			continue
		if absf(cand.x - pos.x) < best_x:
			best_x = absf(cand.x - pos.x)
			x_target = cand
		if absf(cand.z - pos.z) < best_z:
			best_z = absf(cand.z - pos.z)
			z_target = cand
	if x_target != Vector3.INF:
		pos.x = x_target.x
		_align_targets.append(x_target)
	if z_target != Vector3.INF:
		pos.z = z_target.z
		_align_targets.append(z_target)
	_draw_guides(pos)
	return pos


func _alignment_candidates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for name_: String in plant.views:
		if plant.equip_types.get(name_) == "air_cascade":
			continue
		out.append((plant.views[name_] as Node3D).global_position)
	for entry_name: String in plant.structures:
		out.append(((plant.structures[entry_name] as Dictionary)["node"] as Node3D).global_position)
	return out


func _draw_guides(pos: Vector3) -> void:
	var im := _guide_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if _align_targets.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for target in _align_targets:
		im.surface_add_vertex(pos + Vector3(0, 0.06, 0))
		im.surface_add_vertex(Vector3(target.x, pos.y + 0.06, target.z))
	im.surface_end()


## Stretch flow (beams, railings): first click anchors a supported
## start, the ghost then spans level from the anchor to the aim.
func _update_stretch_ghost() -> void:
	var spec: Dictionary = StructureFactory.STRETCH[_current_type()]
	var size_y := float(spec["size_y"])
	var space := player.camera.get_world_3d().direct_space_state
	var aim := _beam_aim(space)
	if aim == Vector3.INF:
		_beam_ghost.visible = false
		_ghost_valid = false
		return
	var mesh := _beam_ghost.mesh as BoxMesh
	if _beam_anchor == Vector3.INF:
		mesh.size = Vector3(0.6, size_y, float(spec["size_z"]))
		_beam_ghost.global_position = aim + Vector3(0, size_y / 2.0 + 0.02, 0)
		_beam_ghost.rotation.y = 0.0
		_ghost_valid = StructureFactory.bears_point(aim, space)
	else:
		_beam_end = Vector3(aim.x, _beam_anchor.y, aim.z)
		_beam_len = _beam_anchor.distance_to(_beam_end)
		var direction := _beam_end - _beam_anchor
		var yaw := atan2(-direction.z, direction.x) if direction.length() > 0.01 else 0.0
		mesh.size = Vector3(maxf(_beam_len, 0.3), size_y, float(spec["size_z"]))
		var mid := (_beam_anchor + _beam_end) / 2.0
		_beam_ghost.global_position = mid + Vector3(0, size_y / 2.0 + 0.02, 0)
		_beam_ghost.rotation.y = yaw
		_ghost_valid = _beam_len >= float(spec["min"]) and _beam_len <= float(spec["max"]) \
			and StructureFactory.placement_ok(_current_type(), mid, yaw, space, _beam_len) == ""
	_beam_ghost.visible = true
	_ghost_mat.albedo_color = Color(0.25, 0.85, 0.35, 0.45) if _ghost_valid \
		else Color(0.9, 0.25, 0.2, 0.45)


## Where a beam endpoint would land: column tops magnetize to their
## center; other upward surfaces snap to the fine grid.
func _beam_aim(_space: PhysicsDirectSpaceState3D) -> Vector3:
	var hit := _place_hit()
	if hit.is_empty():
		return Vector3.INF
	var collider := hit["collider"] as Node
	if collider is StructureView and (collider as StructureView).type_id == "s_column":
		var column := collider as StructureView
		var size: Vector3 = StructureFactory.SIZES["s_column"]
		return column.global_position + Vector3(0, size.y / 2.0, 0)
	if (hit["normal"] as Vector3).y < 0.6:
		return Vector3.INF
	var point := hit["position"] as Vector3
	return Vector3(snappedf(point.x, 0.25), point.y, snappedf(point.z, 0.25))


## The page's entries, less whatever the campaign has not unlocked.
func _catalog() -> Array[Dictionary]:
	var entries := _page_catalog()
	if plant.campaign == null:
		return entries
	var open: Array[Dictionary] = []
	for entry in entries:
		if plant.is_unlocked(str(entry["type"])):
			open.append(entry)
	return open


## A milestone just unlocked something: redraw the page if it is up.
func refresh_menu() -> void:
	if mode == Mode.PLACE:
		_update_hud()


func _page_catalog() -> Array[Dictionary]:
	match page:
		0: return PlantFactory.CATALOG
		1: return PlantFactory.CATALOG_SEPARATION
		2: return PlantFactory.CATALOG_INSTRUMENTS
		3: return StructureFactory.CATALOG
		4: return StructureFactory.CATALOG_ROUTING
		6: return PlantFactory.CATALOG_UTILITIES
	return PlantFactory.CATALOG_CONTROL


## Pages 0, 1, 2, 5, and 6 place sim equipment; 3 and 4 place structure.
func _is_equipment_page() -> bool:
	return page in [0, 1, 2, 5, 6]


func _current_type() -> String:
	var entries := _catalog()
	if catalog_index >= entries.size():
		return ""  # a page with nothing unlocked on it
	return entries[catalog_index]["type"]


func _current_footprint() -> Vector3:
	return PlantFactory.FOOTPRINTS[_current_type()] if _is_equipment_page() \
		else StructureFactory.SIZES[_current_type()]


## ---- actions -------------------------------------------------------------

func _try_place() -> void:
	if _is_stretch():
		_try_place_stretch()
		return
	if _is_run():
		var aim := _aim_point()
		if aim == Vector3.INF:
			hud.toast("aim at a surface")
			return
		_run_points.append(aim)
		_update_hud()
		return
	if _is_mountable():
		if not _ghost_valid or _mount_host == "":
			hud.toast("aim at a tank shell — level instruments mount on the vessel")
			return
		var inst := plant.mount_new(_current_type(), _mount_host, _mount_frac, _mount_angle)
		if inst != null:
			hud.toast("mounted %s on %s" % [inst.comp_name, _mount_host])
		return
	if _ghost == null or not _ghost.visible or not _ghost_valid:
		var reason := "can't place here"
		if not _is_equipment_page() and _ghost != null and _ghost.visible:
			var bearing := StructureFactory.placement_ok(_current_type(), _ghost_pos, rot_y,
				player.camera.get_world_3d().direct_space_state)
			if bearing != "":
				reason = bearing
		hud.toast(reason)
		return
	if not _is_equipment_page():
		var name_ := plant.unique_struct_name(_current_type())
		if plant.place_structure(_current_type(), name_, _ghost_pos, rot_y):
			hud.toast("placed %s" % name_)
		return
	if _current_type() == "cabinet":
		var cab_name := plant.unique_cabinet_name()
		if plant.place_cabinet(cab_name, _ghost_pos, rot_y):
			hud.toast("placed %s — open it and press EDIT to build the panel" % cab_name)
		return
	if _current_type() == "junction_box":
		var jb_name := plant.unique_jb_name()
		if plant.place_junction_box(jb_name, _ghost_pos, rot_y):
			hud.toast("placed %s — land field circuits on its left flank" % jb_name)
		return
	if _current_type() == "control_station":
		var lcs_name := plant.unique_station_name()
		if plant.place_control_station(lcs_name, _ghost_pos, rot_y, Plant.default_station_devices()):
			hud.toast("placed %s — START, STOP, RUNNING, STOPPED; wire its right flank" % lcs_name)
		return
	var record := plant.place_new(_current_type(), _ghost_pos, rot_y)
	if record != null:
		hud.toast("placed %s" % record.comp_name)


func _try_place_stretch() -> void:
	var type_id := _current_type()
	var spec: Dictionary = StructureFactory.STRETCH[type_id]
	var space := player.camera.get_world_3d().direct_space_state
	var aim := _beam_aim(space)
	if aim == Vector3.INF:
		hud.toast("aim at a surface")
		return
	if _beam_anchor == Vector3.INF:
		if not StructureFactory.bears_point(aim, space):
			hud.toast("start point needs support below")
			return
		_beam_anchor = aim
		_update_hud()
		return
	if not _ghost_valid:
		hud.toast("span %.1f m — needs support at both ends, max %.0f m"
			% [_beam_len, float(spec["max"])])
		return
	var mid := (_beam_anchor + _beam_end) / 2.0
	var direction := _beam_end - _beam_anchor
	var yaw := atan2(-direction.z, direction.x)
	var name_ := plant.unique_struct_name(type_id)
	if plant.place_structure(type_id, name_, mid, yaw, _beam_len):
		hud.toast("placed %s — %.1f m" % [name_, _beam_len])
	_beam_anchor = Vector3.INF
	_update_hud()


func _finish_run() -> void:
	if _run_points.size() < 2:
		hud.toast("lay at least two points, then E to finish")
		return
	var path := PipeRoute.lay(_run_points)
	var check := SupportCheck.evaluate(path,
		player.camera.get_world_3d().direct_space_state)
	if not bool(check["ok"]):
		hud.toast("unsupported span %.1f m (max %.1f) — route along structure"
			% [float(check["max_span"]), SupportCheck.MAX_SPAN])
		return
	var local_points: Array = []
	for point in _run_points:
		local_points.append(plant.to_local(point))
	var name_ := plant.unique_run_name(_current_type())
	if plant.place_run(_current_type(), name_, local_points):
		hud.toast("placed %s" % name_)
	_run_points.clear()
	_clear_route()
	_update_hud()


func _try_pick_port() -> void:
	var node := player.aimed_collider()
	if node == null:
		return
	if not node.has_meta("port_name"):
		# A surface click while routing lays a waypoint.
		if _pending_marker != null:
			var aim := _aim_point()
			if aim != Vector3.INF:
				_waypoints.append(aim)
				_update_hud()
		return
	var marker := node as StaticBody3D
	if _pending_marker == null:
		if bool(marker.get_meta("is_input")):
			hud.toast("start from an outlet or output fitting")
			return
		_pending_marker = marker
		_update_hud()
		return
	if not bool(marker.get_meta("is_input")):
		hud.toast("finish on an inlet or input fitting")
		return
	_complete_connection(str(marker.get_meta("record_name")),
		str(marker.get_meta("port_name")), marker.global_position,
		marker.global_basis.x.normalized())


## Land the pending routed connection on an input port. The support
## rule gets its veto before the kernel does; routing state is kept on
## refusal so the run can be fixed with more waypoints.
func _complete_connection(dst_name: String, dst_port: String, dst_pos: Vector3,
		dst_dir: Vector3 = Vector3.ZERO) -> void:
	var check := SupportCheck.evaluate(PipeRoute.routed(
			_pending_marker.global_position, _pending_marker.global_basis.x.normalized(),
			dst_pos, dst_dir, _waypoints),
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
		dst_name, dst_port, local_points)
	hud.toast("connected" if error == "" else error)
	_pending_marker = null
	_waypoints.clear()
	_clear_route()
	_update_hud()


## ---- right-click port picker ---------------------------------------------

func _open_port_menu() -> void:
	var view := player.look_view()
	if view == null:
		return
	var records: Array = []
	var title := ""
	var type_id := ""
	if view is CabinetView:
		var cab := (view as CabinetView).cabinet_name
		title = "%s — field terminations" % cab
		type_id = "cabinet"
		for record_name in plant.cabinet_field_records(cab):
			records.append(record_name)
		if records.is_empty():
			hud.toast("cabinet is empty — open it and press EDIT to mount terminal strips")
			return
	elif view.has_meta("record_name"):
		var record_name := str(view.get_meta("record_name"))
		type_id = str(plant.equip_types.get(record_name, ""))
		title = "%s — %s" % [record_name, type_id if type_id != "" else "device"]
		records.append(record_name)
	else:
		hud.toast("no ports here")
		return
	port_menu.open(plant, title, records, type_id, _port_picked,
		func(record_name: String, values: Dictionary) -> String:
			var why := plant.configure_equipment(record_name, values)
			if why == "":
				hud.toast("%s configured" % record_name)
			return why)


func _port_picked(record_name: String, port_name: String, is_input: bool) -> void:
	var view: Node3D = plant.views.get(record_name)
	if view == null:
		return
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: StaticBody3D = markers.get("%s:%s" % [record_name, port_name])
	if marker == null:
		hud.toast("that port has no field connection point")
		return
	if is_input:
		if _pending_marker == null:
			hud.toast("right-click a SOURCE and pick an output first")
			return
		_complete_connection(record_name, port_name, marker.global_position,
			marker.global_basis.x.normalized())
		return
	if mode != Mode.CONNECT:
		_set_mode(Mode.CONNECT)
	_pending_marker = marker
	_update_hud()
	hud.toast("routing from %s.%s — lay waypoints, finish on an input (click or right-click the target)"
		% [record_name, port_name])


## Headless smoke: the device menu's CONFIGURE path, which no script
## can click. Place a tank, open its menu, change a field, apply, and
## read the record back.
func exercise_device_menu() -> void:
	var record := plant.place_new("tank", plant.to_global(Vector3(12.0, 0.0, 4.0)), 0.0) as SimTank
	if record == null:
		print("[flowstate] device menu exercise FAILED — could not place a tank")
		return
	port_menu.open(plant, "%s — tank" % record.comp_name, [record.comp_name], "tank",
		_port_picked, func(name_: String, values: Dictionary) -> String:
			return plant.configure_equipment(name_, values))
	var fields := port_menu._fields.size()
	var io_rows := port_menu._io_list.get_child_count()
	(port_menu._fields["height_m"] as SpinBox).value = 2.5
	port_menu._apply()
	var ok := absf(record.height_m - 2.5) < 1e-6 and not port_menu.visible \
		and fields == 3 and io_rows == 2
	print("[flowstate] device menu exercise %s — %d I/O rows, %d fields, height %.2f m after apply"
		% ["OK" if ok else "FAILED", io_rows, fields, record.height_m])
	# Edit mode: a tank grows five handles, and the drag maths snap to
	# the grid and the size step.
	var gizmo := EditGizmo.new()
	add_child(gizmo)
	gizmo.setup(plant.views[record.comp_name] as Node3D, record)
	var handles := 0
	for body in gizmo.find_children("*", "StaticBody3D", true, false):
		if body.has_meta("handle"):
			handles += 1
	var base := Vector3(4.0, 0.0, 4.0)
	var d := EditGizmo.diameter_from(base, base + Vector3(0.8, 1.0, 0.0))
	var h := EditGizmo.height_from(base, base + Vector3(0.0, 2.44, 0.0))
	var m := EditGizmo.move_target(base, Vector3(5.3, 0.0, 7.1), Vector3.ZERO, "move_x")
	var gizmo_ok := handles == 5 and absf(d - 1.6) < 1e-6 and absf(h - 2.4) < 1e-6 \
		and m.is_equal_approx(Vector3(5.5, 0.0, 4.0))
	gizmo.queue_free()
	plant.remove_equipment(record.comp_name)
	print("[flowstate] edit gizmo exercise %s — %d handles, ring 0.8 m out reads %.1f m, post at 2.44 reads %.1f m, X arrow lands at %s"
		% ["OK" if gizmo_ok else "FAILED", handles, d, h, str(m)])
	# The edit camera: takes over where the player's camera stands,
	# keeps its distance through an orbit, and the wheel brings it in.
	var cam := EditCamera.new()
	add_child(cam)
	var target := Vector3(12.0, 1.0, 4.0)
	cam.start_from(player.camera, target)
	var d0 := cam.global_position.distance_to(target)
	var start_ok := absf(d0 - clampf(player.camera.global_position.distance_to(target),
		EditCamera.MIN_DIST, EditCamera.MAX_DIST)) < 1e-3
	cam.orbit(Vector2(200.0, -50.0))
	var orbit_ok := absf(cam.global_position.distance_to(target) - d0) < 1e-3 \
		and (-cam.global_basis.z).dot((target - cam.global_position).normalized()) > 0.999
	cam.zoom(2.0)
	var zoom_ok := cam.global_position.distance_to(target) < d0
	cam.queue_free()
	print("[flowstate] edit camera exercise %s — starts %.2f m out, orbit holds distance, zoom brings it to %.2f m"
		% ["OK" if start_ok and orbit_ok and zoom_ok else "FAILED", d0,
		cam.global_position.distance_to(target)])


## Is a footprint free of world geometry (1) and interact volumes (4),
## which stand in for the space equipment occupies? moved is left out
## so equipment being edited does not block its own next spot.
func _footprint_clear(footprint: Vector3, pos: Vector3, rot: float, moved: Node3D) -> bool:
	var space := player.camera.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = footprint * 0.9
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = shape
	overlap.transform = Transform3D(Basis.from_euler(Vector3(0, rot, 0)),
		pos + Vector3(0, footprint.y / 2.0 + 0.06, 0))
	overlap.collision_mask = 1 | 4
	var excluded: Array[RID] = [player.get_rid()]
	if moved != null:
		for body in moved.find_children("*", "CollisionObject3D", true, false):
			excluded.append((body as CollisionObject3D).get_rid())
	overlap.exclude = excluded
	return space.intersect_shape(overlap, 1).is_empty()


## ---- edit mode (M) ---------------------------------------------------------
## The equipment stays where and as it is and grows handles. Aim at a
## handle, hold click, and look: the ring sets a tank's diameter, the
## post its height, the arrows move it along an axis, the cube freely.

func _toggle_edit() -> void:
	if mode == Mode.EDIT:
		_set_mode(Mode.NORMAL)
		return
	var view := player.look_view()
	if view == null or not view.has_meta("record_name"):
		hud.toast("aim at equipment to modify it")
		return
	var name_ := str(view.get_meta("record_name"))
	var why := plant.movable(name_)
	if why != "":
		hud.toast(why)
		return
	_set_mode(Mode.EDIT)
	_edit_name = name_
	_gizmo = EditGizmo.new()
	add_child(_gizmo)
	_gizmo.setup(plant.views[name_] as Node3D, plant.sim.get_component(name_) as SimTank,
		float(PlantFactory.Y_OFFSETS.get(plant.equip_types[name_], 0.0)))
	# The camera leaves the player: a CAD viewport orbiting the
	# equipment, the pointer free to drag its handles.
	_edit_cam = EditCamera.new()
	add_child(_edit_cam)
	_edit_cam.start_from(player.camera, _gizmo.base() + Vector3(0, _edit_footprint().y * 0.5, 0))
	_edit_cam.make_current()
	player.input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_hud()


func is_editing() -> bool:
	return mode == Mode.EDIT


func _end_edit() -> void:
	_edit_name = ""
	_drag = ""
	_orbiting = false
	_panning = false
	_right_down = false
	if _gizmo != null:
		_gizmo.queue_free()
		_gizmo = null
	if _edit_cam != null:
		player.camera.make_current()
		_edit_cam.queue_free()
		_edit_cam = null
		player.input_locked = false
		MouseMode.capture()


## The ray under the pointer, from the edit camera: [origin, direction].
func _edit_ray() -> Array[Vector3]:
	var mouse := get_viewport().get_mouse_position()
	return [_edit_cam.project_ray_origin(mouse), _edit_cam.project_ray_normal(mouse)]


## Mouse in edit mode: left drags a handle, middle pans (shift: orbits),
## right orbits, a right click that did not move opens the device
## menu, the wheel zooms. Returns true when the event was ours.
func _edit_mouse(event: InputEvent) -> bool:
	if _edit_cam == null:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_begin_drag()
				else:
					_drag = ""
					if _gizmo != null:
						_gizmo.set_blocked(false)
				return true
			MOUSE_BUTTON_MIDDLE:
				_orbiting = button.pressed and button.shift_pressed
				_panning = button.pressed and not button.shift_pressed
				return true
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_right_down = true
					_right_moved = false
				else:
					var was_click := _right_down and not _right_moved
					_right_down = false
					if was_click:
						_open_port_menu_at_pointer()
				return true
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_edit_cam.zoom(1.0)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_edit_cam.zoom(-1.0)
				return true
		return false
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting or _right_down:
			if motion.relative.length() > 0.5:
				_right_moved = true
			_edit_cam.orbit(motion.relative)
			return true
		if _panning:
			_edit_cam.pan(motion.relative)
			return true
	return false


## Right-click in edit mode: the device under the pointer, or the one
## being edited.
func _open_port_menu_at_pointer() -> void:
	var ray := _edit_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 200.0, 1 | 4)
	query.exclude = [player.get_rid()]
	var hit := player.camera.get_world_3d().direct_space_state.intersect_ray(query)
	var name_ := _edit_name
	if not hit.is_empty():
		var collider := hit["collider"] as Node
		if collider != null and collider.has_meta("view"):
			var view := collider.get_meta("view") as Node
			if view != null and view.has_meta("record_name"):
				name_ = str(view.get_meta("record_name"))
	var type_id := str(plant.equip_types.get(name_, ""))
	port_menu.open(plant, "%s — %s" % [name_, type_id], [name_], type_id, _port_picked,
		func(record_name: String, values: Dictionary) -> String:
			var why := plant.configure_equipment(record_name, values)
			if why == "":
				hud.toast("%s configured" % record_name)
				if _gizmo != null:
					_gizmo.refresh()
			return why)


func _edit_footprint() -> Vector3:
	var tank := plant.sim.get_component(_edit_name) as SimTank
	if tank != null:
		return Vector3(tank.diameter_m * 1.1, tank.height_m, tank.diameter_m * 1.1)
	return PlantFactory.FOOTPRINTS[plant.equip_types[_edit_name]]


## Where the crosshair ray meets the plane the dragged handle lives on:
## the ring's horizontal plane, a vertical plane through the axis
## facing the camera for the post, the ground for the arrows.
func _drag_hit(base: Vector3) -> Vector3:
	var ray := _edit_ray()
	var origin := ray[0]
	var dir := ray[1]
	var plane: Plane
	match _drag:
		"ring":
			var tank := plant.sim.get_component(_edit_name) as SimTank
			var ring_y := tank.height_m * 0.5 if tank != null else 0.0
			plane = Plane(Vector3.UP, base + Vector3(0, ring_y, 0))
		"post":
			var toward := origin - base
			toward.y = 0.0
			plane = Plane(toward.normalized(), base)
		_:
			plane = Plane(Vector3.UP, base)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector3.INF
	return hit as Vector3


func _begin_drag() -> void:
	if _gizmo == null:
		return
	var ray := _edit_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 200.0,
		EditGizmo.LAYER)
	var pick := player.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if pick.is_empty():
		return
	var collider := pick["collider"] as Node
	if collider == null or not collider.has_meta("handle"):
		return
	_drag = str(collider.get_meta("handle"))
	var base := _gizmo.base()
	var hit := _drag_hit(base)
	if hit == Vector3.INF:
		_drag = ""
		return
	var tank := plant.sim.get_component(_edit_name) as SimTank
	match _drag:
		"ring":
			_drag_offset_f = tank.diameter_m - EditGizmo.raw_diameter(base, hit)
		"post":
			_drag_offset_f = tank.height_m - EditGizmo.raw_height(base, hit)
		_:
			_drag_offset_v = base - hit


func _update_drag() -> void:
	var view := plant.views.get(_edit_name) as Node3D
	if view == null or _gizmo == null:
		_drag = ""
		return
	var base := _gizmo.base()
	var hit := _drag_hit(base)
	if hit == Vector3.INF:
		return
	var tank := plant.sim.get_component(_edit_name) as SimTank
	match _drag:
		"ring":
			var d := EditGizmo.diameter_from(base, hit, _drag_offset_f)
			if tank != null and not is_equal_approx(d, tank.diameter_m):
				plant.resize_tank(_edit_name, tank.height_m, d)
				_gizmo.refresh()
		"post":
			var h := EditGizmo.height_from(base, hit, _drag_offset_f)
			if tank != null and not is_equal_approx(h, tank.height_m):
				plant.resize_tank(_edit_name, h, tank.diameter_m)
				_gizmo.refresh()
		_:
			var target := EditGizmo.move_target(base, hit, _drag_offset_v, _drag)
			if target.is_equal_approx(base):
				return
			if _footprint_clear(_edit_footprint(), target, view.rotation.y, view):
				plant.move_equipment(_edit_name, target, view.rotation.y)
				_gizmo.refresh()
				_gizmo.set_blocked(false)
			else:
				_gizmo.set_blocked(true)


func _rotate_edited() -> void:
	var view := plant.views.get(_edit_name) as Node3D
	if view == null or _gizmo == null:
		return
	var rot := wrapf(view.rotation.y + PI / 2.0, 0.0, TAU)
	if _footprint_clear(_edit_footprint(), _gizmo.base(), rot, view):
		plant.move_equipment(_edit_name, _gizmo.base(), rot)
		_gizmo.refresh()
	else:
		hud.toast("no room to turn it")


func _try_delete() -> void:
	var view := player.look_view()
	if view == null:
		hud.toast("aim at equipment, structure or a run to remove it")
		return
	if view is PipeView:
		var pipe := view as PipeView
		var gone := plant.remove_run(pipe) or plant.remove_placed_run(pipe)
		hud.toast("removed run" if gone else "can't remove that run")
		return
	if view is CabinetView:
		var cab_name := (view as CabinetView).cabinet_name
		if plant.remove_cabinet(cab_name):
			hud.toast("removed %s and its internal wiring" % cab_name)
		return
	if view is JunctionBoxView:
		var jb_name := (view as JunctionBoxView).jb_name
		if plant.remove_junction_box(jb_name):
			hud.toast("removed %s, its circuits and any multicore it fed" % jb_name)
		return
	if view is ControlStationView:
		var lcs_name := (view as ControlStationView).station_name
		if plant.remove_control_station(lcs_name):
			hud.toast("removed %s and its circuits" % lcs_name)
		return
	if view.has_meta("structure_name"):
		var struct_name := str(view.get_meta("structure_name"))
		if plant.remove_structure(struct_name):
			hud.toast("removed %s — runs it carried re-check" % struct_name)
		return
	if not view.has_meta("record_name"):
		hud.toast("nothing removable there")
		return
	var name_ := str(view.get_meta("record_name"))
	if plant.remove_equipment(name_):
		hud.toast("removed %s" % name_)
	else:
		hud.toast("%s is commissioned equipment — can't remove" % name_)
