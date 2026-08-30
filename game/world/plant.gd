class_name Plant
extends Node3D
## Owns the sim graph and the fixed-rate tick; child views only render.
## All equipment — the commissioned starting loop and everything the
## player places — goes through PlantFactory, so save/load can rebuild
## the entire graph from a file.

const SIM_DT := 0.05  # 20 Hz, decoupled from frame rate
const SAVE_VERSION := 4  # v4 adds structures; v3 saves still load

var save_path: String = "user://save.json"
var build_suite: bool = true   # the hall builds the aseptic annex; the sandbox doesn't

var sim: Simulation
var historian: SimHistorian
var hmi_view: HmiView

# Convenience refs to the commissioned loop (refreshed after load).
var tank: SimTank
var switch: SimFloatSwitch
var relay: SimRelay
var pump: SimPump

var views: Dictionary = {}         # record name -> Node3D view
var equip_types: Dictionary = {}   # record name -> type_id
var protected: Dictionary = {}     # record name -> true (not deletable)
var structures: Dictionary = {}    # name -> {type, node}
var runs: Dictionary = {}          # name -> {kind, node, points (plant-local)}
var _wire_visuals: Array[Dictionary] = []   # {node, a, b}

var _accumulator: float = 0.0
# Support re-validation runs a few physics frames after geometry
# changes, once new/freed colliders have actually reached the space.
var _revalidate_in: int = 0
var _support_exercise_phase: int = 0
var _support_exercise_wait: int = 0


func _ready() -> void:
	_new_graph()
	_self_check()
	_build_initial_plant()
	_build_hmi()
	if DisplayServer.get_name() == "headless":
		_exercise_build_api()
		_support_exercise_phase = 1
		_support_exercise_wait = 4


