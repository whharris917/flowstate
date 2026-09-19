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
var _route_block := ""   # what the previewed route would pass through, or ""
var _preview_target: StaticBody3D = null   # the fitting the preview was laid to
var _preview_waypoints := -1
var _preview_path: Array[Vector3] = []
var _nozzle_grab: Dictionary = {}   # {view, port, was: {frac, angle}}
# Edit mode: the equipment under the handles, and the handle being dragged.
var _edit_name := ""
var _gizmo: EditGizmo = null
# Or one leg of a line (director, 2026-09-13: per-leg selection).
var _edit_run: PipeView = null
var _edit_leg := -1
var _leg_gizmo: LegGizmo = null
var _leg_relay_ms := 0
var _drag := ""
var _drag_offset_f := 0.0          # size the grab started at, less the raw hit
var _drag_offset_v := Vector3.ZERO  # base less the grab point, so it stays under the pointer
var _right_down := false
var _right_moved := false
var _right_wheeled := false
var _right_grab := false   # the right button is carrying a nozzle
var _grab_preview_ms := 0  # when the carried nozzle's lines were last re-laid


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
	if OS.has_environment("FLOWSTATE_INPUT_DEBUG") and event is InputEventMouseButton:
		print("[input] mode %d button %d pressed %s aimed %s" % [mode, (event as InputEventMouseButton).button_index,
			str((event as InputEventMouseButton).pressed), str(player.aimed_collider())])
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
	elif mode != Mode.EDIT and _mode_mouse(event):
		get_viewport().set_input_as_handled()
	elif mode == Mode.EDIT and _edit_mouse(event):
		get_viewport().set_input_as_handled()
	elif mode == Mode.EDIT and event.is_action_pressed("rotate_item"):
		_rotate_edited()
	elif mode == Mode.CONNECT and not _nozzle_grab.is_empty() \
			and event.is_action_pressed("place"):
		_commit_nozzle_grab()
	elif mode == Mode.NORMAL and event.is_action_pressed("place") and _click_fitting():
		pass  # a click on a fitting starts a line from it (director, 2026-09-13)
	elif event.is_action_pressed("delete_item"):
		_try_delete()
	elif mode == Mode.PLACE and event.is_action_pressed("place"):
		_try_place()
	elif mode == Mode.CONNECT and event.is_action_pressed("place"):
		_try_pick_port()
	elif mode == Mode.NORMAL and event.is_action_pressed("place"):
		# Clicking a clickable affordance (the cabinet's EDIT button),
		# else a click on equipment selects it (director, 2026-09-13).
		var clicked := player.look_view()
		if clicked != null and clicked.has_method("use") \
				and player.ray.is_colliding() \
				and (player.ray.get_collider() as Node).has_meta("clickable"):
			clicked.call("use")
		elif (event as InputEventMouseButton).double_click:
			# A double click opens properties: of movable equipment (its
			# first press deselected it; the second selects it again), or
			# of anything else with ports, a cabinet's field terminations.
			_click_select()
			_open_port_menu()
		else:
			_click_select()
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
	_route_block = ""
	_update_hud()