## Headless smoke runs can't press B/C/X, so exercise the build API
## directly: place, connect, mis-wire, remove, save/load round-trip.
func _exercise_build_api() -> void:
	var problems: Array[String] = []
	var gauge := place_new("gauge_level", _world(Vector3(5.0, 0.0, -1.0)), 0.0)
	if gauge == null:
		problems.append("place gauge failed")
	elif connect_equipment("supply_tank", "level", gauge.comp_name, "process",
			[Vector3(4.0, 0.35, -1.5)]) != "":
		problems.append("gauge connect refused")
	if connect_equipment(gauge.comp_name, "signal", "fill_pump", "run") == "":
		problems.append("kind mismatch was NOT refused")
	for _i in 40:
		sim.tick()
	var reading := (gauge as SimGauge).reading
	if reading < 10.0 or reading > 20.0:
		problems.append("gauge reading %.2f kPa outside expected range" % reading)
	var pump2 := place_new("pump", _world(Vector3(6.0, 0.0, -1.0)), 0.0)
	if pump2 == null or not remove_equipment(pump2.comp_name):
		problems.append("place/remove pump failed")
	# Column: full duty from hot standby should settle the overhead near
	# 40 kPa within a couple of minutes, read honestly by a press gauge.
	var col := place_new("column", _world(Vector3(10.0, 0.0, 2.0)), 0.0) as SimColumn
	var pi_top := place_new("gauge_press", _world(Vector3(11.5, 0.0, 2.0)), 0.0)
	if col == null or pi_top == null:
		problems.append("place column/gauge failed")
	else:
		if connect_equipment(col.comp_name, "p_top", pi_top.comp_name, "process") != "":
			problems.append("pressure gauge connect refused")
		col.set_duty(1.0)
		for _i in 2400:
			sim.tick()
		var kpa := (pi_top as SimGauge).reading
		if kpa < 30.0 or kpa > 50.0:
			problems.append("column overhead %.1f kPa outside expected range" % kpa)
		if not remove_equipment(pi_top.comp_name) or not remove_equipment(col.comp_name):
			problems.append("column cleanup failed")
	# Air-cascade checks only where the aseptic suite exists (the hall).
	var cascade := sim.get_component("suite_hvac") as SimAirCascade
	if cascade != null:
		# Let the cascade settle, then verify ordering and the DP gauge.
		for _i in 2400:
			sim.tick()
		var p: Dictionary = cascade.pressures
		if not (0.0 < float(p["al1"]) and float(p["al1"]) < float(p["gown"])
				and float(p["gown"]) < float(p["al2"]) and float(p["al2"]) < float(p["core"])
				and float(p["core"]) < float(p["iso"])):
			problems.append("cascade ordering wrong: %s" % str(p))
		var pdi := sim.get_component("pdi_iso") as SimGauge
		if absf(pdi.reading - (float(p["iso"]) - float(p["core"]))) > 0.5:
			problems.append("dp gauge disagrees with cascade")
		cascade.set_door("gown_al2", true)
		cascade.set_door("al2_core", true)
		for _i in 600:
			sim.tick()
		if float(cascade.pressures["core"]) - float(cascade.pressures["gown"]) > 5.0:
			problems.append("open airlock failed to collapse the step")
		cascade.set_door("gown_al2", false)
		cascade.set_door("al2_core", false)
	if remove_equipment("supply_tank"):
		problems.append("protected equipment was removable")
	# Disconnect: pull the gauge's run, then wire it again — the
	# single-source slot must free up.
	if not sim.disconnect_ports(sim.get_component("supply_tank"), "level",
			sim.get_component(gauge.comp_name), "process"):
		problems.append("disconnect refused")
	else:
		var stale: PipeView = null
		for visual in _wire_visuals:
			if visual["b"] == gauge.comp_name:
				stale = visual["node"] as PipeView
		if stale == null or not remove_run(stale):
			# remove_run also disconnects; here the wire is already gone,
			# so only the visual bookkeeping path is exercised.
			pass
		if connect_equipment("supply_tank", "level", gauge.comp_name, "process",
				[Vector3(4.0, 0.35, -1.5)]) != "":
			problems.append("rewire after disconnect refused")
	var real_path := save_path
	save_path = "user://selfcheck_save.json"
	var roundtrip := save_game() and load_game()
	save_path = real_path
	if not roundtrip:
		problems.append("save/load round-trip failed")
	elif sim.get_component(gauge.comp_name) == null:
		problems.append("placed gauge missing after load")
	elif tank == null or pump == null:
		problems.append("commissioned refs missing after load")
	else:
		var routed := false
		for visual in _wire_visuals:
			if (visual["waypoints"] as Array).size() > 0:
				routed = true
		if not routed:
			problems.append("routed waypoints lost in save/load round-trip")
	if problems.is_empty():
		print("[flowstate] build-api exercise OK — gauge %.1f kPa, %d components, %d wires"
			% [reading, sim.components.size(), sim.wires.size()])
	else:
		push_warning("[flowstate] build-api exercise FAILED: " + "; ".join(problems))


func _physics_process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= SIM_DT:
		sim.tick()
		_accumulator -= SIM_DT
	if _revalidate_in > 0:
		_revalidate_in -= 1
		if _revalidate_in == 0:
			_revalidate_supports()
	if _support_exercise_phase > 0:
		_support_exercise_wait -= 1
		if _support_exercise_wait <= 0:
			_exercise_supports()


func _new_graph() -> void:
	sim = Simulation.new(SIM_DT)
	historian = sim.attach_historian(SimHistorian.new())


## ---- equipment lifecycle ------------------------------------------------

func place(type_id: String, name_: String, params: Dictionary,
		world_pos: Vector3, rot_y: float, is_protected: bool) -> SimComponent:
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	if record == null:
		return null
	sim.register_with_historian(record)
	var extra: SimComponent = switch if (type_id == "tank" and is_protected) else null
	var view := PlantFactory.make_view(type_id, record, extra)
	view.position = to_local(world_pos) + Vector3(0, PlantFactory.Y_OFFSETS.get(type_id, 0.0), 0)
	view.rotation.y = rot_y
	add_child(view)
	match type_id:
		"tank":
			(view as TankView).setup(record as SimTank, extra as SimFloatSwitch)
		"pump":
			(view as PumpView).setup(record as SimPump)
		"relay":
			(view as RelayView).setup(record as SimRelay)
		"float_switch":
			(view as FloatSwitchView).setup(record as SimFloatSwitch)
		"gauge_level", "gauge_flow", "gauge_dp", "gauge_press":
			(view as GaugeView).setup(record as SimGauge)
		"column":
			(view as ColumnView).setup(record as SimColumn)
		"air_cascade":
			(view as AsepticSuite).setup(record as SimAirCascade)
	PlantFactory.attach_port_markers(view, record, type_id)
	views[record.comp_name] = view
	equip_types[record.comp_name] = type_id
	if is_protected:
		protected[record.comp_name] = true
	return record


func place_new(type_id: String, world_pos: Vector3, rot_y: float) -> SimComponent:
	return place(type_id, sim.unique_name(type_id), {}, world_pos, rot_y, false)


func remove_equipment(name_: String) -> bool:
	if protected.has(name_) or not views.has(name_):
		return false
	sim.remove_component(name_)
	var keep: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["a"] == name_ or visual["b"] == name_:
			(visual["node"] as Node).queue_free()
		else:
			keep.append(visual)
	_wire_visuals = keep
	(views[name_] as Node).queue_free()
	views.erase(name_)
	equip_types.erase(name_)
	return true


## Connect two ports (by record/port name), optionally routed through
## player-laid waypoints (plant-local). Returns "" on success or a
## human-readable refusal — the kernel's wiring rules, surfaced.
func connect_equipment(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array = []) -> String:
	var src := sim.get_component(src_name)
	var dst := sim.get_component(dst_name)
	if src == null or dst == null:
		return "component missing"
	var out_port: SimOutputPort = src.outputs.get(src_port)
	var in_port: SimInputPort = dst.inputs.get(dst_port)
	if out_port == null or in_port == null:
		return "connect an output to an input"
	if out_port.kind != in_port.kind:
		return "cannot wire %s (%s) to %s (%s)" % [
			out_port.path(), SimTypes.kind_name(out_port.kind),
			in_port.path(), SimTypes.kind_name(in_port.kind)]
	if in_port.wire_count > 0 and not SimTypes.allows_multiple_sources(in_port.kind):
		return "%s already has a wire" % in_port.path()
	if not sim.connect_ports(src, src_port, dst, dst_port):
		return "connection refused"
	_wire_visual(src_name, src_port, dst_name, dst_port, waypoints)
	return ""


## ---- structure ----------------------------------------------------------

func unique_struct_name(prefix: String) -> String:
	var index := 1
	while structures.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]


## base_pos is the bottom-center placement point in world space.
## Bearing rules are the caller's job (StructureFactory.placement_ok);
## the loader and headless exercises place directly.
func place_structure(type_id: String, name_: String, base_pos: Vector3, rot_y: float,
		length: float = -1.0) -> bool:
	if structures.has(name_):
		return false
	var node := StructureFactory.make_view(type_id, name_, length)
	if node == null:
		return false
	add_child(node)
	node.global_position = base_pos + Vector3(0, (StructureFactory.SIZES[type_id] as Vector3).y / 2.0, 0)
	node.rotation.y = rot_y
	structures[name_] = {"type": type_id, "node": node, "length": length}
	_revalidate_in = 3
	return true


## Removing structure re-checks every run: whatever it was carrying
## turns alarm-red rather than quietly staying up.
func remove_structure(name_: String) -> bool:
	if not structures.has(name_):
		return false
	((structures[name_] as Dictionary)["node"] as Node).queue_free()
	structures.erase(name_)
	_revalidate_in = 3
	return true


## ---- standalone infrastructure runs --------------------------------------

func unique_run_name(prefix: String) -> String:
	var index := 1
	while runs.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]


## A routed run with no kernel wire behind it: pipe, conduit, or cable
## tray laid ahead of the equipment it will one day serve. sparse
## points are plant-local; colliders go on layer 1, so the run is real
## support for whatever gets routed along it later.
func place_run(kind: String, name_: String, sparse_local: Array) -> bool:
	if runs.has(name_) or not StructureFactory.RUNS.has(kind):
		return false
	var spec: Dictionary = StructureFactory.RUNS[kind]
	var view := PipeView.new()
	add_child(view)
	view.setup(PipeRoute.orthogonalize(sparse_local), func() -> float: return 0.0,
		spec["color"], spec["radius"], name_, spec["style"], 1)
	runs[name_] = {"kind": kind, "node": view, "points": sparse_local}
	_revalidate_in = 3
	return true