func _update_hud() -> void:
	match mode:
		Mode.NORMAL:
			menu.visible = false
			hud.set_mode_text("B build · C connect · X remove · click: select (a fitting starts a line) · double-click: properties · right-hold: move (a line: pull to cut) · right-click: cancel")
		Mode.EDIT when _edit_run != null:
			menu.visible = false
			hud.set_mode_text("SELECTED %s, leg %d — aim at a gold corner and hold click to move it · right-hold and pull across it cuts · double-click: colour/label · click again or right-click done"
				% [_edit_run.describe().get_slice("\n", 0), _edit_leg])
		Mode.EDIT:
			menu.visible = false
			var handles := "arrows move it (red X, blue Z, gold cube free)"
			if plant.sim.get_component(_edit_name) is SimTank:
				handles = "ring = diameter · post = height · " + handles
			hud.set_mode_text("SELECTED %s — aim at a handle and hold click: %s · right-hold moves · right+wheel turns · double-click properties · click again or right-click done"
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
				hud.set_mode_text("STRETCH — %s · right-click/B/Esc exit" % step)
			elif _is_run():
				var support := "" if _run_points.size() < 2 else \
					("\nsupport OK (span %.1f m)" % _route_span if _route_ok
					else "\nUNSUPPORTED — span %.1f m over %.1f m max" \
					% [_route_span, SupportCheck.MAX_SPAN])
				hud.set_mode_text("RUN — click surfaces to lay points (%d) · E finish · R undo · right-click/B/Esc exit%s"
					% [_run_points.size(), support])
			else:
				hud.set_mode_text("BUILD — click place · R or right-hold+wheel rotate · right-click/B/Esc exit")
		Mode.CONNECT:
			menu.visible = false
			var step := "click a fitting at either end · right-hold or G moves a vessel nozzle" if _pending_marker == null \
				else "lay the run: click surfaces for waypoints (%d), finish on an %s fitting · R undo point" \
				% [_waypoints.size(), "outlet" if bool(_pending_marker.get_meta("is_input")) else "inlet"]
			var support := "" if _pending_marker == null else \
				("\nsupport OK (span %.1f m)" % _route_span if _route_ok
				else "\nUNSUPPORTED — span %.1f m over %.1f m max: route along structure" \
				% [_route_span, SupportCheck.MAX_SPAN])
			if _pending_marker != null and _route_block != "":
				support += "\nBLOCKED — the line would pass through %s: route round it or move it" % _route_block
			hud.set_mode_text("CONNECT — %s · right-click/C/Esc exit%s" % [step, support])


func _physics_process(_delta: float) -> void:
	if not _nozzle_grab.is_empty():
		plant._finish_scans()  # a grab moves a nozzle's elevation in the sim
		_update_nozzle_grab()
		return
	if _carry_name != "":
		plant._finish_scans()  # a move re-lays runs, which read the kernel's flows
		_update_carry()
	if not _cut.is_empty():
		plant._finish_scans()
		_update_cut()
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

func _toggle_nozzle_grab(by_button: bool = false) -> void:
	if not _nozzle_grab.is_empty():
		# Cancel: restore the original spot.
		var view := _nozzle_grab["view"] as TankView
		var was: Dictionary = _nozzle_grab["was"]
		view.set_nozzle(str(_nozzle_grab["port"]), float(was["frac"]), float(was["angle"]))
		_nozzle_grab = {}
		plant.refresh_wires_of(view.tank.comp_name)  # the lines followed the preview
		plant.end_gesture()
		hud.toast("nozzle move cancelled")
		return
	var collider := player.aimed_collider()
	if collider == null or not collider.has_meta("movable"):
		hud.toast("aim at a vessel nozzle to move it")
		return
	var view := collider.get_meta("owner_view") as TankView
	var port := str(collider.get_meta("port_name"))
	plant.begin_gesture()
	_nozzle_grab = {"view": view, "port": port,
		"was": (view.nozzles[port] as Dictionary).duplicate()}
	hud.toast(("moving %s — aim on the shell, release to weld" if by_button
		else "moving %s — aim on the shell, click to weld, G cancels") % port)


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
	var spot: Dictionary = view.nozzles[str(_nozzle_grab["port"])]
	if is_equal_approx(float(spot["frac"]), frac) and is_equal_approx(float(spot["angle"]), angle):
		return
	view.set_nozzle(str(_nozzle_grab["port"]), frac, angle)
	# The lines on it follow as it moves (director, 2026-09-13): re-laid
	# a few times a second while it is carried, the plant-wide sweep
	# waiting for the weld.
	var now := Time.get_ticks_msec()
	if now - _grab_preview_ms >= 150:
		_grab_preview_ms = now
		plant.preview_wires_of(view.tank.comp_name)


func _commit_nozzle_grab() -> void:
	var view := _nozzle_grab["view"] as TankView
	var record_name := view.tank.comp_name
	var port := str(_nozzle_grab["port"])
	_nozzle_grab = {}
	plant.refresh_wires_of(record_name)
	hud.toast("welded %s in place" % port)


## ---- route preview -------------------------------------------------------

func _update_route_preview() -> void:
	var path: Array[Vector3] = []
	# Aimed at a fitting that could finish the line: the preview is the
	# route the lay would take — corners, lane, bridges, ending at the
	# nozzle's stub — asked of the plant once per target and waypoint
	# count, since the lane search is not cheap (director, 2026-09-18).
	var aimed := player.aimed_collider()
	var target: StaticBody3D = null
	if aimed != null and aimed.has_meta("port_name") and aimed != _pending_marker \
			and bool(aimed.get_meta("is_input")) != bool(_pending_marker.get_meta("is_input")):
		target = aimed as StaticBody3D
	if target != null:
		if target != _preview_target or _preview_waypoints != _waypoints.size():
			_preview_target = target
			_preview_waypoints = _waypoints.size()
			var src := _pending_marker
			var dst := target
			var waypoints: Array[Vector3] = _waypoints.duplicate()
			if bool(_pending_marker.get_meta("is_input")):
				src = target
				dst = _pending_marker
				waypoints.reverse()
			_preview_path = plant.preview_route(str(src.get_meta("record_name")), str(src.get_meta("port_name")),
				str(dst.get_meta("record_name")), str(dst.get_meta("port_name")), waypoints)
		path = _preview_path
	else:
		_preview_target = null
		var aim := _aim_point()
		var tail: Array = []
		tail.append_array(_waypoints)
		if aim != Vector3.INF:
			tail.append(aim)
		if tail.is_empty():
			_clear_route()
			return
		path = PipeRoute.routed_open(Plant.marker_face(_pending_marker),
			_pending_marker.global_basis.x.normalized(), tail)
	if path.size() < 2:
		_clear_route()
		return
	var check := SupportCheck.evaluate(path,
		player.camera.get_world_3d().direct_space_state)
	var ok := bool(check["ok"])
	var span := float(check["max_span"])
	var kind: SimTypes.PortKind = _pending_marker.get_meta("kind")
	# And clear of everything solid: what it would pass through is named
	# in the hint and turns the preview red, since the lay will refuse it.
	var is_process_kind := kind == SimTypes.PortKind.PROCESS_MATERIAL or kind == SimTypes.PortKind.PROCESS_LEVEL
	var through := plant.route_obstacles(path, str(_pending_marker.get_meta("record_name")),
		str(target.get_meta("record_name")) if target != null else "", 0.07 if is_process_kind else 0.025)
	var block := ", ".join(through)
	if ok != _route_ok or absf(span - _route_span) > 0.05 or block != _route_block:
		_route_ok = ok
		_route_span = span
		_route_block = block
		_update_hud()
	var base_color: Color = PlantFactory.KIND_COLORS[kind] if ok and block == "" else Color(0.9, 0.2, 0.15)
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
	_preview_target = null
	_preview_path = []
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
	_pick_marker(node as StaticBody3D)


## A fitting picked in connect mode: the first of either kind starts
## the line, one of the other kind finishes it (director, 2026-09-13:
## inlet to outlet or outlet to inlet, not outlet first).
func _pick_marker(marker: StaticBody3D) -> void:
	if _pending_marker == null:
		_pending_marker = marker
		_update_hud()
		return
	if marker == _pending_marker:
		return
	if bool(marker.get_meta("is_input")) == bool(_pending_marker.get_meta("is_input")):
		hud.toast("finish on an %s fitting" % ("outlet or output"
			if bool(_pending_marker.get_meta("is_input")) else "inlet or input"))
		return
	_complete_connection(marker)


## A click in normal play on a fitting: into connect mode with the
## line started there. False when the crosshair is on no fitting.
func _click_fitting() -> bool:
	var aimed := player.aimed_collider()
	if aimed == null or not aimed.has_meta("port_name"):
		return false
	_set_mode(Mode.CONNECT)
	_pick_marker(aimed as StaticBody3D)
	return true


## Land the pending routed connection on an input port. The support
## rule gets its veto before the kernel does; routing state is kept on
## refusal so the run can be fixed with more waypoints.
func _complete_connection(other: StaticBody3D) -> void:
	# The line may have been started at either end: the kernel wire runs
	# output to input, so the waypoints are read in that order.
	var src := _pending_marker
	var dst := other
	var waypoints: Array[Vector3] = _waypoints.duplicate()
	if bool(_pending_marker.get_meta("is_input")):
		src = other
		dst = _pending_marker
		waypoints.reverse()
	var check := SupportCheck.evaluate(PipeRoute.routed(
			Plant.marker_face(src), src.global_basis.x.normalized(),
			Plant.marker_face(dst), dst.global_basis.x.normalized(), waypoints),
		player.camera.get_world_3d().direct_space_state)
	if not bool(check["ok"]):
		hud.toast("unsupported span %.1f m (max %.1f) — route along structure"
			% [float(check["max_span"]), SupportCheck.MAX_SPAN])
		return
	var local_points: Array = []
	for point in waypoints:
		local_points.append(plant.to_local(point))
	var error := plant.connect_equipment_checked(
		str(src.get_meta("record_name")), str(src.get_meta("port_name")),
		str(dst.get_meta("record_name")), str(dst.get_meta("port_name")), local_points)
	hud.toast("connected" if error == "" else error)
	if error != "":
		return  # the line is not made: keep routing, the player fixes it
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
	if mode != Mode.CONNECT:
		_set_mode(Mode.CONNECT)
	var started := _pending_marker == null
	_pick_marker(marker)
	if started:
		hud.toast("routing from %s.%s — lay waypoints, finish by clicking an %s fitting"
			% [record_name, port_name, "outlet" if is_input else "inlet"])


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
	_select(name_)


## A left click in normal play on movable equipment selects it
## (director, 2026-09-13). False when the crosshair is on none.
func _click_select() -> bool:
	var aimed := player.aimed_collider()
	if aimed != null and aimed.has_meta("run") and aimed.has_meta("leg"):
		var pipe := aimed.get_meta("run") as PipeView
		if pipe != null and int(aimed.get_meta("leg")) >= 0:
			return _select_leg(pipe, int(aimed.get_meta("leg")))
	var view := player.look_view()
	if view == null or not view.has_meta("record_name"):
		return false
	var name_ := str(view.get_meta("record_name"))
	if plant.movable(name_) != "":
		return false
	_select(name_)
	return true


## Select one straight of a line: the sleeve and a handle at each end
## that is a corner of the player's to move. Only a line between two
## fittings (a wire) is selectable; standalone runs are laid by hand.
func _select_leg(pipe: PipeView, leg: int) -> bool:
	var path := plant.wire_path(pipe)
	if path.size() < 2:
		return false
	_set_mode(Mode.EDIT)
	_edit_run = pipe
	_edit_leg = leg
	_leg_gizmo = LegGizmo.new()
	plant.add_child(_leg_gizmo)
	_leg_gizmo.setup(pipe, leg, path, plant.wire_corners(pipe))
	_update_hud()
	return true


## Select a piece of equipment: highlighted, with its handles, in
## first person like everything else (director, 2026-09-13: no
## detached view) — a handle is dragged by aiming at it, holding the
## button and looking. Selecting another moves the handles to it.
func _select(name_: String) -> void:
	_set_mode(Mode.EDIT)
	_edit_name = name_
	_gizmo = EditGizmo.new()
	add_child(_gizmo)
	_gizmo.highlight_size = _edit_footprint()
	_gizmo.setup(plant.views[name_] as Node3D, plant.sim.get_component(name_) as SimTank,
		float(PlantFactory.Y_OFFSETS.get(plant.equip_types[name_], 0.0)))
	_update_hud()


func is_editing() -> bool:
	return mode == Mode.EDIT


## Back to plain play with nothing held: what an undo or redo needs
## before the plant is rebuilt under a selection or a carry.
func reset_mode() -> void:
	if not _nozzle_grab.is_empty():
		_toggle_nozzle_grab()
	_carry_name = ""
	_cut = {}
	_cut_done = false
	_drag = ""
	_set_mode(Mode.NORMAL)


func _end_edit() -> void:
	_edit_name = ""
	_drag = ""
	_right_down = false
	_carry_name = ""
	_edit_run = null
	_edit_leg = -1
	if _gizmo != null:
		_gizmo.queue_free()
		_gizmo = null
	if _leg_gizmo != null:
		_leg_gizmo.queue_free()
		_leg_gizmo = null


## The crosshair's ray, from the player's camera: [origin, direction].
func _edit_ray() -> Array[Vector3]:
	return [player.camera.global_position, -player.camera.global_basis.z]


## Mouse in edit mode: left drags a handle, middle pans (shift: orbits),
## right orbits, a right click that did not move opens the device
## menu, the wheel zooms. Returns true when the event was ours.
## The right button in build and connect mode (director, 2026-09-13):
## a right click leaves the mode, and the wheel with the right button
## held turns the thing being placed, fifteen degrees a notch, instead
## of zooming the camera. A wheel turn under the button makes the
## release no longer a click.
func _mode_mouse(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var button := event as InputEventMouseButton
	match button.button_index:
		MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_right_down = true
				_right_wheeled = false
				_right_grab = false
				# Pressed on a vessel nozzle: carry it while the button is
				# held and weld it where it is released. Pressed on movable
				# equipment: carry that, and the wheel turns it meanwhile.
				var aimed := player.aimed_collider()
				if _nozzle_grab.is_empty() and aimed != null and aimed.has_meta("movable"):
					_toggle_nozzle_grab(true)
					_right_grab = not _nozzle_grab.is_empty()
				elif mode != Mode.PLACE and mode != Mode.CONNECT:
					_begin_carry()
					if _carry_name == "" and aimed != null and aimed.has_meta("run"):
						_begin_cut(aimed)
			else:
				var carried := _carry_name != "" and _carry_moved
				var was_click := _right_down and not _right_wheeled and not _right_grab and not carried \
					and not _cut_done
				_right_down = false
				_cut = {}
				_cut_done = false
				if _right_grab:
					_right_grab = false
					if not _nozzle_grab.is_empty():
						_commit_nozzle_grab()
				_end_carry()
				plant.end_gesture()   # a carry, a nozzle grab or a cut: one step
				if was_click:
					# A right click cancels: whatever mode or selection is
					# on, back to plain play (director, 2026-09-13).
					_set_mode(Mode.NORMAL)
			return true
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not _right_down or not button.pressed:
				return _right_down
			var notch := deg_to_rad(15.0) if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -deg_to_rad(15.0)
			if mode == Mode.PLACE and not _is_run() and not _is_stretch():
				_right_wheeled = true
				rot_y = wrapf(rot_y + notch, 0.0, TAU)
				_update_hud()
			elif _carry_name != "":
				_right_wheeled = true
				_turn_carried(notch)
			elif mode == Mode.EDIT:
				_right_wheeled = true
				_rotate_edited_by(notch)
			return true
	return false


## ---- cutting a line: the right button held on it, then a pull -------------

var _cut: Dictionary = {}      # {pipe, point, forward}: the pull is measured from the look at pick-up
var _cut_done := false
const CUT_PULL := deg_to_rad(9.0)   # the look has to swing this far sideways


func _begin_cut(collider: Node) -> void:
	var pipe := collider.get_meta("run") as PipeView
	if pipe == null or not player.ray.is_colliding():
		return
	plant.begin_gesture()
	_cut = {"pipe": pipe, "point": player.ray.get_collision_point(),
		"forward": -player.camera.global_basis.z}
	_cut_done = false


## Each physics frame while the button is held on a line: once the look
## has pulled far enough across it, the line is cut where it was picked.
func _update_cut() -> void:
	if _cut.is_empty() or _cut_done:
		return
	var forward: Vector3 = _cut["forward"]
	var now := -player.camera.global_basis.z
	if forward.angle_to(now) < CUT_PULL:
		return
	_cut_done = true
	var pipe := _cut["pipe"] as PipeView
	if not is_instance_valid(pipe):
		return
	var why := plant.cut_wire(pipe, _cut["point"])
	hud.toast("cut — capped both sides" if why == "" else why)
	_cut = {}


## ---- carrying equipment: the right button held on it ---------------------

var _carry_name := ""
var _carry_offset := Vector3.ZERO   # base less the ground point under the crosshair at pick-up
var _carry_moved := false


func _begin_carry() -> void:
	var view := player.look_view()
	var name_ := ""
	if view != null and view.has_meta("record_name"):
		name_ = str(view.get_meta("record_name"))
	else:
		# The crosshair on one of its fittings counts as on it (a pump is
		# small and its fittings stand proud of its body).
		var aimed := player.aimed_collider()
		if aimed != null and aimed.has_meta("port_name") and aimed.has_meta("record_name"):
			name_ = str(aimed.get_meta("record_name"))
	if name_ == "" or not plant.views.has(name_):
		return
	# A refusal says why (director, 2026-09-19: a right-hold that did
	# nothing, with no word about it).
	var why := plant.movable(name_)
	if why != "":
		hud.toast(why)
		return
	var base := _base_of(name_)
	var hit := _ground_hit(base.y)
	if hit == Vector3.INF:
		hud.toast("look at the ground beside %s to carry it" % name_)
		return
	plant.begin_gesture()   # one undo step for the whole carry
	_carry_name = name_
	_carry_offset = base - hit
	_carry_moved = false


## Each physics frame while carried: the equipment follows the point
## on its own ground plane under the crosshair, snapped to the grid.
func _update_carry() -> void:
	var view := plant.views.get(_carry_name) as Node3D
	if view == null:
		_carry_name = ""
		return
	var base := _base_of(_carry_name)
	var hit := _ground_hit(base.y)
	if hit == Vector3.INF:
		return
	var target := EditGizmo.move_target(base, hit, _carry_offset, "move_xz")
	if target.is_equal_approx(base):
		return
	_carry_moved = true
	if _footprint_clear(_footprint_of(_carry_name), target, view.rotation.y, view):
		plant.move_equipment(_carry_name, target, view.rotation.y)
		if _gizmo != null and _edit_name == _carry_name:
			_gizmo.refresh()
			_gizmo.set_blocked(false)
	elif _gizmo != null and _edit_name == _carry_name:
		_gizmo.set_blocked(true)


func _turn_carried(angle: float) -> void:
	var view := plant.views.get(_carry_name) as Node3D
	if view == null:
		return
	var rot := wrapf(view.rotation.y + angle, 0.0, TAU)
	if _footprint_clear(_footprint_of(_carry_name), _base_of(_carry_name), rot, view):
		plant.move_equipment(_carry_name, _base_of(_carry_name), rot)
		_carry_moved = true
		if _gizmo != null and _edit_name == _carry_name:
			_gizmo.refresh()
	else:
		hud.toast("no room to turn it")


func _end_carry() -> void:
	_carry_name = ""
	if _gizmo != null:
		_gizmo.set_blocked(false)


## The placement point of a record's view, in world space.
func _base_of(name_: String) -> Vector3:
	var view := plant.views[name_] as Node3D
	return view.global_position - Vector3(0, float(PlantFactory.Y_OFFSETS.get(plant.equip_types[name_], 0.0)), 0)


func _footprint_of(name_: String) -> Vector3:
	var tank := plant.sim.get_component(name_) as SimTank
	if tank != null:
		return Vector3(tank.diameter_m * 1.1, tank.height_m, tank.diameter_m * 1.1)
	return PlantFactory.FOOTPRINTS[plant.equip_types[name_]]


## Where the crosshair's ray meets the ground plane at height y.
func _ground_hit(y: float) -> Vector3:
	var ray := _edit_ray()
	var hit: Variant = Plane(Vector3.UP, Vector3(0, y, 0)).intersects_ray(ray[0], ray[1])
	return hit as Vector3 if hit != null else Vector3.INF


func _edit_mouse(event: InputEvent) -> bool:
	if _gizmo == null and _leg_gizmo == null:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					# A double click opens the properties of the selected
					# equipment, or a selected line's service editor
					# (director, 2026-09-13).
					if button.double_click:
						_drag = ""
						if _edit_run != null:
							_edit_run.use()
						else:
							_open_config_menu(_edit_name)
						return true
					_begin_drag()
					if _drag == "":
						# Not a handle: the selected thing again deselects it,
						# another leg or piece of equipment selects that.
						var aimed := player.aimed_collider()
						if aimed != null and aimed.has_meta("run") and aimed.has_meta("leg"):
							var pipe := aimed.get_meta("run") as PipeView
							var leg := int(aimed.get_meta("leg"))
							if pipe == _edit_run and leg == _edit_leg:
								_set_mode(Mode.NORMAL)
							elif leg >= 0:
								_select_leg(pipe, leg)
							return true
						var under := _equipment_under_pointer()
						if under != "" and under == _edit_name:
							_set_mode(Mode.NORMAL)
						elif under != "" and plant.movable(under) == "":
							_select(under)
				else:
					_drag = ""
					plant.end_gesture()
					if _gizmo != null:
						_gizmo.set_blocked(false)
				return true
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				return _mode_mouse(event)  # carry, turn, and a click deselects
	return false


## The record whose equipment is under the crosshair, or "".
func _equipment_under_pointer() -> String:
	var ray := _edit_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 200.0, 1 | 4)
	query.exclude = [player.get_rid()]
	var hit := player.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider := hit["collider"] as Node
	if collider == null or not collider.has_meta("view"):
		return ""
	var view := collider.get_meta("view") as Node
	if view == null or not view.has_meta("record_name"):
		return ""
	return str(view.get_meta("record_name"))


## The properties of a record: its device menu, I/O and CONFIGURE.
func _open_config_menu(name_: String) -> void:
	if name_ == "":
		return
	var type_id := str(plant.equip_types.get(name_, ""))
	port_menu.open(plant, "%s — %s" % [name_, type_id if type_id != "" else "device"], [name_], type_id,
		_port_picked,
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
	if _gizmo == null and _leg_gizmo == null:
		return
	var ray := _edit_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 200.0,
		EditGizmo.LAYER)
	var pick := player.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if OS.has_environment("FLOWSTATE_INPUT_DEBUG"):
		print("[input] handle pick from %s along %s: %s" % [str(ray[0]), str(ray[1]), str(pick)])
	if pick.is_empty():
		return
	var collider := pick["collider"] as Node
	if collider == null or not collider.has_meta("handle"):
		return
	_drag = str(collider.get_meta("handle"))
	plant.begin_gesture()   # one undo step for the whole drag
	if _drag.begins_with("end") or _drag == "mid":
		# A corner of a selected leg, or its middle: it moves in its own
		# level plane.
		var index := _leg_gizmo.corner_index(_drag)
		if index < 0 or index >= _leg_gizmo.path.size():
			_drag = ""
			return
		var corner := plant.to_global(_leg_gizmo.drag_origin(_drag))
		var corner_hit := _drag_hit(corner)
		if corner_hit == Vector3.INF:
			_drag = ""
			return
		_drag_offset_v = corner - corner_hit
		return
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
	if _drag.begins_with("end") or _drag == "mid":
		_update_corner_drag()
		return
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


## A selected leg's corner follows the crosshair in its own level
## plane, snapped to a quarter metre; the line is laid again through
## its corners a few times a second while the handle is held, and
## from then on those corners are the line's own.
func _update_corner_drag() -> void:
	if _leg_gizmo == null or not is_instance_valid(_edit_run):
		_drag = ""
		return
	var index := _leg_gizmo.corner_index(_drag)
	if index < 0 or index >= _leg_gizmo.path.size():
		_drag = ""
		return
	var corner := plant.to_global(_leg_gizmo.drag_origin(_drag))
	var hit := _drag_hit(corner)
	if hit == Vector3.INF:
		return
	var target := hit + _drag_offset_v
	target = Vector3(snappedf(target.x, 0.25), corner.y, snappedf(target.z, 0.25))
	if target.is_equal_approx(corner):
		return
	var now := Time.get_ticks_msec()
	if now - _leg_relay_ms < 150:
		return
	_leg_relay_ms = now
	var moved := plant.to_local(target)
	var waypoints := dragged_waypoints(plant.wire_waypoints(_edit_run), _leg_gizmo.path, index, moved,
		_leg_gizmo.drag_origin(_drag))
	var relaid := plant.set_wire_corners(_edit_run, waypoints)
	# The line is a new node now; the selection follows it, and so does
	# the leg: the corners the router derives can come and go with a
	# lay, so the leg is found again by the moved corner.
	if relaid == null:
		_set_mode(Mode.NORMAL)
		return
	_edit_run = relaid
	_leg_gizmo.pipe = relaid
	var path := plant.wire_path(relaid)
	var nearest := -1
	var best := 0.3
	for i in path.size():
		var d := path[i].distance_to(moved)
		if d < best:
			best = d
			nearest = i
	if nearest >= 0:
		if _drag == "mid":
			_drag = "end1"   # the middle is a corner now: the end of the first half
		_edit_leg = nearest if _drag == "end0" else nearest - 1
		_leg_gizmo.leg = _edit_leg
	_leg_gizmo.refresh(path, plant.wire_corners(relaid))


## What a dragged point of a line makes of its waypoints (2026-09-19:
## the director dragged a handle and "a spaghetti pile rapidly
## emerged" — every corner the router had derived, riser ends and
## square-turn legs, was sent back as a waypoint, derived new corners
## of its own on the next lay, and so on each tick). Only the player's
## waypoints are kept: the dragged point moves if it is one of them,
## or is inserted at its place along the path if the router laid it —
## a stub end included, so pulling the end of a straight at a fitting
## puts a corner there (director, the same day) — and a line gains one
## waypoint per point the player has actually touched. A riser's
## corners stand on one spot at different heights, so a waypoint over
## or under the dragged point moves with it. `index` is into `path`,
## the line as laid.
static func dragged_waypoints(waypoints: Array, path: Array, index: int, moved: Vector3,
		origin: Vector3 = Vector3.INF) -> Array:
	# `origin` is where the drag began when that is not a path point:
	# the middle of a leg, which then becomes a corner before `index`.
	var old: Vector3 = path[index] if origin == Vector3.INF else origin
	var out: Array = []
	var matched := false
	var insert_at := 0
	for w: Vector3 in waypoints:
		# Where along the laid path this waypoint stands.
		var at := -1
		var best := 0.02
		for i in path.size():
			var d := (path[i] as Vector3).distance_to(w)
			if d < best:
				best = d
				at = i
		var mate := absf(w.x - old.x) < 0.02 and absf(w.z - old.z) < 0.02
		out.append(Vector3(moved.x, w.y, moved.z) if mate else w)
		if mate:
			matched = true
		if at >= 0 and at < index:
			insert_at = out.size()
	if not matched:
		out.insert(insert_at, Vector3(moved.x, old.y, moved.z))
	return out


func _rotate_edited() -> void:
	_rotate_edited_by(PI / 2.0)


func _rotate_edited_by(angle: float) -> void:
	var view := plant.views.get(_edit_name) as Node3D
	if view == null or _gizmo == null:
		return
	var rot := wrapf(view.rotation.y + angle, 0.0, TAU)
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