func remove_placed_run(view: PipeView) -> bool:
	for name_: String in runs:
		if (runs[name_] as Dictionary)["node"] == view:
			view.queue_free()
			runs.erase(name_)
			_revalidate_in = 3  # whatever it carried re-checks
			return true
	return false


## Remove one routed run by its view (X while aiming at it): the wire
## leaves the kernel, the input reverts next scan, the visual goes.
func remove_run(view: PipeView) -> bool:
	for visual in _wire_visuals:
		if visual["node"] == view:
			var src := sim.get_component(visual["a"])
			var dst := sim.get_component(visual["b"])
			if src != null and dst != null:
				sim.disconnect_ports(src, str(visual["a_port"]), dst, str(visual["b_port"]))
			(visual["node"] as Node).queue_free()
			_wire_visuals.erase(visual)
			return true
	return false


## Re-run the support rule over every routed run — wires and standalone
## infrastructure — updating brackets and alarm state. Called a few
## frames after geometry changes. A run excludes its own colliders so
## it can't count as its own support.
func _revalidate_supports() -> void:
	var space := get_world_3d().direct_space_state
	for visual in _wire_visuals:
		var sparse: Array = [_marker_pos(str(visual["a"]), str(visual["a_port"]))]
		sparse.append_array(visual["waypoints"])
		sparse.append(_marker_pos(str(visual["b"]), str(visual["b_port"])))
		_apply_support(visual["node"] as PipeView, sparse, space)
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		_apply_support(entry["node"] as PipeView, entry["points"], space)


func _apply_support(view: PipeView, sparse_local: Array, space: PhysicsDirectSpaceState3D) -> void:
	var path := PipeRoute.orthogonalize(sparse_local)
	var global_path: Array[Vector3] = []
	for point in path:
		global_path.append(to_global(point))
	var result := SupportCheck.evaluate(global_path, space, view.collider_rids())
	var local_brackets: Array[Dictionary] = []
	for bracket: Dictionary in result["brackets"]:
		local_brackets.append({"from": to_local(bracket["from"]), "to": to_local(bracket["to"])})
	view.set_supports(local_brackets, not bool(result["ok"]))


func _wire_visual(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array) -> void:
	var from := _marker_pos(src_name, src_port)
	var to := _marker_pos(dst_name, dst_port)
	var record := sim.get_component(src_name)
	var port: SimOutputPort = record.outputs[src_port]
	var is_process := port.kind == SimTypes.PortKind.PROCESS_FLOW \
		or port.kind == SimTypes.PortKind.PROCESS_LEVEL
	var color: Color = PlantFactory.KIND_COLORS[port.kind]
	var sparse: Array = [from]
	sparse.append_array(waypoints)
	sparse.append(to)
	var pipe := PipeView.new()
	add_child(pipe)
	pipe.setup(PipeRoute.orthogonalize(sparse), func() -> float: return port.value,
		color, 0.07 if is_process else 0.025,
		"%s.%s -> %s.%s" % [src_name, src_port, dst_name, dst_port])
	_wire_visuals.append({
		"node": pipe, "a": src_name, "a_port": src_port,
		"b": dst_name, "b_port": dst_port, "waypoints": waypoints,
	})
	_revalidate_in = 3


func _marker_pos(record_name: String, port_name: String) -> Vector3:
	var view: Node3D = views.get(record_name)
	if view == null:
		return Vector3.ZERO
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Node3D = markers.get(port_name)
	return to_local(marker.global_position) if marker != null else view.position


## ---- the commissioned starting loop -------------------------------------

func _build_initial_plant() -> void:
	# Switch first: the tank view draws its trip rings from it.
	switch = place("float_switch", "level_switch", {"low_l": 40.0, "high_l": 80.0},
		_world(Vector3(1.55, 1.32, -2.0)), 0.0, true) as SimFloatSwitch
	tank = place("tank", "supply_tank",
		{"capacity_l": 100.0, "level_l": 70.0, "drain_lps": 1.5},
		_world(Vector3(2.5, 0, -2.0)), 0.0, true) as SimTank
	relay = place("relay", "pump_relay", {},
		_world(Vector3(-2.5, 1.5, -4.74)) - Vector3(0, PlantFactory.Y_OFFSETS["relay"], 0),
		0.0, true) as SimRelay
	pump = place("pump", "fill_pump", {"rated_lps": 4.0},
		_world(Vector3(-0.5, 0, -2.6)), 0.0, true) as SimPump
	# Signal runs drop to the floor and run along it — the support rule
	# applies to the commissioned loop too.
	connect_equipment("supply_tank", "level", "level_switch", "level")
	connect_equipment("level_switch", "contact", "pump_relay", "coil",
		[Vector3(1.7, 0.3, -3.4), Vector3(-2.7, 0.3, -4.3)])
	connect_equipment("pump_relay", "contact", "fill_pump", "run",
		[Vector3(-2.3, 0.3, -3.6), Vector3(-0.8, 0.3, -2.7)])
	connect_equipment("fill_pump", "flow", "supply_tank", "in_flow")
	if build_suite:
		_build_aseptic_suite()


func _build_aseptic_suite() -> void:
	# The suite view builds its own world-space geometry; keep its node
	# at global y=0 (plant sits 0.08 up on the plinth).
	place("air_cascade", "suite_hvac", {}, _world(Vector3(0, -0.08, 0)), 0.0, true)
	var gauge_specs: Array = [
		["pdi_gown", Vector3(-27.9, -0.08, -8.2), "p_gown", "p_al1"],
		["pdi_core", Vector3(-32.2, -0.08, -7.3), "p_core", "p_al2"],
		["pdi_iso", Vector3(-34.2, -0.08, -6.9), "p_iso", "p_core"],
	]
	for spec: Array in gauge_specs:
		place("gauge_dp", spec[0], {}, _world(spec[1]), 0.0, true)
		connect_equipment("suite_hvac", spec[2], spec[0], "process_a")
		connect_equipment("suite_hvac", spec[3], spec[0], "process_b")


func _world(local: Vector3) -> Vector3:
	return to_global(local)


func _build_hmi() -> void:
	hmi_view = HmiView.new()
	hmi_view.position = Vector3(-4.6, 1.6, -4.75)
	add_child(hmi_view)
	hmi_view.setup(historian, tank, switch, relay, pump)


func _self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var c_tank := check.add(SimTank.new("t", 100.0, 70.0, 1.5)) as SimTank
	var c_switch := check.add(SimFloatSwitch.new("s", 40.0, 80.0)) as SimFloatSwitch
	var c_relay := check.add(SimRelay.new("r")) as SimRelay
	var c_pump := check.add(SimPump.new("p", 4.0)) as SimPump
	check.connect_ports(c_tank, "level", c_switch, "level")
	check.connect_ports(c_switch, "contact", c_relay, "coil")
	check.connect_ports(c_relay, "contact", c_pump, "run")
	check.connect_ports(c_pump, "flow", c_tank, "in_flow")
	check.run_for(600.0)
	var ok := c_tank.level_l >= 38.0 and c_tank.level_l <= 82.0 \
		and c_tank.overflowed_l == 0.0 and c_relay.cycles < 15
	if ok:
		print("[flowstate] kernel self-check OK — 600 s: level %.1f L, %d relay cycles"
			% [c_tank.level_l, c_relay.cycles])
	else:
		push_warning("[flowstate] kernel self-check FAILED — level %.1f L, overflow %.1f L, %d cycles"
			% [c_tank.level_l, c_tank.overflowed_l, c_relay.cycles])


## Headless support-rule exercise. Physics space queries see nothing
## during _ready (colliders land in the space a frame later), so this
## runs in two phases from _physics_process: phase 1 checks an open
## span and places test structure; phase 2 checks the braced span and
## the structure bearing rules, then cleans up.
func _exercise_supports() -> void:
	var space := get_world_3d().direct_space_state
	# A lane clear of incidental support in both worlds: sandbox pad is
	# bare there, and the hall's column grid (x/z multiples of 8) and
	# mezzanine posts all miss the z=4 line within x in [-4, 4].
	var origin := to_global(Vector3(0.0, -0.08, 4.0))
	var run: Array[Vector3] = [origin + Vector3(-4, 2, 0), origin + Vector3(4, 2, 0)]
	if _support_exercise_phase == 1:
		var open_check := SupportCheck.evaluate(run, space)
		if bool(open_check["ok"]):
			push_warning("[flowstate] support exercise FAILED: 8 m air span passed (max span %.2f)"
				% float(open_check["max_span"]))
			_support_exercise_phase = 0
			return
		place_structure("s_column", "chk_col_1", origin + Vector3(-1.4, 0, 0), 0.0)
		place_structure("s_column", "chk_col_2", origin + Vector3(1.4, 0, 0), 0.0)
		place_structure("s_column", "chk_col_3", origin + Vector3(-2.8, 0, 4), 0.0)
		place_structure("s_column", "chk_col_4", origin + Vector3(2.8, 0, 4), 0.0)
		_support_exercise_phase = 2
		_support_exercise_wait = 4
		return
	var problems: Array[String] = []
	var braced_check := SupportCheck.evaluate(run, space)
	if not bool(braced_check["ok"]):
		problems.append("braced span still failed (max span %.2f)" % float(braced_check["max_span"]))
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space) != "":
		problems.append("beam across two columns was refused")
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space, 5.8) != "":
		problems.append("stretched 5.8 m beam across columns was refused")
	# The interactive flow seats beams center-to-center: length equals
	# the column spacing exactly. Must bear (regression: the 0.2 m end
	# inset used to miss the 0.35 m column with a hairline ray).
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space, 5.6) != "":
		problems.append("center-to-center beam across columns was refused")
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 8), 0.0, space) == "":
		problems.append("floating beam was accepted")
	if _support_exercise_phase == 2:
		if not problems.is_empty():
			push_warning("[flowstate] support exercise FAILED: " + "; ".join(problems))
			_support_exercise_phase = 0
			return
		# Lay a floor-hugging cable tray; next phase, conduit strung
		# above it must count the tray as its support.
		place_run("run_tray", "chk_tray",
			[to_local(origin + Vector3(-3.6, 0.42, 2)), to_local(origin + Vector3(3.6, 0.42, 2))])
		_support_exercise_phase = 3
		_support_exercise_wait = 4
		return
	var tray_view := (runs["chk_tray"] as Dictionary)["node"] as PipeView
	var conduit: Array[Vector3] = [origin + Vector3(-3.5, 0.95, 2), origin + Vector3(3.5, 0.95, 2)]
	var over_tray := SupportCheck.evaluate(conduit, space)
	if not bool(over_tray["ok"]):
		problems.append("conduit over the tray was not supported by it")
	var without_tray := SupportCheck.evaluate(conduit, space, tray_view.collider_rids())
	if bool(without_tray["ok"]):
		problems.append("conduit counted something other than the tray as support")
	if not remove_placed_run(tray_view):
		problems.append("tray cleanup failed")
	for chk in ["chk_col_1", "chk_col_2", "chk_col_3", "chk_col_4"]:
		if not remove_structure(chk):
			problems.append("structure cleanup failed")
	_support_exercise_phase = 0
	if problems.is_empty():
		print("[flowstate] support exercise OK — spans, bearings, and tray-as-support all behave")
	else:
		push_warning("[flowstate] support exercise FAILED: " + "; ".join(problems))


## ---- save / load ---------------------------------------------------------

func save_game() -> bool:
	var comps: Array[Dictionary] = []
	for name_: String in views:
		var record := sim.get_component(name_)
		var view: Node3D = views[name_]
		comps.append({
			"type": equip_types[name_],
			"name": name_,
			"state": record.state_dict(),
			"params": _params_for(record),
			"pos": [view.global_position.x, view.global_position.y
				- PlantFactory.Y_OFFSETS.get(equip_types[name_], 0.0), view.global_position.z],
			"rot_y": view.rotation.y,
			"protected": protected.has(name_),
		})
	var wire_list: Array = []
	for visual in _wire_visuals:
		var path_out: Array = []
		for point: Vector3 in visual["waypoints"]:
			path_out.append([point.x, point.y, point.z])
		wire_list.append({
			"src": visual["a"], "src_port": visual["a_port"],
			"dst": visual["b"], "dst_port": visual["b_port"],
			"waypoints": path_out,
		})
	var struct_list: Array = []
	for name_: String in structures:
		var entry: Dictionary = structures[name_]
		var node := entry["node"] as Node3D
		var size: Vector3 = StructureFactory.SIZES[entry["type"]]
		var base := node.global_position - Vector3(0, size.y / 2.0, 0)
		struct_list.append({
			"type": entry["type"], "name": name_,
			"pos": [base.x, base.y, base.z], "rot_y": node.rotation.y,
			"length": entry.get("length", -1.0),
		})
	var run_list: Array = []
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		var pts: Array = []
		for point: Vector3 in entry["points"]:
			pts.append([point.x, point.y, point.z])
		run_list.append({"kind": entry["kind"], "name": name_, "points": pts})
	var payload := {
		"version": SAVE_VERSION, "time": sim.time,
		"components": comps, "wires": wire_list, "structures": struct_list,
		"runs": run_list,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	return true


func _params_for(record: SimComponent) -> Dictionary:
	if record is SimTank:
		return {"capacity_l": (record as SimTank).capacity_l}
	if record is SimPump:
		return {"rated_lps": (record as SimPump).rated_lps}
	if record is SimFloatSwitch:
		var fs := record as SimFloatSwitch
		return {"low_l": fs.low_l, "high_l": fs.high_l}
	if record is SimGauge:
		return {"liters_per_meter": (record as SimGauge).liters_per_meter}
	if record is SimColumn:
		var col := record as SimColumn
		return {"charge_l": col.charge_l, "max_duty_kw": col.max_duty_kw}
	return {}


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not int((parsed as Dictionary).get("version", 0)) in [3, SAVE_VERSION]:
		return false
	var payload := parsed as Dictionary

	for name_: String in views:
		(views[name_] as Node).queue_free()
	for visual in _wire_visuals:
		(visual["node"] as Node).queue_free()
	for name_: String in structures:
		((structures[name_] as Dictionary)["node"] as Node).queue_free()
	for name_: String in runs:
		((runs[name_] as Dictionary)["node"] as Node).queue_free()
	views.clear()
	equip_types.clear()
	protected.clear()
	structures.clear()
	runs.clear()
	_wire_visuals.clear()
	_new_graph()

	for entry: Dictionary in payload.get("runs", []):
		var pts: Array = []
		for point: Array in entry["points"]:
			pts.append(Vector3(point[0], point[1], point[2]))
		place_run(entry["kind"], entry["name"], pts)

	for entry: Dictionary in payload.get("structures", []):
		var pos_arr: Array = entry["pos"]
		place_structure(entry["type"], entry["name"],
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]), float(entry.get("rot_y", 0.0)),
			float(entry.get("length", -1.0)))

	for entry: Dictionary in payload["components"]:
		var pos_arr: Array = entry["pos"]
		var record := place(entry["type"], entry["name"], entry.get("params", {}),
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			float(entry.get("rot_y", 0.0)), bool(entry.get("protected", false)))
		if record != null:
			record.apply_state(entry.get("state", {}))
	for wire_entry: Dictionary in payload["wires"]:
		var waypoints: Array = []
		for point: Array in wire_entry.get("waypoints", []):
			waypoints.append(Vector3(point[0], point[1], point[2]))
		connect_equipment(wire_entry["src"], wire_entry["src_port"],
			wire_entry["dst"], wire_entry["dst_port"], waypoints)
	sim.time = float(payload.get("time", 0.0))

	tank = sim.get_component("supply_tank") as SimTank
	switch = sim.get_component("level_switch") as SimFloatSwitch
	relay = sim.get_component("pump_relay") as SimRelay
	pump = sim.get_component("fill_pump") as SimPump
	if hmi_view != null and tank != null:
		hmi_view.panel.setup(historian, tank, switch, relay, pump)
	return true
