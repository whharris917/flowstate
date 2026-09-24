class_name Plant
extends Node3D
## Owns the sim graph and the fixed-rate tick; child views only render.
## All equipment — the commissioned starting loop and everything the
## player places — goes through PlantFactory, so save/load can rebuild
## the entire graph from a file.

const SIM_DT := 0.05  # 20 Hz, decoupled from frame rate
const SAVE_VERSION := 5  # v5: pressure kernel, no draw wires; v3/v4 saves still load

var save_path: String = "user://save.json"
var build_suite: bool = true   # the hall builds the aseptic annex; the sandbox doesn't
var config_panel: RunConfigPanel = null   # injected by the world after _ready
var cabinet_editor: CabinetEditor = null  # injected by the world after _ready
var ladder_panel: LadderPanel = null      # injected by the world after _ready

var sim: Simulation
var historian: SimHistorian
var hmi_view: HmiView
var balance_panel: PlantBalancePanel

# Convenience refs to the commissioned loop (refreshed after load).
var tank: SimTank
var switch: SimFloatSwitch
var relay: SimRelay
var pump: SimPump

var views: Dictionary = {}         # record name -> Node3D view
var equip_types: Dictionary = {}   # record name -> type_id
var protected: Dictionary = {}     # record name -> true (not deletable)

## ---- undo / redo -------------------------------------------------------------
## Every edit begins with checkpoint(): the plant as it stands goes on
## the undo stack as a snapshot, once per frame at most, and a gesture
## (a carry, a handle drag, a nozzle grab, a cut) is one step however
## many frames it lasts. Undo restores the last snapshot and keeps the
## present for redo. Off until the world has finished building, and
## while a snapshot is being restored.
const UNDO_DEPTH := 50
var undo_enabled := false
var _restoring := false
var _gesture := false
var _undo: Array[String] = []
var _redo: Array[String] = []
var _checkpoint_frame: int = -1


func checkpoint() -> void:
	if not undo_enabled or _restoring or _gesture:
		return
	var frame := Engine.get_process_frames()
	if frame == _checkpoint_frame:
		return
	_checkpoint_frame = frame
	var state := JSON.stringify(snapshot())
	if not _undo.is_empty() and _undo[_undo.size() - 1] == state:
		return
	_undo.append(state)
	while _undo.size() > UNDO_DEPTH:
		_undo.pop_front()
	_redo.clear()


## A gesture is one undo step: the checkpoint is taken as it begins,
## and nothing inside it takes another. A gesture that changed nothing
## leaves no step.
func begin_gesture() -> void:
	checkpoint()
	_gesture = true


func end_gesture() -> void:
	_gesture = false
	for visual in _wire_visuals:
		if visual["node"] != null and bool(visual.get("fixed", false)):
			_bake(visual)   # a corner the lay added during the gesture is the line's now
	if undo_enabled and not _undo.is_empty() and _undo[_undo.size() - 1] == JSON.stringify(snapshot()):
		_undo.pop_back()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Back one step; "" on success, else why not.
func undo() -> String:
	if _undo.is_empty():
		return "nothing to undo"
	_gesture = false
	var present := JSON.stringify(snapshot())
	var state: String = _undo.pop_back()
	if not restore(JSON.parse_string(state) as Dictionary):
		return "undo failed"
	_redo.append(present)
	return ""


func redo() -> String:
	if _redo.is_empty():
		return "nothing to redo"
	_gesture = false
	var present := JSON.stringify(snapshot())
	var state: String = _redo.pop_back()
	if not restore(JSON.parse_string(state) as Dictionary):
		return "redo failed"
	_undo.append(present)
	return ""
var cabinets: Dictionary = {}      # name -> {node, plc, terminals}
var junction_boxes: Dictionary = {}  # name -> {node, records, channels, on_post}
var control_stations: Dictionary = {}  # name -> {node, records, devices, on_post}
var member_of: Dictionary = {}     # record name -> cabinet name
var mounted: Dictionary = {}       # instrument name -> {host, frac, angle}
var structures: Dictionary = {}    # name -> {type, node}
var runs: Dictionary = {}          # name -> {kind, node, points (plant-local)}
var _wire_visuals: Array[Dictionary] = []   # {node, a, b}
var _wire_serial: int = 0   # the order runs were laid in: a run yields only to earlier ones
const ORDER_ALL := 1 << 30

var _accumulator: float = 0.0
var last_tick_ms: float = 0.0     # what the latest scan cost, for the frame-rate overlay

# The scans a frame owes run on a worker thread while the frame is
# drawn, off the main thread's critical path. The
# window is RenderingServer.frame_pre_draw to frame_post_draw: every
# script that reads the sim — the views' _process, the HUD, the
# alarms, the screens' _draw (flushed after _process), input handlers,
# saves — runs outside it, and the sim itself never touches a node.
# The thread is joined before the draw ends, so nothing ever sees a
# scan in progress. Headless runs, and FLOWSTATE_SYNC_SCAN=1, scan in
# the physics step.
const MAX_SCANS_PER_FRAME := 3
var threaded_scan: bool = DisplayServer.get_name() != "headless" \
	and OS.get_environment("FLOWSTATE_SYNC_SCAN") == ""
var _scans_due: int = 0
var _scan_thread: Thread = null
var _scan_hooked := false


func _run_scans(count: int) -> void:
	for _i in count:
		var started := Time.get_ticks_usec()
		sim.tick()
		var elapsed := Time.get_ticks_usec() - started
		last_tick_ms = elapsed / 1000.0
		_note_cost(elapsed)


func _start_scans() -> void:
	if _scans_due <= 0 or _scan_thread != null:
		return
	_scan_thread = Thread.new()
	_scan_thread.start(_run_scans.bind(_scans_due))
	_scans_due = 0


func _finish_scans() -> void:
	if _scan_thread == null:
		return
	var started := Time.get_ticks_usec()
	_scan_thread.wait_to_finish()
	_scan_thread = null
	# How long the frame waited for the scan: the part of it still on
	# the critical path when the draw was shorter than the scan.
	last_join_ms = (Time.get_ticks_usec() - started) / 1000.0


var last_join_ms: float = 0.0


## At the end of the draw the scan is collected only if it is done;
## otherwise it runs on through the next frame's input and physics
## and is collected before the first _process (SceneTree.process_frame,
## emitted just before every node's _process), on any key or button
## (WorldBase._input, since a keypress may act on the sim), before a
## routing sweep, and during a nozzle grab (the build controller).
## Everything that reads or writes the sim lives past one of those.
func _join_if_done() -> void:
	if _scan_thread != null and not _scan_thread.is_alive():
		_finish_scans()


func _exit_tree() -> void:
	_finish_scans()
	if _scan_hooked:
		_scan_hooked = false
		RenderingServer.frame_pre_draw.disconnect(_start_scans)
		RenderingServer.frame_post_draw.disconnect(_join_if_done)
		if get_tree() != null:
			get_tree().process_frame.disconnect(_finish_scans)
# One-off kernel cost report, taken over the first few hundred scans.
var _cost_ticks: int = 0
var _cost_total_us: int = 0
var _cost_solve_ms: float = 0.0
var _cost_newton_ms: float = 0.0
var _cost_iterations: int = 0
var _cost_signal_ms: float = 0.0
var _cost_components_ms: float = 0.0
var _cost_historian_ms: float = 0.0
# Support re-validation runs a few physics frames after geometry
# changes, once new/freed colliders have actually reached the space.
var _revalidate_in: int = 0
var _relay_round: int = 0   # deferred re-lays since the last change; capped, see _revalidate_supports
var _relay_capped: int = 0  # runs a sweep would have re-laid past the cap
# A run yields only to earlier runs, so one sweep in laying order should
# settle it; but a re-laid run's new body is unknown to physics until
# the next frame, so the search's steering round it lags a round, and
# a plant of a hundred and fifty interacting runs takes a few.
const RELAY_ROUNDS := 6
var _support_exercise_phase: int = 0
var _support_exercise_wait: int = 0


## The commissioned starting loop and its HMI. A blank map sets this
## false and starts with nothing placed; the headless build exercises need the loop, so they
## run only with it.
var build_home := true

## The campaign ladder, when this world is gated (null: everything is
## available). The build controller asks is_unlocked before offering
## a type; place() itself never refuses, so loaders and showcases work.
var campaign: Milestones = null


func is_unlocked(type_id: String) -> bool:
	return campaign == null or campaign.unlocked(type_id)


## Milliseconds each startup phase took, for the world's startup line.
var startup_ms: Dictionary = {}


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	clearance = RunClearance.new(self)
	_new_graph()
	# The kernel self-checks simulate ten minutes of plant and cost
	# about eight seconds; they are for the headless smoke runs, not for
	# someone pressing Play.
	if DisplayServer.get_name() == "headless":
		_self_check()
	startup_ms["self-check"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	if build_home:
		_build_initial_plant()
	_build_hmi()
	startup_ms["home loop"] = Time.get_ticks_msec() - t0
	if DisplayServer.get_name() == "headless" and build_home:
		_exercise_build_api()
		_support_exercise_phase = 1
		_support_exercise_wait = 4


## Headless smoke runs can't press B/C/X, so exercise the build API
## directly: place, connect, mis-wire, remove, save/load round-trip.
## The visible run on a record, for the exercises. Null if none.
func _visible_run_of(name_: String) -> PipeView:
	for visual in _wire_visuals:
		if visual["node"] != null and (visual["a"] == name_ or visual["b"] == name_):
			return visual["node"] as PipeView
	return null


func _exercise_build_api() -> void:
	var problems: Array[String] = []
	# A level transmitter mounts on the tank's shell and is ranged to it.
	var gauge := mount_new("gauge_level", "supply_tank", 0.3, -0.7)
	if gauge == null:
		problems.append("mount gauge failed")
	if connect_equipment(gauge.comp_name, "signal", "fill_pump", "run") == "":
		problems.append("kind mismatch was NOT refused")
	for _i in 40:
		sim.tick()
	var reading := (gauge as SimGauge).reading
	var expected := tank.level_l / (tank.cross_section_m2 * 1000.0) * SimGauge.WATER_KPA_PER_M
	if absf(reading - expected) > 0.3:
		problems.append("gauge reading %.2f kPa, tank head is %.2f" % [reading, expected])
	var pump2 := place_new("pump", _world(Vector3(6.0, 0.0, -1.0)), 0.0)
	if pump2 == null or not remove_equipment(pump2.comp_name):
		problems.append("place/remove pump failed")
	# G move: a tank set down elsewhere carries its elevation, its run
	# follows, and commissioned equipment moves too.
	var mv_tank := place_new("tank", _world(Vector3(6.0, 0.0, -3.0)), 0.0) as SimTank
	var mv_drain := place_new("drain", _world(Vector3(8.0, 0.0, -3.0)), 0.0)
	if mv_tank == null or mv_drain == null:
		problems.append("place tank/drain for the move test failed")
	else:
		if connect_equipment(mv_tank.comp_name, "outlet", mv_drain.comp_name, "inlet") != "":
			problems.append("move test connect refused")
		var run_before := _visible_run_of(mv_tank.comp_name)
		if not move_equipment(mv_tank.comp_name, _world(Vector3(6.0, 3.0, -5.0)), PI / 2.0):
			problems.append("move_equipment refused a placed tank")
		if absf(mv_tank.elevation_m - 3.0) > 0.02:
			problems.append("moved tank elevation %.2f m, expected 3.0" % mv_tank.elevation_m)
		var run_after := _visible_run_of(mv_tank.comp_name)
		if run_before == null or run_after == null or run_after == run_before:
			problems.append("the moved tank's run was not re-laid")
		if movable("supply_tank") != "":
			problems.append("commissioned tank refused to move")
		# CONFIGURE: sizing edits land on the record, out-of-schema keys
		# and commissioned equipment are refused.
		if configure_equipment(mv_tank.comp_name, {"height_m": 2.0, "diameter_m": 1.2,
				"nozzle_cv_lps": 60.0}) != "":
			problems.append("configure_equipment refused a placed tank")
		if absf(mv_tank.height_m - 2.0) > 1e-6 or absf(mv_tank.nozzle_cv_lps - 60.0) > 1e-6:
			problems.append("configured tank size did not land on the record")
		# A transmitter on the shell is ranged again when the vessel is
		# resized: its litres per metre are the new
		# cross-section, or it reads the wrong kPa for the rest of the game.
		var mv_lt := mount_new("gauge_level", mv_tank.comp_name, 0.4, 0.6) as SimGauge
		if mv_lt == null:
			problems.append("could not mount a transmitter on the placed tank")
		else:
			if configure_equipment(mv_tank.comp_name, {"diameter_m": 1.8}) != "":
				problems.append("resize with a transmitter mounted was refused")
			var ranged := mv_tank.cross_section_m2 * 1000.0
			if absf(mv_lt.liters_per_meter - ranged) > 1e-6:
				problems.append("resized tank's transmitter reads %.1f L/m, expected %.1f" % [
					mv_lt.liters_per_meter, ranged])
			remove_equipment(mv_lt.comp_name)
		# A nozzle's weld is the kernel's nozzle height, and it follows a
		# resize; a line's size is the
		# nozzle's size, in the kernel and on the fitting.
		var mv_view := views[mv_tank.comp_name] as TankView
		mv_view.set_nozzle("outlet", 0.5, 0.0)
		if absf(mv_tank.nozzle_height("outlet") - 0.5 * mv_tank.height_m) > 1e-6:
			problems.append("welded outlet stands %.2f m up, expected %.2f" % [
				mv_tank.nozzle_height("outlet"), 0.5 * mv_tank.height_m])
		if configure_equipment(mv_tank.comp_name, {"height_m": 2.6}) != "":
			problems.append("resize after a weld was refused")
		if absf(mv_tank.nozzle_height("outlet") - 1.3) > 1e-6:
			problems.append("welded outlet did not follow the resize: %.2f m, expected 1.3" % mv_tank.nozzle_height("outlet"))
		var mv_run := _visible_run_of(mv_tank.comp_name)
		if mv_run == null:
			problems.append("no run on the placed tank to size")
		else:
			set_run_size(mv_run, 15)
			if int(mv_tank.nozzle_dn.get("outlet", 0)) != 15:
				problems.append("a DN15 line left the outlet at DN%d" % int(mv_tank.nozzle_dn.get("outlet", 0)))
			if absf(_end_bore(mv_tank.comp_name, "outlet") - line_radius(15)) > 1e-6:
				problems.append("the outlet fitting is not built at the line's bore")
			if absf(mv_tank.nozzle_cv("outlet") - mv_tank.nozzle_cv_lps * 0.09) > 1e-6:
				problems.append("a DN15 nozzle's Cv is not 9 %% of the DN50 figure")
			var mv_drain_fit := _end_bore(mv_drain.comp_name, "inlet")
			if absf(mv_drain_fit - line_radius(15)) > 1e-6:
				problems.append("the drain's inlet fitting is %.3f, expected the DN15 bore" % mv_drain_fit)
		if configure_equipment(mv_tank.comp_name, {"bogus": 1.0}) == "":
			problems.append("configure_equipment accepted an unknown key")
		if configure_equipment("supply_tank", {"height_m": 3.0}) == "":
			problems.append("commissioned tank was configurable")
		# The crosshair asks the interact body for its view: a tank's
		# must answer with the TankView, or hover, E, X and G miss it.
		var tank_view := views[mv_tank.comp_name] as Node3D
		var answers_for_tank := false
		for body in tank_view.find_children("*", "StaticBody3D", true, false):
			if (body as StaticBody3D).collision_layer == 4 and body.has_meta("view") \
					and body.get_meta("view") == tank_view:
				answers_for_tank = true
		if not answers_for_tank:
			problems.append("the tank's interact body does not name its view")
		if not remove_equipment(mv_drain.comp_name) or not remove_equipment(mv_tank.comp_name):
			problems.append("move test cleanup failed")
	var src_t := place_new("source", _world(Vector3(7.5, 0.0, 0.5)), 0.0)
	var drn_t := place_new("drain", _world(Vector3(8.6, 0.0, 0.5)), 0.0)
	if src_t == null or drn_t == null:
		problems.append("place source/drain failed")
	elif not remove_equipment(drn_t.comp_name) or not remove_equipment(src_t.comp_name):
		problems.append("source/drain removal failed")
	# Column: full duty from hot standby should settle the overhead near
	# 40 kPa within a couple of minutes, read honestly by a press gauge.
	var col := place_new("column", _world(Vector3(10.0, 0.0, 2.0)), 0.0) as SimColumn
	var pi_top := place_new("gauge_press", _world(Vector3(11.5, 0.0, 2.0)), 0.0)
	if col == null or pi_top == null:
		problems.append("place column/gauge failed")
	else:
		if connect_equipment(col.comp_name, "p_top", pi_top.comp_name, "process") != "":
			problems.append("pressure gauge connect refused")
		if connect_equipment("plant_mains", free_way("plant_mains"), col.comp_name, "power") != "":
			problems.append("column power feed refused")
		col.set_duty(1.0)
		for _i in 2400:
			sim.tick()
		var kpa := (pi_top as SimGauge).reading
		if kpa < 30.0 or kpa > 50.0:
			problems.append("column overhead %.1f kPa outside expected range" % kpa)
		if not remove_equipment(pi_top.comp_name) or not remove_equipment(col.comp_name):
			problems.append("column cleanup failed")
	# Enclosures: a station's circuit reaches a junction box through a
	# multicore, the cable survives a save and reload with a live getter,
	# and X on the box takes its circuits and the cable with it.
	var jb := unique_jb_name()
	var lcs := unique_station_name()
	if not place_junction_box(jb, _world(Vector3(13.0, 0.0, -4.0)), 0.0, 4) \
			or not place_control_station(lcs, _world(Vector3(15.0, 0.0, -4.0)), 0.0, default_station_devices()):
		problems.append("place junction box / station failed")
	else:
		var cable := "MC-X1"
		var err := connect_multicore(cable, [[lcs + "_start", "contact", jb + "_t1", "in"]], [])
		if err != "":
			problems.append("multicore refused: " + err)
		var keep_path := save_path
		save_path = "user://exercise_save.json"
		var saved := save_game()
		var loaded := saved and load_game()
		save_path = keep_path
		if not loaded:
			problems.append("save/load round trip failed")
		elif not runs.has(cable) or not (runs[cable] as Dictionary).has("circuits"):
			problems.append("the multicore did not reload with its circuits")
		elif sim.find_wire(sim.get_component(lcs + "_start"), "contact",
				sim.get_component(jb + "_t1"), "in") == null:
			problems.append("the multicore's wire did not reload")
		if not remove_junction_box(jb):
			problems.append("junction box removal refused")
		if runs.has(cable) or views.has(jb + "_t1") or sim.get_component(jb + "_t1") != null:
			problems.append("junction box removal left its cable or terminals behind")
		if not remove_control_station(lcs) or views.has(lcs + "_start"):
			problems.append("control station removal failed")
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
			problems.append("dp gauge disagrees with cascade: reads %.2f, iso - core is %.2f (iso %.2f, core %.2f)" % [pdi.reading, float(p["iso"]) - float(p["core"]), float(p["iso"]), float(p["core"])])
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
	# Disconnect: pull the gauge's mount wire, then land it again — the
	# single-source slot must free up.
	if not sim.disconnect_ports(sim.get_component("supply_tank"), "level",
			sim.get_component(gauge.comp_name), "process"):
		problems.append("disconnect refused")
	else:
		for visual in _wire_visuals.duplicate():
			if visual["b"] == gauge.comp_name:
				_wire_visuals.erase(visual)
		if connect_equipment("supply_tank", "level", gauge.comp_name, "process", [], false) != "":
			problems.append("rewire after disconnect refused")
	# Cabinet: starts empty, gets a panel built module by module, then a
	# field signal traverses terminal -> PLC rung -> terminal, and
	# through an interposing relay — field to panel to field. The rack
	# is dead until its PSU gets a 480 V feed.
	var cab := "chk_cab"
	if not place_cabinet(cab, _world(Vector3(3.0, 0.0, 6.5)), 0.0):
		problems.append("place cabinet failed")
		cab = ""
	else:
		if cabinet_plc(cab) != "" or not cabinet_all_records(cab).is_empty():
			problems.append("new cabinet was not empty")
		if cabinet_add_module(cab, "card_di", 0, 8) == "":
			problems.append("I/O card accepted without a CPU")
		if cabinet_add_module(cab, "psu", 0, 0) != "" \
				or cabinet_add_module(cab, "plc", 0, 4) != "" \
				or cabinet_add_module(cab, "card_di", 0, 8) != "" \
				or cabinet_add_module(cab, "card_do", 0, 10) != "" \
				or cabinet_add_module(cab, "relay", 1, 0) != "" \
				or cabinet_add_module(cab, "tb8d", 2, 0) != "":
			problems.append("module placement refused")
		if cabinet_add_module(cab, "plc", 1, 4) == "":
			problems.append("second CPU accepted")
		if cabinet_add_module(cab, "relay", 1, 0) == "":
			problems.append("overlapping module accepted")
		var backed: Dictionary = cabinet_backed_channels(cab)
		if (backed["di"] as Array).size() != 8 or (backed["ai"] as Array).size() != 0:
			problems.append("card-backed channels wrong: %s" % str(backed))
		var plc_name := cabinet_plc(cab)
		var cab_plc := sim.get_component(plc_name) as SimPLC
		var psu_name := ""
		var relay_name := ""
		var t := "%s_m6_t" % cab  # the tb8d strip's terminals
		for record_name in cabinet_all_records(cab):
			if equip_types.get(record_name) == "psu":
				psu_name = record_name
			elif equip_types.get(record_name) == "relay":
				relay_name = record_name
		# A switch of its own on the shell: the home loop's already feeds
		# the pump relay, and a contact takes one line.
		var cab_switch := mount_new("float_switch", "supply_tank", 0.5, 1.2) as SimFloatSwitch
		if cab_switch == null or connect_equipment(cab_switch.comp_name, "contact", t + "1", "in") != "":
			problems.append("field wire to cabinet terminal refused")
		if connect_equipment(t + "1", "out", plc_name, "di_0", [], false) != "":
			problems.append("internal terminal->PLC wire refused")
		if connect_equipment(psu_name, "dc_out", plc_name, "power", [], false) != "":
			problems.append("PSU->PLC power wire refused")
		if cab_plc.set_program([{"coil": "do_0", "logic": [[{"ref": "di_0"}]]}]) != "":
			problems.append("PLC refused a mirror rung")
		if connect_equipment(plc_name, "do_0", t + "2", "in", [], false) != "":
			problems.append("internal PLC->terminal wire refused")
		cab_switch.set_band(150.0, 150.0)  # level < 150: contact closed for sure
		for _i in 10:
			sim.tick()
		# The PSU has no 480 V feed yet: the whole rack must be dead.
		if (sim.get_component(t + "2") as SimTerminal).t_out.value > 0.5:
			problems.append("unpowered PLC drove an output")
		# Through a waypoint: the save/load round trip below checks that
		# a routed line keeps its corners (the home loop has none of its
		# own).
		if connect_equipment("plant_mains", free_way("plant_mains"), psu_name, "ac_in",
				[Vector3(0.0, 0.3, 3.0)]) != "":
			problems.append("mains to cabinet PSU refused")
		for _i in 10:
			sim.tick()
		if (sim.get_component(t + "2") as SimTerminal).t_out.value < 0.5:
			problems.append("signal failed to traverse terminal -> PLC -> terminal")
		# And through the interposing relay.
		if connect_equipment(t + "1", "out", relay_name, "coil", [], false) != "":
			problems.append("terminal -> relay coil wire refused")
		if connect_equipment(relay_name, "contact", t + "3", "in", [], false) != "":
			problems.append("relay contact -> terminal wire refused")
		for _i in 10:
			sim.tick()
		if (sim.get_component(t + "3") as SimTerminal).t_out.value < 0.5:
			problems.append("signal failed to traverse the interposing relay")
		# The switch stays: the save/load check below expects the loop alive.
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
	if cab != "" and roundtrip:
		var plc_after := sim.get_component(cabinet_plc(cab)) as SimPLC
		if plc_after == null or plc_after.program.size() != 1:
			problems.append("cabinet PLC program lost in save/load")
		else:
			(sim.get_component("level_switch") as SimFloatSwitch).set_band(150.0, 150.0)
			for _i in 10:
				sim.tick()
			if (sim.get_component("%s_m6_t2" % cab) as SimTerminal).t_out.value < 0.5:
				problems.append("cabinet loop dead after save/load")
			(sim.get_component("level_switch") as SimFloatSwitch).set_band(40.0, 80.0)
		if not remove_cabinet(cab):
			problems.append("cabinet removal failed")
	if problems.is_empty():
		print("[flowstate] build-api exercise OK — gauge %.1f kPa, %d components, %d wires"
			% [reading, sim.components.size(), sim.wires.size()])
	else:
		push_warning("[flowstate] build-api exercise FAILED: " + "; ".join(problems))


## An open end's stream carries further as its flow rises, so the vessel
## it lands in is looked for again four times a second. Safe here: the
## scan thread is collected before any node's _process.
var _catch_t := 0.0


## The filling line is derived again once a frame after any change to
## it (VialLine): links, seats and vial sizes follow where parts stand.
var _vial_line_dirty := false


func _process(delta: float) -> void:
	if _vial_line_dirty:
		_vial_line_dirty = false
		VialLine.sync(self)
	_catch_t -= delta
	if _catch_t <= 0.0:
		_catch_t = 0.25
		_sync_catches()


func _physics_process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= SIM_DT:
		_scans_due += 1
		_accumulator -= SIM_DT
	if _scans_due > MAX_SCANS_PER_FRAME:
		# A hitch is not repaid with a longer hitch: the sim slips behind
		# the clock by the scans it drops.
		_scans_due = MAX_SCANS_PER_FRAME
	if not threaded_scan:
		_run_scans(_scans_due)
		_scans_due = 0
	elif not _scan_hooked:
		_scan_hooked = true
		RenderingServer.frame_pre_draw.connect(_start_scans)
		RenderingServer.frame_post_draw.connect(_join_if_done)
		get_tree().process_frame.connect(_finish_scans)
	if _revalidate_in > 0:
		_revalidate_in -= 1
		if _revalidate_in == 0:
			_finish_scans()  # the sweep repaints runs off the kernel's flows
			_revalidate_supports()
	if _support_exercise_phase > 0:
		_support_exercise_wait -= 1
		if _support_exercise_wait <= 0:
			_exercise_supports()


## The kernel budget is 50 ms per scan at 20 Hz, and the hydraulic
## solve is the part that grows with the plant, so say once what a
## scan actually costs on this plant.
func _note_cost(elapsed_us: int) -> void:
	if _cost_ticks < 0:
		return
	_cost_ticks += 1
	_cost_total_us += elapsed_us
	_cost_solve_ms += sim.solve_ms
	_cost_newton_ms += sim.newton_ms
	_cost_signal_ms += sim.signal_ms
	_cost_components_ms += sim.components_ms
	_cost_historian_ms += sim.historian_ms
	var net := sim.network()
	_cost_iterations += net.iterations if net != null else 0
	if _cost_ticks >= 150:
		print("[flowstate] scan phases: signals %.2f ms, components %.2f ms, historian %.2f ms (%d tags)" % [
			_cost_signal_ms / _cost_ticks, _cost_components_ms / _cost_ticks,
			_cost_historian_ms / _cost_ticks, historian.active_tags().size()])
		print("[flowstate] kernel cost: %.2f ms/scan; hydraulic pass %.2f ms, of which the Newton solve %.2f ms (%d nodes, %d branches, band %d, %.1f iterations a scan, residual %.6f L/s)" % [
			_cost_total_us / 1000.0 / _cost_ticks, _cost_solve_ms / _cost_ticks,
			_cost_newton_ms / _cost_ticks,
			net.node_count() if net != null else 0,
			net.branches.size() if net != null else 0,
			net.bandwidth() if net != null else 0,
			float(_cost_iterations) / _cost_ticks,
			net.residual_lps if net != null else 0.0])
		_cost_ticks = -1


func _new_graph() -> void:
	sim = Simulation.new(SIM_DT)
	historian = sim.attach_historian(SimHistorian.new())


## ---- equipment lifecycle ------------------------------------------------

## Types whose nozzles stand at the placement height: a vessel on a
## deck really does stand above one at grade. The elevation is
## re-derived from the saved position on load, and from the new spot
## when the equipment is moved.
##
## One rule, not a list: every record with an elevation_m property
## takes it from where it stands, at placement, on a move, and on a
## load (which places again). What "where it stands" means per type is
## the one thing tabulated: a vessel, header or drain stands on its
## base; an inline device (a pump, a valve, a regulator) stands its
## nozzles a fixed height above its base; a cap stands at its line.
const NOZZLE_ELEVATION_TYPES: Array[String] = ["pump", "metering_pump", "valve", "block_valve",
	"ball_valve", "needle_valve", "solenoid_valve", "regulator", "gauge_line"]


## The height above grade a record of this type reckons its pressures
## at, standing with its base at base_y (plant-local).
func _elevation_for(type_id: String, view: Node3D, base_y: float) -> float:
	if type_id == "cap" and view is CapView:
		return base_y + (view as CapView).line_y
	if type_id == "fill_needle":
		return base_y + FillNeedleView.TIP_Y   # it vents at its tip
	if type_id in NOZZLE_ELEVATION_TYPES:
		var anchor: Variant = PlantFactory.PORT_ANCHORS.get(type_id, {}).get("inlet")
		if anchor is Dictionary:
			return base_y + ((anchor as Dictionary)["pos"] as Vector3).y
		if anchor is Vector3:
			return base_y + (anchor as Vector3).y
	return base_y


## Apply the rule above to a record that has just been placed or moved.
## A saved elevation in params wins on a load, so a plant reloads as
## it was saved even if the tabulated height of a type has changed.
func _apply_elevation(record: SimComponent, type_id: String, view: Node3D, base_y: float,
		params: Dictionary) -> void:
	if record.get("elevation_m") == null:
		return
	var value: float = float(params["elevation_m"]) if params.has("elevation_m") \
		else snappedf(_elevation_for(type_id, view, base_y), 0.01)
	record.set("elevation_m", value)


func place(type_id: String, name_: String, params: Dictionary,
		world_pos: Vector3, rot_y: float, is_protected: bool) -> SimComponent:
	checkpoint()
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	if record == null:
		return null
	sim.register_with_historian(record)
	var view := PlantFactory.make_view(type_id, record)
	view.position = to_local(world_pos) + Vector3(0, PlantFactory.Y_OFFSETS.get(type_id, 0.0), 0)
	view.rotation.y = rot_y
	add_child(view)
	match type_id:
		"tank":
			(record as SimTank).open_top = bool(params.get("open_top", false))
			(view as TankView).setup(record as SimTank)
		"pump":
			(view as PumpView).setup(record as SimPump)
		"orifice":
			(view as OrificeView).setup(record as SimOrifice)
		"needle_valve":
			(view as NeedleValveView).setup(record as SimNeedleValve)
		"ball_valve":
			(view as BallValveView).setup(record as SimBallValve)
		"solenoid_valve":
			(view as SolenoidValveView).setup(record as SimSolenoidValve)
		"metering_pump":
			(view as MeteringPumpView).setup(record as SimMeteringPump)
		"regulator":
			(view as RegulatorView).setup(record as SimRegulator)
		"rotameter":
			(view as RotameterView).setup(record as SimRotameter)
		"relay":
			(view as RelayView).setup(record as SimRelay)
		"hmi_trend":
			(view as TrendScreenView).setup_trend(record as SimTrendScreen, self)
		"float_switch":
			(view as FloatSwitchView).setup(record as SimFloatSwitch)
		"gauge_level", "gauge_flow", "gauge_dp", "gauge_press", \
		"gauge_temp", "gauge_conc", "gauge_line":
			(view as GaugeView).setup(record as SimGauge)
		"column":
			(view as ColumnView).setup(record as SimColumn)
		"valve":
			(view as ControlValveView).setup(record as SimControlValve)
		"block_valve":
			(view as BlockValveView).setup(record as SimBlockValve)
		"controller":
			(view as PIDView).setup(record as SimPID)
		"mains":
			(view as MainsView).setup(record as SimMainsFeed)
		"tee_split", "tee_mix":
			(view as TeeView).setup(record as SimTee)
		"cap":
			(view as CapView).setup(record as SimCap, float(params.get("line_y", 0.35)))
		"psu":
			(view as PsuView).setup(record as SimPowerSupply)
		"source":
			(view as SourceView).setup(record as SimSource)
		"drain":
			(view as DrainView).setup(record as SimDrain)
		"reactor":
			(view as ReactorView).setup(record as SimReactor)
		"centrifuge":
			(view as CentrifugeView).setup(record as SimCentrifuge)
		"hx":
			(view as HeatExchangerView).setup(record as SimHeatExchanger)
		"steamgen":
			(view as SteamGenView).setup(record as SimSteamGen)
		"vaclock":
			(view as VacLockView).setup(record as SimVacuumLock)
		"vialfill":
			(view as VialFillerView).setup(record as SimVialFiller)
		"crystallizer":
			(view as CrystallizerView).setup(record as SimCrystallizer)
		"dryer":
			(view as DryerView).setup(record as SimDryer)
		"still":
			(view as StillView).setup(record as SimStill)
		"air_cascade":
			(view as AsepticSuite).setup(record as SimAirCascade)
	if view is VialPartView:
		(view as VialPartView).setup_record(record)
		_vial_line_dirty = true
	# Where it stands is where it reckons its pressures: the one
	# elevation rule, for every record that has one.
	_apply_elevation(record, type_id, view, to_local(world_pos).y, params)
	# One mesh per look for the furniture; the port fittings come after
	# and stay separate, since the plant colours and grabs them.
	MeshMerge.merge_view(view)
	if type_id == "mains":
		PlantFactory.attach_port_markers(view, record, type_id,
			PlantFactory.mains_anchors((record as SimMainsFeed).ways))
	elif type_id == "cap":
		PlantFactory.attach_port_markers(view, record, type_id,
			PlantFactory.cap_anchors((view as CapView).line_y))
	elif type_id == "vial_track":   # its drive, and so its fittings, at its outfeed end
		PlantFactory.attach_port_markers(view, record, type_id,
			VialTrackView.anchors((record as SimVialTrack).length_m))
	elif type_id != "tank":  # a tank's nozzles are its own
		PlantFactory.attach_port_markers(view, record, type_id)
	views[record.comp_name] = view
	equip_types[record.comp_name] = type_id
	if is_protected:
		protected[record.comp_name] = true
	return record


func place_new(type_id: String, world_pos: Vector3, rot_y: float) -> SimComponent:
	return place(type_id, sim.unique_name(type_id), {}, world_pos, rot_y, false)


## ---- instruments on vessels ------------------------------------------------
## A level switch or level transmitter is not placed on the floor and
## piped to a "level" nozzle: it is
## mounted on a vessel's shell, and the plant lands the kernel wire
## from the vessel's internal tap for it. frac is the height up the
## shell, angle the bearing round it.

func mount_instrument(type_id: String, name_: String, params: Dictionary,
		host_name: String, frac: float, angle: float, is_protected: bool) -> SimComponent:
	checkpoint()
	var host_view := views.get(host_name) as TankView
	var host := sim.get_component(host_name) as SimTank
	if host_view == null or host == null or not PlantFactory.MOUNTABLE.has(type_id):
		return null
	params = params.duplicate()
	if type_id == "gauge_level" and not params.has("liters_per_meter"):
		# A transmitter is ranged to the vessel it is on.
		params["liters_per_meter"] = host.cross_section_m2 * 1000.0
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	if record == null:
		return null
	sim.register_with_historian(record)
	var view := PlantFactory.make_view(type_id, record)
	if type_id == "float_switch":
		(view as FloatSwitchView).setup(record as SimFloatSwitch, true)
	else:
		(view as GaugeView).setup(record as SimGauge, true)
	MeshMerge.merge_view(view)
	host_view.mount(view, frac, angle)
	var skip: Array[String] = [str(PlantFactory.MOUNTED_INPUT[type_id])]
	PlantFactory.attach_port_markers(view, record, type_id,
		PlantFactory.MOUNTED_ANCHORS.get(type_id, {}), skip)
	views[record.comp_name] = view
	equip_types[record.comp_name] = type_id
	mounted[record.comp_name] = {"host": host_name, "frac": frac, "angle": angle}
	if is_protected:
		protected[record.comp_name] = true
	connect_equipment(host_name, str(PlantFactory.MOUNTED_HOST_PORT[type_id]), record.comp_name,
		str(PlantFactory.MOUNTED_INPUT[type_id]), [], false)
	return record


## Mount with default sizing: a switch trips around the height it is
## mounted at, a transmitter is ranged to the vessel.
func mount_new(type_id: String, host_name: String, frac: float, angle: float) -> SimComponent:
	var params := {}
	var host := sim.get_component(host_name) as SimTank
	if type_id == "float_switch" and host != null:
		var trip := host.capacity_l * clampf(frac, 0.04, 0.97)
		params = {"low_l": maxf(trip - 0.15 * host.capacity_l, 0.0),
			"high_l": minf(trip + 0.15 * host.capacity_l, host.capacity_l)}
	return mount_instrument(type_id, sim.unique_name(type_id), params,
		host_name, frac, angle, false)


## ---- control cabinets -----------------------------------------------------
## A cabinet starts as an EMPTY enclosure with bare DIN rails. The
## cabinet editor places modules — PSU, one PLC CPU, I/O cards (which
## gate usable PLC channels), relays, terminal strips — each backed by
## real kernel records, and lands internal wires as hidden kernel
## wires. The 3D interior renders the layout; field wiring uses the
## flank markers terminal strips and PSUs provide.

func unique_cabinet_name() -> String:
	var index := 1
	while cabinets.has("cabinet_%d" % index):
		index += 1
	return "cabinet_%d" % index


func place_cabinet(name_: String, world_pos: Vector3, rot_y: float) -> bool:
	checkpoint()
	if cabinets.has(name_):
		return false
	var view := CabinetView.new()
	view.position = to_local(world_pos)
	view.rotation.y = rot_y
	add_child(view)
	view.setup(name_)
	MeshMerge.merge_view(view)
	view.config_cb = _configure_cabinet
	cabinets[name_] = {"node": view, "modules": [], "next_id": 1}
	return true


## Add one module to a rail. Returns "" or the refusal reason.
## forced_id / forced_bank replay a saved layout exactly.
func cabinet_add_module(cab: String, type_id: String, rail: int, slot: int,
		forced_id: String = "", forced_bank: int = -1) -> String:
	checkpoint()
	if not cabinets.has(cab):
		return "no such cabinet"
	if not CabinetSpec.MODULES.has(type_id):
		return "unknown module type"
	var entry: Dictionary = cabinets[cab]
	var modules: Array = entry["modules"]
	if not CabinetSpec.span_free(modules, rail, slot, CabinetSpec.units_of(type_id)):
		return "doesn't fit there"
	if type_id == "plc" and cabinet_plc(cab) != "":
		return "one CPU per cabinet"
	var bank := -1
	if CabinetSpec.CARD_FAMILY.has(type_id):
		if cabinet_plc(cab) == "":
			return "place a PLC CPU first"
		bank = forced_bank if forced_bank >= 0 else _free_bank(cab, type_id)
		if bank < 0:
			return "no channel capacity left for that card"
	var id := forced_id
	if id == "":
		id = "m%d" % int(entry["next_id"])
	entry["next_id"] = maxi(int(entry["next_id"]), int(id.trim_prefix("m")) + 1)
	var base := "%s_%s" % [cab, id]
	var records: Array[String] = []
	match type_id:
		"psu":
			records.append(_add_cab_record(cab, "psu", base, {}))
		"plc":
			records.append(_add_cab_record(cab, "plc", base,
				{"di": 16, "do": 16, "ai": 8, "ao": 8}))
		"relay":
			records.append(_add_cab_record(cab, "relay", base, {}))
		"tb8d":
			for i in range(8):
				records.append(_add_cab_record(cab, "terminal", "%s_t%d" % [base, i + 1],
					{"kind": "discrete"}))
		"tb4a":
			for i in range(4):
				records.append(_add_cab_record(cab, "terminal", "%s_t%d" % [base, i + 1],
					{"kind": "analog"}))
	modules.append({"id": id, "type": type_id, "rail": rail, "slot": slot,
		"bank": bank, "records": records})
	_sync_cabinet(cab)
	return ""


func _add_cab_record(cab: String, type_id: String, name_: String, params: Dictionary) -> String:
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	sim.register_with_historian(record)
	views[name_] = (cabinets[cab] as Dictionary)["node"]
	equip_types[name_] = type_id
	protected[name_] = true
	member_of[name_] = cab
	return name_


## Lowest bank of the card's family not already claimed in this cabinet.
func _free_bank(cab: String, type_id: String) -> int:
	var family := str(CabinetSpec.CARD_FAMILY[type_id])
	var width := int(CabinetSpec.CARD_CHANNELS[type_id])
	var capacity := {"di": 16, "do": 16, "ai": 8, "ao": 8}[family] as int
	var taken := {}
	for module_v: Variant in (cabinets[cab] as Dictionary)["modules"]:
		var module := module_v as Dictionary
		if CabinetSpec.CARD_FAMILY.get(str(module["type"])) == family:
			taken[int(module["bank"])] = true
	for bank in range(capacity / width):
		if not taken.has(bank):
			return bank
	return -1


func cabinet_remove_module(cab: String, module_id: String) -> bool:
	checkpoint()
	if not cabinets.has(cab):
		return false
	var entry: Dictionary = cabinets[cab]
	var modules: Array = entry["modules"]
	for i in range(modules.size()):
		var module := modules[i] as Dictionary
		if str(module["id"]) != module_id:
			continue
		if CabinetSpec.CARD_FAMILY.has(str(module["type"])):
			_drop_card_wires(cab, module)
		for record_name: String in module["records"]:
			sim.remove_component(record_name)
			_prune_wires_of(record_name)
			views.erase(record_name)
			equip_types.erase(record_name)
			protected.erase(record_name)
			member_of.erase(record_name)
		modules.remove_at(i)
		_sync_cabinet(cab)
		return true
	return false


## Removing an I/O card takes its channels' wires with it.
func _drop_card_wires(cab: String, module: Dictionary) -> void:
	var plc_name := cabinet_plc(cab)
	if plc_name == "":
		return
	var family := str(CabinetSpec.CARD_FAMILY[str(module["type"])])
	var width := int(CabinetSpec.CARD_CHANNELS[str(module["type"])])
	var channels := {}
	for i in range(width):
		channels["%s_%d" % [family, int(module["bank"]) * width + i]] = true
	for visual in _wire_visuals.duplicate():
		var hits: bool = (str(visual["a"]) == plc_name and channels.has(str(visual["a_port"]))) \
			or (str(visual["b"]) == plc_name and channels.has(str(visual["b_port"])))
		if hits:
			remove_internal_wire(visual)


func _prune_wires_of(member: String) -> void:
	var keep: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["a"] == member or visual["b"] == member:
			if visual["node"] != null:
				(visual["node"] as Node).queue_free()
		else:
			keep.append(visual)
	_wire_visuals = keep


func remove_cabinet(name_: String) -> bool:
	checkpoint()
	if not cabinets.has(name_):
		return false
	var entry: Dictionary = cabinets[name_]
	for module_v: Variant in (entry["modules"] as Array).duplicate():
		var module := module_v as Dictionary
		for record_name: String in module["records"]:
			sim.remove_component(record_name)
			_prune_wires_of(record_name)
			views.erase(record_name)
			equip_types.erase(record_name)
			protected.erase(record_name)
			member_of.erase(record_name)
	(entry["node"] as Node).queue_free()
	cabinets.erase(name_)
	_schedule_revalidate()
	return true


## X on a junction box or a control station: its records go, every wire on them, and any multicore that
## carried its circuits — the cable has nothing left to carry.
func remove_junction_box(name_: String) -> bool:
	checkpoint()
	if not junction_boxes.has(name_):
		return false
	_remove_enclosure_records((junction_boxes[name_] as Dictionary)["records"] as Array, name_)
	((junction_boxes[name_] as Dictionary)["node"] as Node).queue_free()
	junction_boxes.erase(name_)
	_schedule_revalidate()
	return true


func remove_control_station(name_: String) -> bool:
	checkpoint()
	if not control_stations.has(name_):
		return false
	_remove_enclosure_records((control_stations[name_] as Dictionary)["records"] as Array, name_)
	((control_stations[name_] as Dictionary)["node"] as Node).queue_free()
	control_stations.erase(name_)
	_schedule_revalidate()
	return true


func _remove_enclosure_records(records: Array, enclosure: String) -> void:
	for record_v: Variant in records.duplicate():
		var record_name := str(record_v)
		sim.remove_component(record_name)
		_prune_wires_of(record_name)
		views.erase(record_name)
		equip_types.erase(record_name)
		protected.erase(record_name)
		member_of.erase(record_name)
	for label: String in runs.keys():
		var entry: Dictionary = runs[label]
		if not entry.has("circuits"):
			continue
		for pair_v: Variant in entry["circuits"]:
			var pair := pair_v as Array
			if str(pair[0]).begins_with(enclosure + "_") or str(pair[2]).begins_with(enclosure + "_"):
				remove_placed_run(entry["node"] as PipeView)
				break


## A multicore lights while any circuit in it is live. Ports are
## looked up by name at read time, so the same getter serves a cable
## laid now and one rebuilt from a save before its wires reload.
func _multicore_getter(pairs: Array) -> Callable:
	return func() -> float:
		var count := 0.0
		for pair_v: Variant in pairs:
			var pair := pair_v as Array
			var src := sim.get_component(str(pair[0]))
			if src == null:
				continue
			var port: SimOutputPort = src.outputs.get(str(pair[1]))
			if port != null and port.value > 0.5:
				count += 1.0
		return count


## ---- cabinet queries (editor, ladder, port menu) --------------------------

func cabinet_plc(cab: String) -> String:
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		var module := module_v as Dictionary
		if str(module["type"]) == "plc":
			return str((module["records"] as Array)[0])
	return ""


## Channels the placed I/O cards back, per family: {"di": [0,1,...]}.
func cabinet_backed_channels(cab: String) -> Dictionary:
	var out := {"di": [], "do": [], "ai": [], "ao": []}
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		var module := module_v as Dictionary
		var type_id := str(module["type"])
		if not CabinetSpec.CARD_FAMILY.has(type_id):
			continue
		var family := str(CabinetSpec.CARD_FAMILY[type_id])
		var width := int(CabinetSpec.CARD_CHANNELS[type_id])
		for i in range(width):
			(out[family] as Array).append(int(module["bank"]) * width + i)
	for family: String in out:
		(out[family] as Array).sort()
	return out


## Field-wirable member records: terminals and PSUs.
func cabinet_field_records(cab: String) -> Array[String]:
	var out: Array[String] = []
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		var module := module_v as Dictionary
		if str(module["type"]) in ["tb8d", "tb4a", "psu"]:
			for record_name: String in module["records"]:
				out.append(record_name)
	return out


## All member records, for the editor's wiring panel.
func cabinet_all_records(cab: String) -> Array[String]:
	var out: Array[String] = []
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		for record_name: String in (module_v as Dictionary)["records"]:
			out.append(record_name)
	return out


## ---- cabinet sync: flank markers + 3D interior ----------------------------

func _sync_cabinet(cab: String) -> void:
	var entry: Dictionary = cabinets[cab]
	var view := entry["node"] as CabinetView
	var markers: Dictionary = view.get_meta("port_markers", {})
	for key: String in markers:
		var marker := markers[key] as Node
		if is_instance_valid(marker):
			marker.queue_free()
	view.set_meta("port_markers", {})
	# The fittings' meshes were merged under the view; they go with the bodies.
	for child in view.get_children():
		if child.has_meta("merged_markers"):
			view.remove_child(child)
			child.queue_free()
	# Flank fittings run down each side in rows; a cabinet with more
	# terminals than one column holds starts a second column further
	# along the flank rather than putting a fitting below the floor.
	var y := 1.72
	var z := 0.12
	for module_v: Variant in entry["modules"]:
		var module := module_v as Dictionary
		var type_id := str(module["type"])
		for record_name: String in module["records"]:
			var record := sim.get_component(record_name)
			if y < 0.25:
				y = 1.72
				z += 0.16
			if record is SimTerminal:
				PlantFactory.attach_port_markers(view, record, "terminal",
					{"in": Vector3(-0.72, y, z), "out": Vector3(0.72, y, z)})
				y -= 0.115
			elif record is SimPowerSupply:
				PlantFactory.attach_port_markers(view, record, "psu",
					{"ac_in": Vector3(-0.72, y, z), "dc_out": Vector3(0.72, y, z)})
				y -= 0.115
	view.set_layout(entry["modules"], _cabinet_wire_specs(cab))
	var relays: Array[SimRelay] = []
	for module_v: Variant in entry["modules"]:
		for record_name: String in (module_v as Dictionary)["records"]:
			var record := sim.get_component(record_name)
			if record is SimRelay:
				relays.append(record as SimRelay)
	view.set_relays(relays)
	_schedule_revalidate()


func _cabinet_wire_specs(cab: String) -> Array:
	var specs: Array = []
	var members := {}
	for record_name in cabinet_all_records(cab):
		members[record_name] = true
	for visual in _wire_visuals:
		if not (members.has(str(visual["a"])) and members.has(str(visual["b"]))):
			continue
		var a := _cabinet_port_pos(cab, str(visual["a"]))
		var b := _cabinet_port_pos(cab, str(visual["b"]))
		var src := sim.get_component(str(visual["a"]))
		var port: SimOutputPort = src.outputs.get(str(visual["a_port"])) if src != null else null
		var color: Color = PlantFactory.KIND_COLORS.get(port.kind, Color.GRAY) if port != null \
			else Color.GRAY
		specs.append({"a": a, "b": b, "color": color})
	return specs


func _cabinet_port_pos(cab: String, record_name: String) -> Vector3:
	for module_v: Variant in (cabinets[cab] as Dictionary)["modules"]:
		var module := module_v as Dictionary
		var records: Array = module["records"]
		var index := records.find(record_name)
		if index < 0:
			continue
		var units := CabinetSpec.units_of(str(module["type"]))
		var center := CabinetSpec.module_center(int(module["rail"]), int(module["slot"]), units)
		var width := units * CabinetSpec.UNIT_W - 0.012
		if records.size() > 1:  # terminal within a strip
			center.x += -width / 2.0 + (index + 0.5) * width / records.size()
		return center + Vector3(0, -CabinetSpec.MODULE_H / 2.0, 0)
	return Vector3.ZERO


func _configure_cabinet(view: CabinetView) -> void:
	if cabinet_editor != null:
		cabinet_editor.open(self, view.cabinet_name)


## Drop one internal (hidden) wire — the schematic panel's remove.
func remove_internal_wire(visual: Dictionary) -> void:
	checkpoint()
	_disconnect_visual(visual)
	_wire_visuals.erase(visual)


## ---- tank configuration ---------------------------------------------------

func resize_tank(name_: String, height_m: float, diameter_m: float) -> void:
	checkpoint()
	var record := sim.get_component(name_) as SimTank
	var view := views.get(name_) as TankView
	if record == null or view == null:
		return
	record.set_size(height_m, diameter_m)
	view.rebuild()
	MeshMerge.merge_view(view)
	refresh_wires_of(name_)
	# Instruments on the shell moved with it; their cables follow, and a
	# level transmitter is ranged again to the new cross-section, or it
	# reads the wrong kPa.
	for inst_name: String in mounted:
		if str((mounted[inst_name] as Dictionary)["host"]) == name_:
			var inst := sim.get_component(inst_name)
			if inst is SimGauge and (inst as SimGauge).kind == "level_kpa":
				(inst as SimGauge).liters_per_meter = record.cross_section_m2 * 1000.0
			refresh_wires_of(inst_name)
	_schedule_revalidate()


## Rebuild the pipe visuals touching one record — after its nozzles
## moved or its vessel was resized.
func refresh_wires_of(name_: String) -> void:
	checkpoint()
	preview_wires_of(name_)
	_schedule_revalidate()


## The same re-lay without the plant-wide sweep after it: a nozzle
## being carried has its lines follow it a few times a second, and the
## sweep waits for the weld.
func preview_wires_of(name_: String) -> void:
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		if str(visual["a"]) != name_ and str(visual["b"]) != name_:
			continue
		_refresh_visual(visual)


## Lay one run again from its record: its lane is chosen afresh
## against everything else as it stands now.
func _refresh_visual(visual: Dictionary) -> void:
	if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
		print("[relay] %s.%s -> %s.%s" % [visual["a"], visual["a_port"], visual["b"], visual["b_port"]])
	(visual["node"] as Node).queue_free()
	var before: Array = visual.get("path", [])
	visual["path"] = []  # not a collision with its own old route
	visual["base_path"] = []
	var pipe := _build_pipe(str(visual["a"]), str(visual["a_port"]),
		str(visual["b"]), str(visual["b_port"]), visual["waypoints"], -1, int(visual.get("lane", 0)),
		int(visual.get("order", ORDER_ALL)), bool(visual.get("fixed", false)), int(visual.get("dn", 50)))
	visual["node"] = pipe
	visual["lane"] = int(pipe.get_meta("lane", 0))
	visual["path"] = pipe.get_meta("path", [])
	visual.erase("box")   # computed again from the new path when next asked
	visual["corners"] = pipe.get_meta("corners", [])
	visual["base_path"] = pipe.get_meta("base_path", [])
	# A re-lay that changed nothing: whatever still crosses this run is
	# a crossing no lane or bridge of it can fix, and the sweep must not
	# re-lay it again for that reason until something round it moves.
	visual["same_relay"] = _same_path(visual["path"], before)
	visual["relays"] = int(visual.get("relays", 0)) + 1
	if str(visual.get("color", "")) != "":
		pipe.apply_service(Color.html(str(visual["color"])), str(visual.get("label", "")))
	if str(visual.get("fitting", "")) != "":
		pipe.set_fitting(str(visual["fitting"]))
	_sync_line_resistance(visual)


## A line's resistance follows its length and size, by one rule applied wherever a line is laid — placed,
## re-laid, stretched by a move, slid, cut, resized or loaded: the
## pipe as drawn, face to face, its length and the right angles it
## turns through, through SimHydraulics.pipe_k at its bore. Nothing
## sets a line's resistance by hand; a line that must pass more is a
## bigger line.
func _sync_line_resistance(visual: Dictionary) -> void:
	if visual["node"] == null:
		return
	var wire := sim.find_wire(sim.get_component(str(visual["a"])), str(visual["a_port"]),
		sim.get_component(str(visual["b"])), str(visual["b_port"]))
	if wire == null or not wire.is_material():
		return
	var geometry := line_geometry(_visual_path(visual))
	sim.set_wire_resistance(wire, SimHydraulics.pipe_k(float(geometry["length"]),
		int(visual.get("dn", 50)), float(geometry["bends"])))


## A drawn path's length in metres and the right angles it turns
## through in all (a 45-degree corner is half of one).
static func line_geometry(path: Array[Vector3]) -> Dictionary:
	var length := 0.0
	var turned := 0.0
	var last := Vector3.ZERO
	for i in range(1, path.size()):
		var seg := path[i] - path[i - 1]
		var l := seg.length()
		if l < 1e-4:
			continue
		length += l
		var dir := seg / l
		if last != Vector3.ZERO:
			turned += last.angle_to(dir)
		last = dir
	return {"length": length, "bends": turned / (PI / 2.0)}


## Lines whose kernel resistance is not what their drawn length and
## size make it: the check that the rule above holds everywhere, for
## the headless smoke. Empty is right.
func resistance_report() -> PackedStringArray:
	var out := PackedStringArray()
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		var wire := sim.find_wire(sim.get_component(str(visual["a"])), str(visual["a_port"]),
			sim.get_component(str(visual["b"])), str(visual["b_port"]))
		if wire == null or not wire.is_material():
			continue
		var geometry := line_geometry(_visual_path(visual))
		var want := SimHydraulics.pipe_k(float(geometry["length"]), int(visual.get("dn", 50)), float(geometry["bends"]))
		if absf(wire.k_pa_per_lps2 - want) > 1e-6 * maxf(want, 1.0):
			out.append("%s.%s -> %s.%s: k %.4g, its %.2f m at DN%d make it %.4g" % [visual["a"], visual["a_port"],
				visual["b"], visual["b_port"], wire.k_pa_per_lps2, float(geometry["length"]),
				int(visual.get("dn", 50)), want])
	return out


## Where two runs would pass through each other — crossings, not the
## parallel stretches the lanes see to. A run being laid hops over
## each one. Each entry: the segment of
## `path` it is on, how far along it, and the other run's top and
## bottom there. Risers cannot hop and the first and last half metre
## are the fittings' own.
func _crossings(path: Array[Vector3], radius: float, skip: Dictionary, ignore: Array,
		order: int = ORDER_ALL, margin: float = 0.03, targets: Array = []) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if path.size() < 2:
		return found
	var others: Array = targets if not targets.is_empty() else _crossing_targets(skip, ignore, order)
	var start := path[0]
	var finish := path[path.size() - 1]
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var d := b - a
		var length := d.length()
		if length < 0.4:
			continue
		var dir := d / length
		var seg_box := AABB(a, Vector3.ZERO).expand(b).grow(0.3)
		for other in others:
			if not seg_box.intersects(other[2]):
				continue
			var other_path: Array = other[0]
			var other_r: float = other[1]
			for j in range(other_path.size() - 1):
				var c: Vector3 = other_path[j]
				var e: Vector3 = other_path[j + 1]
				if not seg_box.intersects(AABB(c, Vector3.ZERO).expand(e)):
					continue
				if dir.cross((e - c).normalized()).length() < 0.15:
					continue  # parallel, or within nine degrees of it: a stretch, the lanes' business
				var hit := _segment_closest(a, b, c, e)
				if float(hit[0]) > radius + other_r + margin:
					continue
				var at: float = hit[1]
				var p := a + dir * at
				if p.distance_to(start) < 0.4 or p.distance_to(finish) < 0.4:
					continue
				var on_other: Vector3 = hit[2]
				var other_start: Vector3 = other_path[0]
				var other_finish: Vector3 = other_path[other_path.size() - 1]
				if bool(other[5]):
					if on_other.distance_to(other_start) >= 0.45 and on_other.distance_to(other_finish) >= 0.45:
						continue  # the later run can move there, so it will
				# At the other run's own fitting, a bridge may stand inside
				# that fitting's machine; anywhere else the machine is solid.
				var near_fitting := on_other.distance_to(other_start) < PipeRoute.STUB_CLEAR \
					or on_other.distance_to(other_finish) < PipeRoute.STUB_CLEAR
				var other_dir := (e - c).normalized()
				var normal := dir.cross(other_dir).normalized()
				var lateral := 0.0
				if absf(normal.y) < 0.7:
					lateral = (on_other - p).dot(Vector3(normal.x, 0.0, normal.z).normalized())
				found.append({"seg": i, "at": at, "top": on_other.y + other_r, "bottom": on_other.y - other_r,
					"other": other[3], "other_r": other_r, "other_dir": other_dir, "lateral": lateral,
					"ends": other[4] if near_fitting else []})
	return found


## The runs a path is checked against: every earlier run from another
## source, as rendered, with its box; built once per lay.
func _crossing_targets(skip: Dictionary, ignore: Array, order: int) -> Array:
	var others: Array = []
	for visual in _wire_visuals:
		if visual == skip or visual["node"] == null:
			continue
		# A later run yields to this one — except where it cannot move at
		# all, its first and last half metre off the fitting; a crossing
		# there is this run's to fix, and it is marked so only those count.
		var later := int(visual.get("order", -1)) >= order
		if not ignore.is_empty() and str(visual["a"]) == str(ignore[0]):
			continue  # a bundle-mate: cables in one tray lie together, they do not hop each other
		var other_path: Array = visual.get("path", [])
		if other_path.size() >= 2:
			others.append([other_path, (visual["node"] as PipeView).radius(), _path_box(other_path),
				"%s.%s -> %s.%s" % [visual["a"], visual["a_port"], visual["b"], visual["b_port"]],
				[str(visual["a"]), str(visual["b"])], later])
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		if (entry["node"] as PipeView).style() == "tray":
			continue  # a conduit lands on a tray, it does not hop it
		var run_path := PipeRoute.lay(entry["points"])
		if run_path.size() >= 2:
			others.append([run_path, (entry["node"] as PipeView).radius(), _path_box(run_path), name_, [], false])
	return others


## Closest approach of segment ab to segment ce: [distance, metres
## along ab, the point on ce].
static func _segment_closest(a: Vector3, b: Vector3, c: Vector3, e: Vector3) -> Array:
	var d1 := b - a
	var d2 := e - c
	var r := a - c
	var aa := d1.dot(d1)
	var ee := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if aa <= 1e-9 and ee <= 1e-9:
		return [a.distance_to(c), 0.0, c]
	if aa <= 1e-9:
		t = clampf(f / ee, 0.0, 1.0)
	else:
		var cc := d1.dot(r)
		if ee <= 1e-9:
			s = clampf(-cc / aa, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := aa * ee - bb * bb
			if denom > 1e-9:
				s = clampf((bb * f - cc * ee) / denom, 0.0, 1.0)
			t = (bb * s + f) / ee
			if t < 0.0:
				t = 0.0
				s = clampf(-cc / aa, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - cc) / aa, 0.0, 1.0)
	var p1 := a + d1 * s
	var p2 := c + d2 * t
	return [p1.distance_to(p2), s * sqrt(aa), p2]


const JUMPER_HALF := 0.3   # a bridge reaches this far either side of the crossing
const JUMPER_GAP := 0.08   # air between the two pipes' surfaces, well past the crossing test's 0.03


## The path with a bridge round every run it would cross, bridges on
## one segment merged where they would touch. A bridge lifts the run
## perpendicular to both: over (or, for the thinner run, under) a
## horizontal, sideways round a riser. Where there is no room either
## way the crossing stays and the report names it.
func _with_jumpers(path: Array[Vector3], radius: float, skip: Dictionary, ignore: Array,
		order: int = ORDER_ALL) -> Array[Vector3]:
	var crossings := _crossings(path, radius, skip, ignore, order)
	if crossings.is_empty():
		if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
			print("[jumper] %s: no crossings (%d others with paths)" % [str(ignore), _wire_visuals.size()])
		return path
	var hopped := 0
	var refused := 0
	var by_seg := {}
	for crossing in crossings:
		var seg: int = crossing["seg"]
		if not by_seg.has(seg):
			by_seg[seg] = []
		(by_seg[seg] as Array).append(crossing)
	var out: Array[Vector3] = [path[0]]
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		if by_seg.has(i):
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var list: Array = by_seg[i]
			list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["at"]) < float(y["at"]))
			# Spans: [from, to, top, bottom, other radius, sideways normal or
			# ZERO, farthest riser axis on the + side, farthest on the - side]
			var spans: Array = []
			for crossing: Dictionary in list:
				var s0 := maxf(0.05, float(crossing["at"]) - JUMPER_HALF)
				var s1 := minf(length - 0.05, float(crossing["at"]) + JUMPER_HALF)
				var other_dir: Vector3 = crossing["other_dir"]
				var normal := dir.cross(other_dir).normalized()
				var sideways := Vector3.ZERO
				if absf(normal.y) < 0.7:
					sideways = Vector3(normal.x, 0.0, normal.z).normalized()
				var lateral: float = crossing["lateral"]
				if not spans.is_empty() and s0 <= float(spans[spans.size() - 1][1]) + 0.1:
					var last: Array = spans[spans.size() - 1]
					last[1] = maxf(float(last[1]), s1)
					last[2] = maxf(float(last[2]), float(crossing["top"]))
					last[3] = minf(float(last[3]), float(crossing["bottom"]))
					last[4] = maxf(float(last[4]), float(crossing["other_r"]))
					if sideways == Vector3.ZERO:
						last[5] = Vector3.ZERO   # any horizontal in the span: go over it
					elif last[9] == Vector3.ZERO:
						last[9] = sideways       # and round the riser beside it, if any
					last[6] = maxf(float(last[6]), lateral)
					last[7] = minf(float(last[7]), lateral)
					for end_name in crossing["ends"]:
						if not (last[8] as Array).has(end_name):
							(last[8] as Array).append(end_name)
				else:
					spans.append([s0, s1, crossing["top"], crossing["bottom"], crossing["other_r"], sideways,
						lateral, lateral, (crossing["ends"] as Array).duplicate(), sideways])
			for span: Array in spans:
				var s0: float = span[0]
				var s1: float = span[1]
				if s1 - s0 < 0.2:
					refused += 1
					continue
				var p0 := a + dir * s0
				var p1 := a + dir * s1
				var rise := Vector3.ZERO
				# A bridge in front of a nozzle cluster is not inside the machine:
				# the other run's two records are as open to it as this run's own.
				var bridge_ctx := clearance.context(ignore, path[0], path[path.size() - 1], radius, span[8])
				var side_normal: Vector3 = span[5]
				if side_normal != Vector3.ZERO:
					# Round a riser, or a row of them: past the farthest on
					# that side, and a jog big enough for its elbows to sweep.
					var gap_needed := radius + float(span[4]) + JUMPER_GAP
					var plus := maxf(float(span[6]), 0.0) + gap_needed
					var minus := maxf(-float(span[7]), 0.0) + gap_needed
					var candidates: Array[Vector3] = []
					for jog: float in [plus, minus] if plus <= minus else [minus, plus]:
						var side := 1.0 if jog == plus else -1.0
						candidates.append(side_normal * side * maxf(jog, 3.0 * radius + 0.03))
					for candidate in candidates:
						# Clear of solids, and not landed on another run: a jog
						# round a riser must not come down on the line that
						# riser feeds.
						var jog: Array[Vector3] = [p0 - dir * 0.5, p0, p0 + candidate, p1 + candidate, p1, p1 + dir * 0.5]
						if clearance.hits([p0, p0 + candidate, p1 + candidate, p1], bridge_ctx).is_empty() \
								and _crossings(jog, radius, skip, ignore, order, 0.0).is_empty():
							rise = candidate
							break
				else:
					var over := maxf(a.y, float(span[2]) + radius + JUMPER_GAP)
					var under := minf(a.y, float(span[3]) - radius - JUMPER_GAP)
					# A bridge must clear whatever else crosses under its deck:
					# another run's bridge over the same spot, say.
					for attempt in 3:
						var deck_top := _highest_under(p0 + Vector3.UP * (over - a.y), p1 + Vector3.UP * (over - a.y),
							radius, skip, ignore, order)
						if deck_top <= over - radius - JUMPER_GAP + 0.001:
							break
						over = deck_top + radius + JUMPER_GAP
					var up := Vector3.UP * (over - a.y)
					var down := Vector3.UP * (under - a.y)
					# A span with a riser in it as well (a line's own bridge, deck
					# and ramps) is passed over or under the deck and beside the
					# ramp at once; without one, straight over or under.
					var jogs: Array[Vector3] = [Vector3.ZERO]
					var riser_normal: Vector3 = span[9]
					if riser_normal != Vector3.ZERO:
						var gap_needed := radius + float(span[4]) + JUMPER_GAP
						var plus := maxf(float(span[6]), 0.0) + gap_needed
						var minus := maxf(-float(span[7]), 0.0) + gap_needed
						jogs = []
						for jog: float in [plus, minus] if plus <= minus else [minus, plus]:
							var side := 1.0 if jog == plus else -1.0
							jogs.append(riser_normal * side * maxf(jog, 3.0 * radius + 0.03))
					# A conduit dips under a pipe; a pipe goes over a conduit.
					var thinner: bool = radius < float(span[4])
					var under_possible := under > radius + 0.05 and under < a.y - 0.001
					var over_possible := over > a.y + 0.001
					var vertical: Array[Vector3] = []
					if thinner:
						if under_possible:
							vertical.append(down)
						if over_possible:
							vertical.append(up)
					else:
						if over_possible:
							vertical.append(up)
						if under_possible:
							vertical.append(down)
					for v in vertical:
						for jog in jogs:
							var move := v + jog
							var deck: Array[Vector3] = [p0 - dir * 0.5, p0, p0 + move, p1 + move, p1, p1 + dir * 0.5]
							# The deck clears what it bridges by the gap, so the check
							# here is for touching, with no margin.
							if clearance.hits([p0, p0 + move, p1 + move, p1], bridge_ctx).is_empty() \
									and (jog == Vector3.ZERO or _crossings(deck, radius, skip, ignore, order,
										0.0).is_empty()):
								rise = move
								break
						if rise.length() > 0.001:
							break
				if rise.length() < 0.001:
					refused += 1
					continue
				hopped += 1
				_append_point(out, p0)
				_append_point(out, p0 + rise)
				_append_point(out, p1 + rise)
				_append_point(out, p1)
		_append_point(out, b)
	if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
		var names: Array = []
		for crossing in crossings:
			names.append("%s@%.1f" % [crossing["other"], float(crossing["at"])])
		print("[jumper] %s: hopped %d, refused %d (last blocked by %s); crossings %s" % [str(ignore),
			hopped, refused, clearance.last_block, str(names)])
	return out


## The top of the highest other run a bridge deck from p0 to p1 would
## cross, or -INF when it crosses nothing.
func _highest_under(p0: Vector3, p1: Vector3, radius: float, skip: Dictionary, ignore: Array,
		order: int) -> float:
	var top := -INF
	var deck: Array[Vector3] = [p0 - (p1 - p0).normalized() * 0.5, p0, p1, p1 + (p1 - p0).normalized() * 0.5]
	for crossing in _crossings(deck, radius, skip, ignore, order, JUMPER_GAP + 0.05):
		top = maxf(top, float(crossing["top"]))
	return top


static func _append_point(out: Array[Vector3], p: Vector3) -> void:
	if out[out.size() - 1].distance_to(p) > 0.001:
		out.append(p)


## Every place two runs still pass through each other, worst first.
func crossing_report() -> PackedStringArray:
	var lines := PackedStringArray()
	var seen := {}
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		var path: Array[Vector3] = _visual_path(visual)
		var view := visual["node"] as PipeView
		for crossing in _crossings(path, view.radius(), visual, [str(visual["a"]), str(visual["b"])]):
			var p: Vector3 = path[crossing["seg"]] \
				+ (path[crossing["seg"] + 1] - path[crossing["seg"]]).normalized() * float(crossing["at"])
			var key := Vector3i(roundi(p.x * 4.0), roundi(p.y * 4.0), roundi(p.z * 4.0))
			if seen.has(key):
				continue
			seen[key] = true
			var line := "%s.%s -> %s.%s crosses %s at (%.1f, %.2f, %.1f)" % [visual["a"],
				visual["a_port"], visual["b"], visual["b_port"], crossing["other"], p.x, p.y, p.z]
			if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
				var own := _crossings(path, view.radius(), visual, [str(visual["a"]), str(visual["b"])],
					int(visual.get("order", ORDER_ALL))).size()
				line += " — order %d, sees %d under its own order; segment %d of %s" % [int(visual.get("order", -1)), own,
					int(crossing["seg"]), str(path)]
			lines.append(line)
	return lines


## Every run failing the support rule, with where its longest
## unsupported span begins and how long it is.
## Every place a laid run passes through solid geometry, by the one
## rule in RunClearance. One line per run and owner.
func intersection_report() -> PackedStringArray:
	var lines := PackedStringArray()
	var checks: Array = []
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		var path: Array[Vector3] = _visual_path(visual)
		if path.size() < 2:
			continue
		checks.append([path, (visual["node"] as PipeView).radius(),
			"%s.%s -> %s.%s" % [visual["a"], visual["a_port"], visual["b"], visual["b_port"]],
			[str(visual["a"]), str(visual["b"])]])
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		var laid: Array[Vector3] = PipeRoute.lay(entry["points"])
		if laid.size() >= 2:
			checks.append([laid, (entry["node"] as PipeView).radius(), name_, []])
	for item: Array in checks:
		var path: Array[Vector3] = item[0]
		var ctx := clearance.context(item[3], path[0], path[path.size() - 1], float(item[1]))
		for hit: Dictionary in clearance.hits(path, ctx):
			var p: Vector3 = hit["at"]
			lines.append("%s through %s at (%.1f, %.2f, %.1f)" % [item[2], str(hit["owner"]), p.x, p.y, p.z])
	return lines


func unsupported_report() -> PackedStringArray:
	var out := PackedStringArray()
	for visual in _wire_visuals:
		var node: Node = visual["node"]
		if node is PipeView and (node as PipeView)._unsupported:
			out.append("%s -> %s: %.1f m from %s%s" % [visual["a"], visual["b"],
				float(node.get_meta("unsupported_span", 0.0)), str(node.get_meta("unsupported_at", "?")),
				(" — path %s" % str(visual.get("path", []))) if OS.has_environment("FLOWSTATE_ROUTE_DEBUG") else ""])
	for name_: String in runs:
		var node := runs[name_]["node"] as PipeView
		if node != null and node._unsupported:
			out.append("%s: %.1f m from %s" % [name_, float(node.get_meta("unsupported_span", 0.0)),
				str(node.get_meta("unsupported_at", "?"))])
	return out


## Why a record cannot be picked up and set down elsewhere, or "".
func movable(name_: String) -> String:
	if not equip_types.has(name_) or not views.has(name_):
		return "only placed equipment moves — remove and re-place structure"
	# Commissioned equipment moves like anything else; only its removal
	# and its sizing stay refused, so the starting loop can never be broken.
	if mounted.has(name_) or PlantFactory.MOUNTABLE.has(str(equip_types[name_])):
		return "%s is mounted on a vessel — remove it and mount it again" % name_
	return ""


## Set placed equipment down somewhere else.
## Its runs are re-laid from their own waypoints, instruments on its
## shell ride with it, and a vessel takes its elevation from the new
## height exactly as it did at placement.
func move_equipment(name_: String, world_pos: Vector3, rot_y: float) -> bool:
	checkpoint()
	if movable(name_) != "":
		return false
	var view := views[name_] as Node3D
	var type_id := str(equip_types[name_])
	view.position = to_local(world_pos) + Vector3(0, PlantFactory.Y_OFFSETS.get(type_id, 0.0), 0)
	view.rotation.y = rot_y
	var record := sim.get_component(name_)
	if record != null and record.get("elevation_m") != null:
		_apply_elevation(record, type_id, view, to_local(world_pos).y, {})
		sim.invalidate_network()
	refresh_wires_of(name_)
	for inst_name: String in mounted.keys():
		if str((mounted[inst_name] as Dictionary)["host"]) == name_:
			refresh_wires_of(inst_name)
	if view is VialPartView:
		_vial_line_dirty = true
	return true


## Sizing from the device menu's CONFIGURE tab: every modification to
## equipment goes through that menu. Values
## are keyed like the record's constructor params, which is what
## _params_for saves, so a change survives a reload. The plant owns
## what a change means: a tank re-renders and re-anchors its runs, a
## switch redraws its trip rings on the host, and anything hydraulic
## rebuilds the network. Returns "" or why not.
func configure_equipment(name_: String, values: Dictionary) -> String:
	checkpoint()
	var record := sim.get_component(name_)
	if record == null or not views.has(name_):
		return "no such equipment"
	if protected.has(name_):
		return "%s is commissioned equipment — its sizing is fixed" % name_
	var allowed := {}
	for field: Dictionary in PlantFactory.CONFIG.get(str(equip_types.get(name_, "")), []):
		allowed[str(field["key"])] = field
	for key: String in values:
		if not allowed.has(key):
			return "%s has no %s" % [name_, key]
		var field: Dictionary = allowed[key]
		if field.has("options"):
			if SimSpecies.index_of(str(values[key])) < 0:
				return "unknown species"
		elif str(field.get("kind", "")) == "toggle":
			pass
		elif str(field.get("kind", "")) == "tag":
			if str(values[key]) != "" and not historian.data.has(str(values[key])):
				return "no historian tag named %s" % str(values[key])
		elif float(values[key]) < float(field["min"]) or float(values[key]) > float(field["max"]):
			return "%s must be %s to %s" % [field["label"], field["min"], field["max"]]
	if record is SimTrendScreen:
		var screen := record as SimTrendScreen
		for key: String in values:
			if key.begins_with("tag"):
				screen.tags[int(key.substr(3)) - 1] = str(values[key])
			elif key == "window_s":
				screen.window_s = clampf(float(values[key]), 60.0, 3600.0)
		return ""
	if values.has("dn") and record.get("dn") != null:
		# A fitting bought at a size (a tee, a valve): the nearest nominal
		# bore, the view rebuilt at it, its lines laid again (a reducer
		# where they differ).
		var wanted := float(values["dn"])
		var nearest := LINE_SIZES[0]
		for size: int in LINE_SIZES:
			if absf(float(size) - wanted) < absf(float(nearest) - wanted):
				nearest = size
		record.set("dn", nearest)
		values = values.duplicate()
		values.erase("dn")
		_sync_bores([name_])
		if values.is_empty():
			return ""
	if record is SimTank:
		var tank_rec := record as SimTank
		if values.has("nozzle_cv_lps"):
			tank_rec.nozzle_cv_lps = float(values["nozzle_cv_lps"])
		if values.has("open_top") and bool(values["open_top"]) != tank_rec.open_top:
			# The roof comes off or goes on: the view is built again, and
			# an open end above it finds it (or loses it) at the sweep.
			tank_rec.open_top = bool(values["open_top"])
			var tank_view := views.get(name_) as TankView
			if tank_view != null:
				tank_view.rebuild()
				MeshMerge.merge_view(tank_view)
			_schedule_revalidate()
		if values.has("height_m") or values.has("diameter_m"):
			resize_tank(name_, float(values.get("height_m", tank_rec.height_m)),
				float(values.get("diameter_m", tank_rec.diameter_m)))
	elif record is SimFloatSwitch:
		var fs := record as SimFloatSwitch
		var low := float(values.get("low_l", fs.low_l))
		var high := float(values.get("high_l", fs.high_l))
		if low > high:
			return "the low trip must not be above the high trip"
		fs.set_band(low, high)
		if mounted.has(name_):
			var host_view := views.get(str((mounted[name_] as Dictionary)["host"])) as TankView
			if host_view != null:
				host_view.rebuild()  # its trip rings
				MeshMerge.merge_view(host_view)
	else:
		for key: String in values:
			if str(allowed[key].get("kind", "")) == "toggle":
				record.set(key, bool(values[key]))
			elif key != "species":
				record.set(key, float(values[key]))
			elif record is SimSource:
				(record as SimSource).set_species(str(values[key]))
			elif record is SimGauge:
				(record as SimGauge).species_index = SimSpecies.index_of(str(values[key]))
	if record is SimVialMagazine:
		var magazine := record as SimVialMagazine
		magazine.vial_ml = SimVial.size_of(magazine.vial_ml)
	var line_view := views.get(name_) as VialPartView
	if line_view != null:
		line_view.rebuild()
		MeshMerge.merge_view(line_view)
		if record is SimVialTrack:
			_free_markers(line_view)
			PlantFactory.attach_port_markers(line_view, record, "vial_track",
				VialTrackView.anchors((record as SimVialTrack).length_m))
			refresh_wires_of(name_)
		_vial_line_dirty = true
	sim.invalidate_network()
	return ""


func remove_equipment(name_: String) -> bool:
	checkpoint()
	if protected.has(name_) or not views.has(name_):
		return false
	# Instruments mounted on a vessel go with it.
	for inst_name: String in mounted.keys():
		if inst_name != name_ and str((mounted[inst_name] as Dictionary)["host"]) == name_:
			remove_equipment(inst_name)
	if mounted.has(name_):
		var host_view := views.get(str((mounted[name_] as Dictionary)["host"])) as TankView
		if host_view != null:
			host_view.unmount(views[name_] as Node3D)
		mounted.erase(name_)
	var rejoin := _line_through(name_) if PlantFactory.LINE_ONLY.has(str(equip_types.get(name_, ""))) else {}
	sim.remove_component(name_)
	var keep: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["a"] == name_ or visual["b"] == name_:
			if visual["node"] != null:
				(visual["node"] as Node).queue_free()
		else:
			keep.append(visual)
	_wire_visuals = keep
	if views[name_] is VialPartView:
		_vial_line_dirty = true
	(views[name_] as Node).queue_free()
	views.erase(name_)
	equip_types.erase(name_)
	if not rejoin.is_empty():
		_rejoin_line(rejoin)
	return true


## The line a fitting that exists only in a line is cut into: the far
## ends of its two pieces, their corners in order, and what the line
## was (size, service, resistance), or {} when it is not on one.
func _line_through(name_: String) -> Dictionary:
	var up: Dictionary = {}
	var down: Dictionary = {}
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		if str(visual["b"]) == name_ and str(visual["b_port"]) == "inlet":
			up = visual
		elif str(visual["a"]) == name_ and str(visual["a_port"]) == "outlet":
			down = visual
	if up.is_empty() or down.is_empty():
		return {}
	var corners: Array = (up["waypoints"] as Array).duplicate()
	corners.append_array(down["waypoints"] as Array)
	return {"a": up["a"], "a_port": up["a_port"], "b": down["b"], "b_port": down["b_port"],
		"corners": corners, "dn": int(up.get("dn", 50)),
		"color": str(up.get("color", "")), "label": str(up.get("label", "")),
		"fitting": str(up.get("fitting", ""))}


## Lay the line a removed tapping was cut into back as one: the
## pipe it was, through the pieces' corners, at its size and service; its resistance follows from what is laid.
func _rejoin_line(line: Dictionary) -> void:
	var a := str(line["a"])
	var a_port := str(line["a_port"])
	var b := str(line["b"])
	var b_port := str(line["b_port"])
	_next_wire_fixed = true
	var why := connect_equipment(a, a_port, b, b_port, line["corners"] as Array)
	_next_wire_fixed = false
	if why != "":
		push_warning("could not rejoin the line %s.%s -> %s.%s: %s" % [a, a_port, b, b_port, why])
		return
	for visual in _wire_visuals:
		if str(visual["a"]) == a and str(visual["a_port"]) == a_port and visual["node"] != null:
			var view := visual["node"] as PipeView
			if int(line["dn"]) != 50:
				view = set_run_size(view, int(line["dn"]))
			if str(line["color"]) != "":
				set_run_service(view, Color.html(str(line["color"])), str(line["label"]), str(line["fitting"]))
			break


## Connect two ports (by record/port name), optionally routed through
## player-laid waypoints (plant-local). Returns "" on success or a
## human-readable refusal — the kernel's wiring rules, surfaced.
## visible=false makes an internal wire (cabinet hookup): a real
## kernel wire with no 3D run behind it.
func connect_equipment(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array = [],
		visible: bool = true) -> String:
	checkpoint()
	var src := sim.get_component(src_name)
	var dst := sim.get_component(dst_name)
	if src == null or dst == null:
		return "component missing"
	# One player pipe is one kernel wire. A material nozzle may take
	# several: that is a tee, and the network solves the split.
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
	if visible:
		# One line per nozzle, one cable per terminal: joining and splitting is a fitting's job, with its
		# own separated connection points. A tap does not count as a
		# line on what it reads. Hidden wires — mounts, cabinet internals,
		# multicore circuits — are the plant's own bookkeeping.
		# A pressure or level port is an instrument tap by nature: what
		# leaves it is an impulse line, and a room with a gauge on each of
		# two walls has two.
		var to_tap := dst.tap_ports().has(dst_port) \
			or out_port.kind == SimTypes.PortKind.PROCESS_PRESSURE \
			or out_port.kind == SimTypes.PortKind.PROCESS_LEVEL
		if not to_tap and visible_wire_count(src_name, src_port) > 0:
			return "%s already has a line — split it with a tee, or use another way" % out_port.path()
		if visible_wire_count(dst_name, dst_port) > 0:
			return "%s already has a line — join lines with a tee" % in_port.path()
	if not sim.connect_ports(src, src_port, dst, dst_port):
		return "connection refused"
	if visible:
		_wire_visual(src_name, src_port, dst_name, dst_port, waypoints)
		_sync_caps([src_name, dst_name])
		_sync_bores([src_name, dst_name])
	else:
		_wire_visuals.append({
			"node": null, "a": src_name, "a_port": src_port,
			"b": dst_name, "b_port": dst_port, "waypoints": [],
			"color": "", "label": "", "hidden": true,
		})
	return ""


## Visible lines on a port — the ones that occupy its fitting. A tap
## reading a line is not a line on it.
func visible_wire_count(record_name: String, port_name: String) -> int:
	var count := 0
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		if str(visual["a"]) == record_name and str(visual["a_port"]) == port_name:
			var dst := sim.get_component(str(visual["b"]))
			if dst != null and dst.tap_ports().has(str(visual["b_port"])):
				continue
			count += 1
		elif str(visual["b"]) == record_name and str(visual["b_port"]) == port_name:
			count += 1
	return count


## The first way on a mains feeder with nothing on it, or "".
func free_way(mains_name: String) -> String:
	var mains := sim.get_component(mains_name) as SimMainsFeed
	if mains == null:
		return ""
	for i in mains.ways:
		var way := "way%d" % (i + 1)
		if visible_wire_count(mains_name, way) == 0:
			return way
	return ""


## The drawn line between two ports, or null.
func line_between(src_name: String, src_port: String, dst_name: String, dst_port: String) -> PipeView:
	for visual in _wire_visuals:
		if str(visual["a"]) == src_name and str(visual["a_port"]) == src_port \
				and str(visual["b"]) == dst_name and str(visual["b_port"]) == dst_port \
				and visual["node"] is PipeView:
			return visual["node"] as PipeView
	return null


## A line's size: its drawn radius and its resistance follow, the line laid again as it
## was. The two lines of a cut or an inline device each keep their own.
func set_run_size(view: PipeView, dn: int) -> PipeView:
	if not LINE_SIZES.has(dn):
		return view
	checkpoint()
	for visual in _wire_visuals:
		if visual["node"] != view:
			continue
		visual["dn"] = dn
		_refresh_visual(visual)   # which sizes its resistance
		_sync_bores([str(visual["a"]), str(visual["b"])])
		_schedule_revalidate()
		return visual["node"] as PipeView
	return view


func wire_size(view: PipeView) -> int:
	for visual in _wire_visuals:
		if visual["node"] == view:
			return int(visual.get("dn", 50))
	return 50


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
	checkpoint()
	if structures.has(name_):
		return false
	var node := StructureFactory.make_view(type_id, name_, length)
	if node == null:
		return false
	add_child(node)
	node.global_position = base_pos + Vector3(0, (StructureFactory.SIZES[type_id] as Vector3).y / 2.0, 0)
	node.rotation.y = rot_y
	MeshMerge.merge_view(node)  # the door leaf, the sign face and the like are held and stay
	if type_id == "s_sign":
		node.config_cb = _configure_sign
	structures[name_] = {"type": type_id, "node": node, "length": length, "text": ""}
	_schedule_revalidate()
	return true


## Removing structure re-checks every run: whatever it was carrying
## turns alarm-red rather than quietly staying up.
func remove_structure(name_: String) -> bool:
	checkpoint()
	if not structures.has(name_):
		return false
	((structures[name_] as Dictionary)["node"] as Node).queue_free()
	structures.erase(name_)
	_schedule_revalidate()
	return true


## ---- junction boxes and multicores ---------------------------------------
## A junction box owns terminal records (one scan late, like any
## terminal) and stands where an area's circuits gather; a multicore
## is the one cable that carries them to the cabinet: a hidden kernel
## wire per circuit, and a single run to look at that the support rule
## checks like any other. This is how a real plant wires a field, and
## why it does not look like ten conduits home.

func unique_jb_name() -> String:
	var index := 1
	while junction_boxes.has("jb_%d" % index):
		index += 1
	return "jb_%d" % index


func place_junction_box(name_: String, world_pos: Vector3, rot_y: float, channels: int = 12,
		on_post: bool = true) -> bool:
	checkpoint()
	if junction_boxes.has(name_) or channels < 1:
		return false
	var view := JunctionBoxView.new()
	view.position = to_local(world_pos) + Vector3(0, JunctionBoxView.POST_H if on_post else 0.0, 0)
	view.rotation.y = rot_y
	add_child(view)
	view.setup(name_, channels, on_post)
	MeshMerge.merge_view(view)
	var records: Array[String] = []
	for i in channels:
		var record_name := "%s_t%d" % [name_, i + 1]
		var record := PlantFactory.make_record(sim, "terminal", record_name, {"kind": "discrete"})
		sim.register_with_historian(record)
		views[record_name] = view
		equip_types[record_name] = "terminal"
		protected[record_name] = true
		member_of[record_name] = name_
		records.append(record_name)
	junction_boxes[name_] = {"node": view, "records": records, "channels": channels, "on_post": on_post}
	# Field circuits land on the left flank, the multicore on the right,
	# one row per terminal down the box.
	var y := JunctionBoxView.BOX.y - 0.08
	var step := (JunctionBoxView.BOX.y - 0.14) / maxf(channels - 1, 1)
	for record_name in records:
		PlantFactory.attach_port_markers(view, sim.get_component(record_name), "terminal",
			{"in": Vector3(-0.25, y, 0.06), "out": Vector3(0.25, y, 0.06)})
		y -= step
	_schedule_revalidate()
	return true


## Wire several circuits between two enclosures through one cable. A
## pair is [src_record, src_port, dst_record, dst_port]; each becomes a
## hidden kernel wire, and the cable is a standalone run named `label`
## from the first pair's source marker to its destination marker
## through the plant-local waypoints. It lights while any circuit in
## it is live. Returns "" or the refusal.
func connect_multicore(label: String, pairs: Array, waypoints: Array) -> String:
	checkpoint()
	if pairs.is_empty():
		return "nothing to carry"
	if runs.has(label):
		return "a run named %s exists" % label
	for pair_v: Variant in pairs:
		var pair := pair_v as Array
		var err := connect_equipment(str(pair[0]), str(pair[1]), str(pair[2]), str(pair[3]), [], false)
		if err != "":
			return err
	var first := pairs[0] as Array
	var points: Array = [_marker_pos(str(first[0]), str(first[1]))]
	points.append_array(waypoints)
	points.append(_marker_pos(str(first[2]), str(first[3])))
	if not place_run("run_cable", label, points, _multicore_getter(pairs.duplicate(true))):
		return "could not lay the cable"
	var entry: Dictionary = runs[label]
	var text := "%s · %d circuits" % [label, pairs.size()]
	(entry["node"] as PipeView).apply_service(StructureFactory.RUNS["run_cable"]["color"], text)
	entry["label"] = text
	entry["circuits"] = pairs.duplicate(true)
	return ""


## ---- local control stations -----------------------------------------------
## A station is an enclosure on a post holding pushbutton and pilot
## light records; each is a real component the ladder sees, and each
## button is its own interaction target. devices is a list of
## {"kind": "button"|"light", "id", "legend", "color", "momentary",
## "nc"}; the records are named "<station>_<id>".

func unique_station_name() -> String:
	var index := 1
	while control_stations.has("lcs_%d" % index):
		index += 1
	return "lcs_%d" % index


static func default_station_devices() -> Array:
	return [
		{"kind": "button", "id": "start", "legend": "START", "color": "green", "momentary": true, "nc": false},
		{"kind": "button", "id": "stop", "legend": "STOP", "color": "red", "momentary": true, "nc": true},
		{"kind": "light", "id": "running", "legend": "RUNNING", "color": "green"},
		{"kind": "light", "id": "stopped", "legend": "STOPPED", "color": "red"},
	]


func place_control_station(name_: String, world_pos: Vector3, rot_y: float, devices: Array,
		on_post: bool = true) -> bool:
	checkpoint()
	if control_stations.has(name_) or devices.is_empty():
		return false
	var view := ControlStationView.new()
	view.position = to_local(world_pos) + Vector3(0, ControlStationView.POST_H if on_post else 0.0, 0)
	view.rotation.y = rot_y
	add_child(view)
	var records: Array[String] = []
	var built: Array = []
	for d_v: Variant in devices:
		var d := d_v as Dictionary
		var record_name := "%s_%s" % [name_, str(d["id"])]
		var is_button := str(d.get("kind", "button")) == "button"
		var record := PlantFactory.make_record(sim, "pushbutton" if is_button else "pilot_light", record_name,
			{"momentary": bool(d.get("momentary", true)), "normally_closed": bool(d.get("nc", false)),
			"color": str(d.get("color", "green"))})
		sim.register_with_historian(record)
		views[record_name] = view
		equip_types[record_name] = "pushbutton" if is_button else "pilot_light"
		protected[record_name] = true
		member_of[record_name] = name_
		records.append(record_name)
		built.append({"record": record, "legend": str(d.get("legend", str(d["id"]).to_upper())),
			"color": str(d.get("color", "green"))})
	view.setup(name_, built, on_post)
	MeshMerge.merge_view(view)
	control_stations[name_] = {"node": view, "records": records, "devices": devices.duplicate(true),
		"on_post": on_post}
	# Circuits leave on the right flank, one row per device.
	var y := ControlStationView.BOX.y - 0.06
	var step := (ControlStationView.BOX.y - 0.12) / maxf(records.size() - 1, 1)
	for record_name in records:
		var record := sim.get_component(record_name)
		var port_name := "contact" if record is SimPushbutton else "lamp"
		PlantFactory.attach_port_markers(view, record, str(equip_types[record_name]),
			{port_name: Vector3(0.26, y, 0.03)})
		y -= step
	_schedule_revalidate()
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
func place_run(kind: String, name_: String, sparse_local: Array, getter: Callable = Callable()) -> bool:
	checkpoint()
	if runs.has(name_) or not StructureFactory.RUNS.has(kind):
		return false
	var spec: Dictionary = StructureFactory.RUNS[kind]
	var view := PipeView.new()
	add_child(view)
	var live := getter if getter.is_valid() else func() -> float: return 0.0
	view.setup(PipeRoute.lay(sparse_local), live,
		spec["color"], spec["radius"], name_, spec["style"], 1)
	view.config_cb = _configure_run
	runs[name_] = {"kind": kind, "node": view, "points": sparse_local,
		"color": "", "label": ""}
	_schedule_revalidate()
	return true


## E on a run: open the color/label editor and store what it applies.
func _configure_run(view: PipeView) -> void:
	if config_panel == null:
		return
	var is_wire := false
	for visual in _wire_visuals:
		if visual["node"] == view:
			is_wire = true
	config_panel.open_for_run(view.service_color(), view.service_label,
		func(color: Color, label_: String, fitting: String = "", dn: int = 0) -> void:
			var target := view
			if dn > 0 and is_wire and dn != wire_size(view):
				target = set_run_size(view, dn)
			set_run_service(target, color, label_, fitting),
		view.fitting, wire_size(view) if is_wire else 0)


func set_run_service(view: PipeView, color: Color, label_: String, fitting: String = "") -> void:
	checkpoint()
	for visual in _wire_visuals:
		if visual["node"] == view:
			visual["color"] = color.to_html(false)
			visual["label"] = label_
			view.apply_service(color, label_)
			if fitting != "":
				visual["fitting"] = fitting
				view.set_fitting(fitting)
			return
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		if entry["node"] == view:
			entry["color"] = color.to_html(false)
			entry["label"] = label_
			view.apply_service(color, label_)
			if fitting != "":
				entry["fitting"] = fitting
				view.set_fitting(fitting)
			return


## E on a sign: open the text editor and persist the result.
func _configure_sign(view: StructureView) -> void:
	if config_panel == null:
		return
	var entry: Dictionary = structures.get(view.struct_name, {})
	config_panel.open_for_sign(str(entry.get("text", "")),
		func(text: String) -> void: set_sign_text(view.struct_name, text))


func set_sign_text(name_: String, text: String) -> void:
	checkpoint()
	if not structures.has(name_):
		return
	var entry: Dictionary = structures[name_]
	entry["text"] = text
	(entry["node"] as StructureView).set_text(text if text != "" else "SIGN")


func remove_placed_run(view: PipeView) -> bool:
	checkpoint()
	for name_: String in runs:
		if (runs[name_] as Dictionary)["node"] == view:
			view.queue_free()
			runs.erase(name_)
			_schedule_revalidate()  # whatever it carried re-checks
			return true
	return false


## Remove one routed run by its view (X while aiming at it): the wire
## leaves the kernel, the input reverts next scan, the visual goes.
func remove_run(view: PipeView) -> bool:
	checkpoint()
	for visual in _wire_visuals:
		if visual["node"] == view:
			_disconnect_visual(visual)
			(visual["node"] as Node).queue_free()
			_wire_visuals.erase(visual)
			_sync_caps([str(visual["a"]), str(visual["b"])])
			_sync_bores([str(visual["a"]), str(visual["b"])])
			return true
	return false


## Cut a line where the player pulled across it: the wire goes, a cap stands on each side of
## the cut, and the two pieces are laid again from the corners the
## line had, so they keep their shape; each cap's outer nozzle is a
## blind end a later line can land on. Returns "" or why not.
## The nearest point of a laid path to `at` (plant-local): the segment,
## the point, how far along the path it lies, and the path's length.
static func _nearest_on_path(path: Array[Vector3], at: Vector3) -> Dictionary:
	var best_d := INF
	var best_seg := 0
	var best_point := path[0]
	var arc := 0.0
	var best_arc := 0.0
	var best_t := 0.0
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var length := a.distance_to(b)
		var t := 0.0 if length < 1e-6 else clampf((at - a).dot(b - a) / (length * length), 0.0, 1.0)
		var p := a.lerp(b, t)
		var d := p.distance_to(at)
		if d < best_d:
			best_d = d
			best_seg = i
			best_point = p
			best_arc = arc + t * length
			best_t = t
		arc += length
	return {"seg": best_seg, "point": best_point, "arc": best_arc, "total": arc, "t": best_t,
		"distance": best_d}


## Equipment that stands on the floor: above it, it gets a pedestal.
## Measured from the floor, slab or deck actually below, in the
## deferred pass where physics is known, so a placement, a move and a
## load all get one; nothing within reach below, and it stays as it is.
const PEDESTAL_TYPES: Array[String] = ["pump", "metering_pump"]
const PEDESTAL_REACH := 6.0


func _pedestal_pass(space: PhysicsDirectSpaceState3D) -> void:
	for name_: String in views:
		if not PEDESTAL_TYPES.has(str(equip_types.get(name_, ""))):
			continue
		var view := views[name_] as Node3D
		if view == null:
			continue
		var base := view.global_position - Vector3(0, PlantFactory.Y_OFFSETS.get(equip_types[name_], 0.0), 0)
		var query := PhysicsRayQueryParameters3D.create(base + Vector3(0, 0.05, 0),
			base + Vector3(0, -PEDESTAL_REACH, 0), 1)
		var exclude: Array[RID] = []
		for body in view.find_children("*", "CollisionObject3D", true, false):
			exclude.append((body as CollisionObject3D).get_rid())
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		var height := 0.0
		if not hit.is_empty():
			height = base.y - (hit["position"] as Vector3).y
		_set_pedestal(view, height if height > 0.03 else 0.0)


## A painted-steel plinth under a view, from its base down `height`,
## with a base plate on the floor. Held by name so it is rebuilt, not
## merged away, and removed when the height is nothing.
func _set_pedestal(view: Node3D, height: float) -> void:
	var old := view.get_node_or_null("pedestal")
	if old != null:
		if height > 0.0 and absf(float(old.get_meta("height", 0.0)) - height) < 0.01:
			return
		old.queue_free()
	if height <= 0.0:
		return
	var pedestal := Node3D.new()
	pedestal.name = "pedestal"
	pedestal.set_meta("height", height)
	pedestal.set_meta("no_merge", true)
	view.add_child(pedestal)
	var steel := ViewUtil.flat(Color(0.30, 0.32, 0.35))
	ViewUtil.box(pedestal, Vector3(0.5, height, 0.42), Vector3(0, -height / 2.0, 0), steel)
	ViewUtil.box(pedestal, Vector3(0.7, 0.03, 0.6), Vector3(0, -height + 0.015, 0), steel)
	ViewUtil.box(pedestal, Vector3(0.6, 0.03, 0.5), Vector3(0, -0.015, 0), steel)


## ---- inline equipment ----------------------------------------------------

## How a type goes inline, or {} for one that cannot:
## `in` and `out`, the ports the two pieces take; `in_angle`, the
## bearing the inlet leaves the device at, so it can be turned to face
## upstream; `half`, the room the device needs either side along the
## line; `axis`, true when both nozzles sit on one axis at one height
## (the device then stands with its nozzles at the line's height) and
## false for a vessel, which stands on the floor and takes the line
## through risers to its nozzles; `port_y`, the nozzle height over the
## base for an axis type.
static func inline_spec(type_id: String, dn: int = 50) -> Dictionary:
	var anchors: Dictionary = PlantFactory.anchors_for(type_id, line_radius(dn))
	match type_id:
		"tank":
			var probe := TankView.new()
			var angle := float(probe.nozzles["inlet"]["angle"])
			probe.free()
			return {"in": "inlet", "out": "outlet", "in_angle": angle, "axis": false,
				"half": PlantFactory.FOOTPRINTS[type_id].x / 2.0, "port_y": 0.0}
		"tee_split":
			return {"in": "in", "out": "a", "in_angle": PI, "axis": true,
				"half": 0.27, "port_y": (anchors["in"]["pos"] as Vector3).y}
		"tee_mix":
			return {"in": "a", "out": "out", "in_angle": PI, "axis": true,
				"half": 0.27, "port_y": (anchors["a"]["pos"] as Vector3).y}
	if not anchors.has("inlet") or not anchors.has("outlet"):
		return {}
	var i: Dictionary = anchors["inlet"]
	var o: Dictionary = anchors["outlet"]
	if i["dir"] != Vector3.LEFT or o["dir"] != Vector3.RIGHT:
		return {}
	var ip: Vector3 = i["pos"]
	var op: Vector3 = o["pos"]
	if absf(ip.y - op.y) > 0.001 or absf(ip.z) > 0.001 or absf(op.z) > 0.001 or absf(ip.x + op.x) > 0.001:
		return {}
	return {"in": "inlet", "out": "outlet", "in_angle": PI, "axis": true, "half": op.x, "port_y": ip.y}


## The room an inline device needs either side of its centre along
## the line: its half, its flange, and the straight spool every
## fitting keeps after the flange — nothing more.
static func inline_need(type_id: String, dn: int = 50) -> float:
	var spec := inline_spec(type_id, dn)
	if spec.is_empty():
		return -1.0
	var r := line_radius(dn)
	# The fitting at the face: a flange on pipe, a nut on tubing.
	var fitting := 0.03 if SmallBoreUtil.is_tube(r) else 0.175
	return float(spec["half"]) + fitting + PipeRoute.stub_for(r)


## The line nearest a point (world), within `max_d` of its drawn path,
## and the point of it: {"view", "at"} or {}. A pipe is a thin target,
## so an inline element snaps to one near the crosshair.
func nearest_wire(world_point: Vector3, max_d: float) -> Dictionary:
	var local := to_local(world_point)
	var best := max_d
	var found := {}
	for visual in _wire_visuals:
		if visual["node"] == null or not (visual["node"] is PipeView):
			continue
		var view := visual["node"] as PipeView
		if view.style() != "pipe":
			continue
		var path: Array[Vector3] = _visual_path(visual)
		if path.size() < 2:
			continue
		var near := _nearest_on_path(path, local)
		if float(near["distance"]) < best:
			best = float(near["distance"])
			found = {"view": view, "at": to_global(near["point"] as Vector3)}
	return found


## Where an inline device would sit on a line aimed at, or why not:
## {"why", "point" (plant-local, on the pipe axis), "dir", "arc"}. The
## device and the stubs of the two pieces must fit on one level
## straight, clear of the fittings.
func inline_spot(view: PipeView, at_global: Vector3, type_id: String) -> Dictionary:
	var dn := wire_size(view)
	var spec := inline_spec(type_id, dn)
	if spec.is_empty():
		return {"why": "%s does not go inline" % type_id}
	var half: float = spec["half"]
	var visual: Dictionary = {}
	for candidate in _wire_visuals:
		if candidate["node"] == view:
			visual = candidate
	if visual.is_empty():
		return {"why": "only a line between two fittings takes equipment inline"}
	var path: Array[Vector3] = _visual_path(visual)
	if path.size() < 2:
		return {"why": "nothing to cut into"}
	var near := _nearest_on_path(path, to_local(at_global))
	var seg: int = near["seg"]
	var dir := (path[seg + 1] - path[seg]).normalized()
	if absf(dir.y) > 0.01:
		return {"why": "put it on a level stretch, not a riser"}
	# Room along this straight for the device, the two stub ends and a
	# little more, and clear of the fittings either way.
	var need := inline_need(type_id, dn)
	var length := path[seg].distance_to(path[seg + 1])
	var t: float = near["t"]
	if t * length < need or (1.0 - t) * length < need:
		return {"why": "no room on that straight — it needs %.2f m either side" % need}
	var fitting_zone := PipeRoute.stub_for(line_radius(dn)) + 0.2
	if float(near["arc"]) - need < fitting_zone or float(near["total"]) - float(near["arc"]) - need < fitting_zone:
		return {"why": "too close to the fitting"}
	# Where the device stands and which way it faces: its inlet toward
	# the upstream piece; an axis type with its nozzles at the line's
	# height, a vessel on the floor below the line.
	var point: Vector3 = near["point"]
	var rot: float = float(spec["in_angle"]) - atan2(-dir.z, -dir.x)
	var base := Vector3(point.x, point.y - float(spec["port_y"]), point.z)
	var query := PhysicsRayQueryParameters3D.create(to_global(point), to_global(point) + Vector3.DOWN * 6.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not bool(spec["axis"]):
		if hit.is_empty():
			return {"why": "nothing below the line to stand it on"}
		base = to_local(hit["position"] as Vector3)
		base.x = point.x
		base.z = point.z
	elif not hit.is_empty() and base.y < to_local(hit["position"] as Vector3).y - 0.02:
		# A fitting on a stand would be buried: the line is lower than
		# its nozzles stand.
		return {"why": "the line is too low here for a %s (its nozzles stand %.2f m up) — raise it first"
			% [type_id, float(spec["port_y"])]}
	return {"why": "", "point": point, "dir": dir, "arc": near["arc"], "base": base, "rot": rot,
		"in": spec["in"], "out": spec["out"]}


## Cut a line and stand an inline device in the gap, connected: the
## upstream piece to its inlet, its outlet to the downstream piece, the
## corners of the line kept, both pieces fixed. "" on success.
func place_inline(type_id: String, view: PipeView, at_global: Vector3) -> String:
	var spot := inline_spot(view, at_global, type_id)
	if spot["why"] != "":
		return spot["why"]
	checkpoint()
	var visual: Dictionary = {}
	for candidate in _wire_visuals:
		if candidate["node"] == view:
			visual = candidate
	var path: Array[Vector3] = _visual_path(visual)
	var point: Vector3 = spot["point"]
	var dir: Vector3 = spot["dir"]
	var arc: float = spot["arc"]
	var before: Array = []
	var after: Array = []
	var walked := 0.0
	for i in range(1, path.size() - 1):
		walked += path[i].distance_to(path[i - 1])
		if i >= 2 and i <= path.size() - 3:
			if walked < arc:
				before.append(path[i])
			else:
				after.append(path[i])
	var a_name := str(visual["a"])
	var a_port := str(visual["a_port"])
	var b_name := str(visual["b"])
	var b_port := str(visual["b_port"])
	var color := str(visual.get("color", ""))
	var label_ := str(visual.get("label", ""))
	var fitting := str(visual.get("fitting", ""))
	var dn := int(visual.get("dn", 50))
	remove_run(view)
	# The device on the pipe axis, its inlet toward the upstream piece.
	var rot: float = spot["rot"]
	var base: Vector3 = spot["base"]
	var in_port := str(spot["in"])
	var out_port := str(spot["out"])
	var params := {}
	if type_id in ["tee_split", "tee_mix", "valve", "block_valve"]:
		params["dn"] = int(visual.get("dn", 50))   # bought at the size of the line it is cut into
	var record := place(type_id, sim.unique_name(type_id), params, to_global(base), rot, false)
	if record == null:
		return "could not place %s" % type_id
	_next_wire_fixed = true
	var why := connect_equipment(a_name, a_port, record.comp_name, in_port, before)
	if why == "":
		_next_wire_fixed = true
		why = connect_equipment(record.comp_name, out_port, b_name, b_port, after)
	_next_wire_fixed = false
	if why != "":
		return why
	for pair: Array in [[a_name, a_port, record.comp_name, in_port], [record.comp_name, out_port, b_name, b_port]]:
		for candidate in _wire_visuals:
			if str(candidate["a"]) == str(pair[0]) and str(candidate["b"]) == str(pair[2]) \
					and candidate["node"] != null:
				var piece := candidate["node"] as PipeView
				if dn != 50:
					piece = set_run_size(piece, dn)   # the pieces keep the size of the line
				if color != "":
					set_run_service(piece, Color.html(color), label_, fitting)
	# The two pieces are priced by their own lengths, as every line is,
	# so together they are the line less the length the device took.
	return ""


func cut_wire(view: PipeView, at_global: Vector3) -> String:
	checkpoint()
	var visual: Dictionary = {}
	for candidate in _wire_visuals:
		if candidate["node"] == view:
			visual = candidate
	if visual.is_empty():
		return "only a line between two fittings can be cut"
	var path: Array[Vector3] = _visual_path(visual)
	if path.size() < 2:
		return "nothing to cut"
	var near := _nearest_on_path(path, to_local(at_global))
	var best_seg: int = near["seg"]
	var best_point: Vector3 = near["point"]
	var best_arc: float = near["arc"]
	var arc: float = near["total"]
	var seg_dir := (path[best_seg + 1] - path[best_seg]).normalized()
	if absf(seg_dir.y) > 0.7:
		return "cut a horizontal stretch, not a riser"
	if best_arc < 0.9 or arc - best_arc < 0.9:
		return "too close to the fitting to cut there"
	# The corners the line was laid through, split about the cut; the
	# stubs and the ends belong to the fittings.
	var before: Array = []
	var after: Array = []
	var walked := 0.0
	for i in range(1, path.size() - 1):
		walked += path[i].distance_to(path[i - 1])
		if i >= 2 and i <= path.size() - 3:
			if walked < best_arc:
				before.append(path[i])
			else:
				after.append(path[i])
	var a_name := str(visual["a"])
	var a_port := str(visual["a_port"])
	var b_name := str(visual["b"])
	var b_port := str(visual["b_port"])
	var color := str(visual.get("color", ""))
	var label_ := str(visual.get("label", ""))
	var fitting := str(visual.get("fitting", ""))
	var dn := int(visual.get("dn", 50))
	remove_run(view)
	# Two caps, a hand apart either side of the cut, their spools along
	# the line: the first takes the upstream piece on its a-nozzle, the
	# second feeds the downstream piece from its b-nozzle.
	var rot := atan2(-seg_dir.z, seg_dir.x)
	var names: Array[String] = []
	for side: float in [-1.0, 1.0]:
		var cap_name := unique_name("cap")
		var spot := best_point + seg_dir * (side * 0.45)
		place("cap", cap_name, {"line_y": spot.y}, to_global(Vector3(spot.x, 0.0, spot.z)), rot, false)
		names.append(cap_name)
	_next_wire_fixed = true   # the pieces keep the corners they were cut with
	var why := connect_equipment(a_name, a_port, names[0], "a", before)
	if why == "":
		_next_wire_fixed = true
		why = connect_equipment(names[1], "b", b_name, b_port, after)
	_next_wire_fixed = false
	if why != "":
		return why
	for pair: Array in [[a_name, a_port, names[0], "a"], [names[1], "b", b_name, b_port]]:
		for candidate in _wire_visuals:
			if str(candidate["a"]) == str(pair[0]) and str(candidate["b"]) == str(pair[2]) \
					and candidate["node"] != null:
				var piece := candidate["node"] as PipeView
				if dn != 50:
					piece = set_run_size(piece, dn)   # the pieces keep the size of the line
				if color != "":
					set_run_service(piece, Color.html(color), label_, fitting)
	return ""


## Lay a line again through the corners the player set. The corners become
## the line's own waypoints, so from here on it is laid the player's
## way and the router only fills between them.
func set_wire_corners(view: PipeView, corners: Array) -> PipeView:
	checkpoint()
	for visual in _wire_visuals:
		if visual["node"] == view:
			visual["waypoints"] = corners
			# A lock stays while its waypoint does.
			var kept: Array = []
			for lock: Vector3 in visual.get("locks", []):
				for w: Vector3 in corners:
					if w.distance_to(lock) < 0.01:
						kept.append(lock)
						break
			visual["locks"] = kept
			_refresh_visual(visual)   # a new node: the caller keeps the one returned
			_schedule_revalidate()
			return visual["node"] as PipeView
	return null


## A line laid to nowhere: the last waypoint becomes an open
## cap, turned to take the line, and the line runs from the outlet to
## it. "" on success, else why not.
func connect_open(src_name: String, src_port: String, waypoints: Array) -> String:
	if waypoints.size() < 1:
		return "aim the line somewhere first: click a point for its end"
	var src := sim.get_component(src_name)
	if src == null or not src.outputs.has(src_port):
		return "an open end takes a line from an outlet"
	checkpoint()
	var end: Vector3 = waypoints[waypoints.size() - 1]
	var before: Vector3 = waypoints[waypoints.size() - 2] if waypoints.size() >= 2 \
		else _marker_pos(src_name, src_port) + _marker_dir(src_name, src_port) \
			* _stub_of(src_name, src_port, line_radius(_next_wire_dn))
	var dir := end - before
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = _marker_dir(src_name, src_port)
		dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3.RIGHT
	# The cap's a-nozzle faces back along the line: its bearing is LEFT.
	var rot := PI - atan2(-dir.z, -dir.x)
	var cap_name := unique_name("cap")
	var record := place("cap", cap_name, {"line_y": end.y}, to_global(Vector3(end.x, 0.0, end.z)), rot, false)
	if record == null:
		return "could not place the open end"
	(record as SimCap).open = true
	var corners: Array = waypoints.slice(0, waypoints.size() - 1)
	var why := connect_equipment(src_name, src_port, cap_name, "a", corners)
	if why != "":
		remove_equipment(cap_name)
		return why
	_sync_caps([cap_name])
	return ""


## Delete a corner of a fixed line (a right click on a cube): the
## waypoint goes, and the leg between its two
## neighbours — the next corners either side, or the stub ends — is
## auto-routed afresh, round solids, its corners becoming the line's.
## "" on success, else why not.
func delete_wire_corner(view: PipeView, point: Vector3) -> String:
	for visual in _wire_visuals:
		if visual["node"] != view:
			continue
		var waypoints: Array = (visual["waypoints"] as Array).duplicate()
		var k := -1
		for i in waypoints.size():
			if (waypoints[i] as Vector3).distance_to(point) < 0.01:
				k = i
				break
		if k < 0:
			return "that corner is the line's stub — it follows the fitting"
		for lock: Vector3 in visual.get("locks", []):
			if lock.distance_to(point) < 0.01:
				return "that corner is locked — middle-click it to unlock"
		checkpoint()
		waypoints.remove_at(k)
		var a := str(visual["a"])
		var b := str(visual["b"])
		var a_port := str(visual["a_port"])
		var b_port := str(visual["b_port"])
		var from := _marker_pos(a, a_port)
		var to := _marker_pos(b, b_port)
		var stub_a := from + _marker_dir(a, a_port) * _stub_of(a, a_port, view.radius())
		var stub_b := to + _marker_dir(b, b_port) * _stub_of(b, b_port, view.radius())
		var prev: Vector3 = waypoints[k - 1] if k > 0 else stub_a
		var next: Vector3 = waypoints[k] if k < waypoints.size() else stub_b
		var before_prev: Vector3 = waypoints[k - 2] if k > 1 else (stub_a if k == 1 else from)
		var d_in := (prev - before_prev).normalized()
		var radius := view.radius()
		var ctx := clearance.context([a, b], from, to, radius)
		var leg := PipeRoute.leg_avoiding(prev, next, d_in, clearance.router_blocked.bind(ctx),
			clearance.busy.bind([a], int(visual.get("order", ORDER_ALL))), [from, to])
		# The leg's corners, short of its end, are the line's now.
		var fresh: Array = []
		for i in range(leg.size() - 1):
			fresh.append(leg[i])
		for i in fresh.size():
			waypoints.insert(k + i, fresh[i])
		visual["waypoints"] = waypoints
		_refresh_visual(visual)
		_bake(visual)
		_schedule_revalidate()
		return ""
	return "not a line"


## The two fittings of a wire, [a, a_port, b, b_port]: how a line is
## found again once its node has been laid anew.
func wire_ends(view: PipeView) -> Array:
	for visual in _wire_visuals:
		if visual["node"] == view:
			return [visual["a"], visual["a_port"], visual["b"], visual["b_port"]]
	return []


## The locked waypoints of a wire (plant-local positions): corners the
## player pinned, which no edit moves. Saved with the wire; a lock lapses with its
## waypoint.
func wire_locks(view: PipeView) -> Array:
	for visual in _wire_visuals:
		if visual["node"] == view:
			return (visual.get("locks", []) as Array).duplicate()
	return []


func set_wire_locks(view: PipeView, locks: Array) -> void:
	checkpoint()
	for visual in _wire_visuals:
		if visual["node"] == view:
			visual["locks"] = locks.duplicate()
			return


## The waypoints a wire is laid through (plant-local): the player's
## own, never the corners the router derives from them.
func wire_waypoints(view: PipeView) -> Array:
	for visual in _wire_visuals:
		if visual["node"] == view:
			return (visual["waypoints"] as Array).duplicate()
	return []


## The route a wire's player owns (plant-local): lane 0 through their
## waypoints, before any lane's sidestep or bridge, each waypoint a
## point of it exactly. What the handles stand on.
func wire_own_path(view: PipeView) -> Array[Vector3]:
	for visual in _wire_visuals:
		if visual["node"] == view:
			var out: Array[Vector3] = []
			for p: Vector3 in (visual["node"] as Node).get_meta("own_path", []):
				out.append(p)
			return out
	return []


## The path a wire's line is laid on (plant-local), or [] for a run
## that is not a wire.
func wire_path(view: PipeView) -> Array[Vector3]:
	for visual in _wire_visuals:
		if visual["node"] == view:
			return _visual_path(visual)
	return []


## The corners a line was routed through before its lane and bridges
## were added — the player's waypoints and the search's detours — as
## laid, plant-local: what becomes its waypoints when the player takes
## it in hand. The lane's sidesteps and a bridge's ramps are not
## corners of the line's own and are laid again over these.
func wire_corners(view: PipeView) -> Array:
	for visual in _wire_visuals:
		if visual["node"] == view:
			var out: Array = []
			for corner: Vector3 in visual.get("corners", []):
				out.append(corner)
			return out
	return []


## The next free name with a prefix among the placed records.
func unique_name(prefix: String) -> String:
	var index := 1
	while views.has("%s_%d" % [prefix, index]) or sim.get_component("%s_%d" % [prefix, index]) != null:
		index += 1
	return "%s_%d" % [prefix, index]


## A cap shows a blind flange on each nozzle without a line.
## An open end over an open-topped vessel lands what it spills in it.
## Geometry the plant knows and the kernel does not: the
## open nozzle's face, in plan inside the vessel's rim and above its
## top, names the vessel to the cap. Every open cap is asked again
## whenever the plant changes.
func _sync_catches() -> void:
	for name_: String in views:
		# A fill needle not over a line fills the open vessel under its tip.
		var needle := sim.get_component(name_) as SimFillNeedle
		if needle != null:
			needle.catch = null
			if needle.host == "":
				var tip := (views[name_] as Node3D).global_position + Vector3(0, FillNeedleView.TIP_Y, 0)
				var best_top := -INF
				for tank_name: String in views:
					var tank_rec := sim.get_component(tank_name) as SimTank
					if tank_rec == null or not tank_rec.open_top:
						continue
					var base := (views[tank_name] as Node3D).global_position
					var top := base.y + tank_rec.height_m
					if top < tip.y and top > best_top 							and Vector2(tip.x - base.x, tip.z - base.z).length() <= tank_rec.diameter_m / 2.0:
						best_top = top
						needle.catch = tank_rec
			continue
		var cap := sim.get_component(name_) as SimCap
		if cap == null:
			continue
		var cap_view := views[name_] as CapView
		if cap_view == null:
			continue
		cap.catch = _vessel_under(cap_view, cap)
		cap_view.set_landing(cap.catch, to_local(cap_view.to_global(cap_view.open_end_local())).y)


## The open-topped vessel the stream from an open end falls into: the
## highest whose rim holds the point where the stream comes down through
## the rim's height. The stream leaves along the pipe's axis at its real
## exit speed (SpillJet), so a trickle falls straight into a tank under
## the end and a strong jet can carry over it; with nothing flowing it is
## the vessel straight below. Kept honest because the kernel counts what
## lands in a vessel as delivered and the rest as spilled.
func _vessel_under(cap_view: CapView, cap: SimCap) -> SimTank:
	var side := 1.0 if cap_view.open_port() == "b" else -1.0
	var origin := cap_view.to_global(Vector3(side * 0.19, cap_view.line_y, 0))
	var axis := (cap_view.global_basis * Vector3(side, 0, 0)).normalized()
	var q := cap.spill_lps() if cap.open else 0.0
	var v0 := axis * SpillJet.exit_speed(q, cap_view.bore_diameter_m())
	var best: SimTank = null
	var best_top := -INF
	for name_: String in views:
		var tank_rec := sim.get_component(name_) as SimTank
		if tank_rec == null or not tank_rec.open_top:
			continue
		var tank_view := views[name_] as Node3D
		var base := tank_view.global_position
		var top := base.y + tank_rec.height_m
		var t := SpillJet.time_to(origin, v0, top)
		if t < 0.0 or origin.y < top:
			continue
		var hit := SpillJet.point_at(origin, v0, t)
		if Vector2(hit.x - base.x, hit.z - base.z).length() > tank_rec.diameter_m / 2.0:
			continue
		if top > best_top:
			best_top = top
			best = tank_rec
	return best


func _sync_caps(names: Array) -> void:
	for name_ in names:
		var view := views.get(str(name_)) as CapView
		if view == null:
			continue
		for port: String in ["a", "b"]:
			view.set_capped(port, visible_wire_count(str(name_), port) == 0)


## Drop the kernel wire behind a visual entry.
func _disconnect_visual(visual: Dictionary) -> void:
	var src := sim.get_component(str(visual["a"]))
	var dst := sim.get_component(str(visual["b"]))
	if src == null or dst == null:
		return
	sim.disconnect_ports(src, str(visual["a_port"]), dst, str(visual["b_port"]))


## Re-run the support rule over every routed run — wires and standalone
## infrastructure — updating brackets and alarm state. Called a few
## frames after geometry changes. A run excludes its own colliders so
## it can't count as its own support.
static func _same_path(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if (a[i] as Vector3).distance_to(b[i] as Vector3) > 0.05:
			return false
	return true


## Anything that changes what a run could be routed round asks for the
## deferred pass, and starts a fresh re-lay budget.
func _schedule_revalidate() -> void:
	_revalidate_in = 3
	_relay_round = 0
	_relay_capped = 0
	for visual in _wire_visuals:
		visual.erase("same_relay")  # the plant changed: everything is worth a look again
		visual.erase("relays")


func _revalidate_supports() -> void:
	var t0 := Time.get_ticks_msec()
	# The obstacle cells are the plant's solids, which the sweep's own
	# re-lays never change: cleared once per schedule, not every round.
	if _relay_round == 0:
		clearance.clear()
		PipeRoute.clear_cache()
	# Runs laid before physics knew the bodies round them: re-lay any
	# whose avoiding route now differs.
	# In laying order, each run out of place is re-laid before the next
	# is looked at, so a later run is checked against the earlier ones
	# as they now stand: one sweep settles it. A run yields only to
	# earlier runs, so the sweep cannot chase its own tail; the round
	# cap is a belt for the braces.
	var relaid := 0
	var t1 := Time.get_ticks_msec()
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		if bool(visual.get("fixed", false)):
			continue   # a fixed line never routes again: only a new line moves
		var order := int(visual.get("order", ORDER_ALL))
		var t_dec := Time.get_ticks_usec()
		var fresh := _avoided_corners(str(visual["a"]), str(visual["a_port"]),
			str(visual["b"]), str(visual["b_port"]), visual["waypoints"], order,
			(visual["node"] as PipeView).radius())
		_lay_us["dec_corners"] = int(_lay_us.get("dec_corners", 0)) + Time.get_ticks_usec() - t_dec
		var moved := fresh != (visual.get("corners", []) as Array)
		if not moved:
			# Same corners, but a lane laid blind may sit differently now
			# that physics knows what is beside it.
			var view := visual["node"] as PipeView
			_lane_room.clear()
			var t_lane_dec := Time.get_ticks_usec()
			var fresh_path := _with_jumpers(_route_points(str(visual["a"]), str(visual["a_port"]),
				str(visual["b"]), str(visual["b_port"]), fresh, int(visual.get("lane", 0)), view.radius()),
				view.radius(), visual, [str(visual["a"]), str(visual["b"])], order)
			_lay_us["dec_lane"] = int(_lay_us.get("dec_lane", 0)) + Time.get_ticks_usec() - t_lane_dec
			moved = not _same_path(fresh_path, visual.get("path", []))
		if not moved and not bool(visual.get("same_relay", false)):
			# Or an earlier run has moved onto it since it was laid.
			var stored: Array[Vector3] = _visual_path(visual)
			var view2 := visual["node"] as PipeView
			var t_checks := Time.get_ticks_usec()
			var collides := _path_collision(stored, view2.radius(), str(visual["a"]), str(visual["a_port"]),
				str(visual["b"]), str(visual["b_port"]), order) > 0.0
			var crossed := not _crossings(stored, view2.radius(), visual,
				[str(visual["a"]), str(visual["b"])], order).is_empty()
			_lay_us["dec_checks"] = int(_lay_us.get("dec_checks", 0)) + Time.get_ticks_usec() - t_checks
			moved = collides or crossed
		if not moved and not bool(visual.get("same_relay", false)):
			# Or its lane left it unsupported, laid before physics knew
			# what would carry it: another lane may pass now.
			moved = (visual["node"] as PipeView).is_unsupported()
		# A run re-laid twice already since the plant last changed is left
		# where it is: a knot of short cables at one cabinet can trade
		# lanes for ever, each moving because another did.
		if moved and int(visual.get("relays", 0)) >= 2:
			moved = false
			_relay_capped += 1
		if moved and _relay_round < RELAY_ROUNDS:
			_refresh_visual(visual)
			relaid += 1
		elif moved:
			_relay_capped += 1
	if relaid > 0:
		_relay_round += 1
		_revalidate_in = 3  # once more, to confirm it settled
	else:
		# Settled: what the router decided is now what each new line is.
		for visual in _wire_visuals:
			if visual["node"] != null and not bool(visual.get("fixed", false)):
				_bake(visual)
	var t2 := Time.get_ticks_msec()
	var relay := []
	relay.resize(relaid)
	var space := get_world_3d().direct_space_state
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue  # internal cabinet wire, nothing physical to carry
		_apply_support_path(visual["node"] as PipeView, _visual_path(visual), space)
	_pedestal_pass(space)
	_sync_catches()
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		_apply_support(entry["node"] as PipeView, entry["points"], space)
	if DisplayServer.get_name() == "headless":
		print("[flowstate] revalidate: corners %d ms, re-lay %d ms (%d runs%s; %s ms), supports %d ms"
			% [t1 - t0, t2 - t1, relay.size(),
				(", %d more past the round cap" % _relay_capped) if _relay_capped > 0 else "",
				_lay_phases(), Time.get_ticks_msec() - t2])


## Runs sharing the same space: every
## pair of parallel segments closer than their two radii for longer
## than min_length, worst first. Trays are left out: a conduit in a
## tray is where it belongs.
func overlap_report(min_length: float = 0.5) -> PackedStringArray:
	var paths: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		var view := visual["node"] as PipeView
		if view.style() == "tray":
			continue
		var shown := "%s.%s -> %s.%s [lane %d]" % [visual["a"], visual["a_port"], visual["b"],
				visual["b_port"], int(visual.get("lane", 0))]
		if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
			shown += " path %s" % str(_visual_path(visual))
		paths.append({"name": shown,
			"path": _visual_path(visual), "r": view.radius(),
			"from": "%s.%s" % [visual["a"], visual["a_port"]], "to": "%s.%s" % [visual["b"], visual["b_port"]]})
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		var view := entry["node"] as PipeView
		if view.style() == "tray":
			continue
		paths.append({"name": name_, "path": PipeRoute.lay(entry["points"]), "r": view.radius(),
			"from": "", "to": ""})
	var found: Array = []
	for i in paths.size():
		var pa: Array = paths[i]["path"]
		for j in range(i + 1, paths.size()):
			var pb: Array = paths[j]["path"]
			var gap := float(paths[i]["r"]) + float(paths[j]["r"])
			var worst := 0.0
			var where := Vector3.ZERO
			for s in range(pa.size() - 1):
				for t in range(pb.size() - 1):
					var got := _segment_overlap(pa[s], pa[s + 1], pb[t], pb[t + 1], gap)
					if got[0] > worst:
						worst = got[0]
						where = got[1]
			var allowed := _allowed_overlap(str(paths[i]["from"]).get_slice(".", 0),
				str(paths[i]["to"]).get_slice(".", 0), str(paths[j]["from"]).get_slice(".", 0),
				str(paths[j]["to"]).get_slice(".", 0), where)
			if worst >= maxf(min_length, allowed):
				found.append([worst, "%s ∥ %s for %.1f m near (%.1f, %.1f, %.1f)" % [
					paths[i]["name"], paths[j]["name"], worst, where.x, where.y, where.z]])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var lines := PackedStringArray()
	for hit: Array in found:
		lines.append(str(hit[1]))
	return lines


## Every port carrying more than one wire: a nozzle or a terminal
## takes one line; joining and splitting is a fitting's job, with its
## own separated connection points.
func fanout_report() -> PackedStringArray:
	var counts: Dictionary = {}
	for wire in sim.wires:
		for port in [wire.src, wire.dst]:
			var key: String = port.path()
			counts[key] = int(counts.get(key, 0)) + 1
	var lines := PackedStringArray()
	for key: String in counts:
		if int(counts[key]) > 1:
			lines.append("%s carries %d wires" % [key, int(counts[key])])
	lines.sort()
	return lines


## The stretch of segment ab that lies within gap of segment ce, at
## whatever angle they meet: [length, its midpoint]. For parallel
## segments it is the length they run side by side; for segments
## that cross it is short, and the steeper the crossing the shorter
## (a right angle gives about a pipe's width, which no rule minds);
## a shallow crossing is a long stretch, and is the lanes' business like a parallel one.
static func _segment_overlap(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3,
		gap: float) -> Array:
	var da := a1 - a0
	var db := b1 - b0
	var la := da.length()
	var lb := db.length()
	if la < 1e-6 or lb < 1e-6:
		return [0.0, Vector3.ZERO]
	var na := da / la
	var nb := db / lb
	var r := a0 - b0
	var c := na.dot(nb)
	var u := na - nb * c              # how fast a point along ab leaves the line of ce
	var w := r - nb * r.dot(nb)       # where a0 stands off that line
	var lo := 0.0
	var hi := la
	var uu := u.dot(u)
	if uu < 1e-6:
		if w.length() > gap:
			return [0.0, Vector3.ZERO]
	else:
		# |w + u s|^2 <= gap^2 is a quadratic in s.
		var half_b := w.dot(u) / uu
		var disc := half_b * half_b - (w.dot(w) - gap * gap) / uu
		if disc < 0.0:
			return [0.0, Vector3.ZERO]
		var root := sqrt(disc)
		lo = maxf(lo, -half_b - root)
		hi = minf(hi, -half_b + root)
	# And within ce's own extent.
	var t0 := r.dot(nb)               # a0 projected along ce
	if absf(c) < 1e-6:
		if t0 < -gap or t0 > lb + gap:
			return [0.0, Vector3.ZERO]
	else:
		var s_lo := -t0 / c
		var s_hi := (lb - t0) / c
		lo = maxf(lo, minf(s_lo, s_hi))
		hi = minf(hi, maxf(s_lo, s_hi))
	if hi <= lo:
		return [0.0, Vector3.ZERO]
	return [hi - lo, a0 + na * ((lo + hi) / 2.0)]


func _apply_support(view: PipeView, sparse_local: Array, space: PhysicsDirectSpaceState3D) -> void:
	_apply_support_path(view, PipeRoute.lay(sparse_local), space)


func _apply_support_path(view: PipeView, path: Array[Vector3],
		space: PhysicsDirectSpaceState3D) -> void:
	var global_path: Array[Vector3] = []
	for point in path:
		global_path.append(to_global(point))
	var result := SupportCheck.evaluate(global_path, space, view.collider_rids())
	var local_brackets: Array[Dictionary] = []
	for bracket: Dictionary in result["brackets"]:
		local_brackets.append({"from": to_local(bracket["from"]), "to": to_local(bracket["to"])})
	view.set_supports(local_brackets, not bool(result["ok"]))
	if not bool(result["ok"]):
		view.set_meta("unsupported_at", to_local(result["worst_at"]))
		view.set_meta("unsupported_span", float(result["max_span"]))


## Set before a connect whose waypoints are already the line's corners
## (a save's fixed line, a cut's pieces): the line is laid fixed.
var _next_wire_fixed := false
## The size the next line is laid at (default DN50): a code-laid line
## on tubing takes its size before its first lay, so the stubs and
## the fittings are right from the start rather than after a re-lay.
var _next_wire_dn := 50


func next_line_size(dn: int) -> void:
	_next_wire_dn = dn if LINE_SIZES.has(dn) else 50


var _pending_dn: Dictionary = {}   # name -> the size of a line about to land on it


func _wire_visual(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array) -> void:
	var order := _wire_serial
	_wire_serial += 1
	var fixed := _next_wire_fixed
	_next_wire_fixed = false
	var dn := _next_wire_dn
	_next_wire_dn = 50
	if dn != 50:
		# The fittings at both ends take the line's size before its first
		# lay: laid against DN50 bodies that a close train of tube
		# devices overlaps, every leg would detour and keep its lane for
		# good.
		_pending_dn = {src_name: dn, dst_name: dn}
		_sync_bores([src_name, dst_name])
		_pending_dn = {}
	var pipe := _build_pipe(src_name, src_port, dst_name, dst_port, waypoints, -1, 0, order, fixed, dn)
	_wire_visuals.append({
		"node": pipe, "a": src_name, "a_port": src_port,
		"b": dst_name, "b_port": dst_port, "waypoints": waypoints,
		"color": "", "label": "", "order": order, "fixed": fixed, "dn": dn,
		"lane": int(pipe.get_meta("lane", 0)), "path": pipe.get_meta("path", []),
		"corners": pipe.get_meta("corners", []), "base_path": pipe.get_meta("base_path", []),
	})
	_sync_line_resistance(_wire_visuals[_wire_visuals.size() - 1])
	_schedule_revalidate()


## Bake a line: its waypoints become the corners it is drawn with —
## every sidestep, bridge, detour and square leg the router decided —
## and from then on it is laid plainly through them and never routed
## again. The fittings and their stubs are not corners: they follow the equipment.
func _bake(visual: Dictionary) -> void:
	var node := visual["node"] as PipeView
	if node == null:
		return
	var path: Array = visual.get("path", [])
	if path.size() < 4:
		return
	var a := str(visual["a"])
	var b := str(visual["b"])
	var from := _marker_pos(a, str(visual["a_port"]))
	var to := _marker_pos(b, str(visual["b_port"]))
	var ends: Array[Vector3] = [from, from + _marker_dir(a, str(visual["a_port"])) * _stub_of(a, str(visual["a_port"]), node.radius()),
		to + _marker_dir(b, str(visual["b_port"])) * _stub_of(b, str(visual["b_port"]), node.radius()), to]
	var waypoints: Array = []
	for p: Vector3 in path:
		var at_end := false
		for e in ends:
			if p.distance_to(e) < 0.001:
				at_end = true
				break
		if not at_end:
			waypoints.append(p)
	visual["waypoints"] = waypoints
	visual["corners"] = waypoints.duplicate()
	visual["fixed"] = true
	visual["lane"] = 0
	node.set_meta("corners", waypoints.duplicate())
	node.set_meta("own_path", path.duplicate())
	node.set_meta("base_path", path.duplicate())
	node.set_meta("lane", 0)
	# A lock stays while its waypoint does.
	var kept: Array = []
	for lock: Vector3 in visual.get("locks", []):
		for w: Vector3 in waypoints:
			if w.distance_to(lock) < 0.01:
				kept.append(lock)
				break
	visual["locks"] = kept


## `order`: the run's place in the laying order. It is laid round the
## runs before it and never reacts to the ones after: when two runs
## both shift to avoid each other they still meet, so one stays where
## it is and only the other moves. Lanes,
## bridges and the router's busy cells all keep to it, so a sweep in
## order settles in one pass.
## The route a line takes, in full: its corners round what is solid,
## its lane, its bridges. {lane, path, corners, searched, base_path}.
## Shared by the lay itself and the preview a player sees while
## routing, so the preview ends at the nozzle's stub where the line lands.
func _lay_route(src_name: String, src_port: String, dst_name: String, dst_port: String,
		waypoints: Array, lane: int, preferred: int, order: int, radius: float,
		fixed: bool = false) -> Dictionary:
	if fixed:
		# A fixed line: its waypoints are its
		# corners, laid plainly, stub to stub, no search, no lane, no
		# bridge — those were decided once and baked into the waypoints.
		var plain := _route_points(src_name, src_port, dst_name, dst_port, waypoints, 0, radius)
		return {"lane": 0, "path": plain, "corners": waypoints.duplicate(), "searched": false,
			"base_path": plain, "own_path": plain}
	var chosen := lane
	var path: Array[Vector3] = []
	var t_start := Time.get_ticks_usec()
	var corners := _avoided_corners(src_name, src_port, dst_name, dst_port, waypoints, order, radius)
	_lay_us["corners"] = int(_lay_us.get("corners", 0)) + Time.get_ticks_usec() - t_start
	var lay_ctx := clearance.context([src_name, dst_name], _marker_pos(src_name, src_port),
		_marker_pos(dst_name, dst_port), radius)
	t_start = Time.get_ticks_usec()
	var searched := PipeRoute.last_searched
	_lane_room.clear()  # the room beside each leg is this run's, for its lanes
	if chosen < 0:
		# The lane with the fewest bends that shares no stretch with an
		# earlier run: a crossing costs the four bends of a bridge, so a
		# tier that clears it outright wins over hopping it.
		var best_lane := 0
		var best_cost := INF
		var best_overlap := 0.0
		# The lane a run already had is tried first: a run re-laid by the
		# deferred pass that keeps its lane moves nothing else.
		var targets := _crossing_targets({}, [src_name, dst_name], order)
		var lane_order: Array[int] = []
		if preferred > 0:
			lane_order.append(preferred)
		lane_order.append(0)  # lane 0, the route as laid, is always tried
		# Then sideways steps before tiers: a tier lifts a
		# run, and a lifted drop beside a column leaves the floor's reach,
		# so every step out on the ground is tried before the first lift.
		var rest: Array[int] = []
		for try_lane in range(1, 2 * LANE_TIERS * LANE_STEPS + 1):
			if try_lane != preferred:
				rest.append(try_lane)
		rest.sort_custom(func(x: int, y: int) -> bool: return _lane_rank(x) < _lane_rank(y))
		lane_order.append_array(rest)
		var costs := PackedStringArray()
		for try_lane in lane_order:
			var t_lane := Time.get_ticks_usec()
			var candidate := _route_points(src_name, src_port, dst_name, dst_port, corners, try_lane, radius)
			_lay_us["points"] = int(_lay_us.get("points", 0)) + Time.get_ticks_usec() - t_lane
			t_lane = Time.get_ticks_usec()
			var overlap := _path_collision(candidate, radius, src_name, src_port, dst_name, dst_port, order)
			_lay_us["collision"] = int(_lay_us.get("collision", 0)) + Time.get_ticks_usec() - t_lane
			t_lane = Time.get_ticks_usec()
			var cost := 0.0
			if overlap > 0.0:
				cost += 1000.0 + overlap
			var crossed := _crossings(candidate, radius, {}, [src_name, dst_name], order, 0.03, targets)
			_lay_us["crossings"] = int(_lay_us.get("crossings", 0)) + Time.get_ticks_usec() - t_lane
			cost += 4.0 * crossed.size()
			# A tier can lift a ground run out of reach of the floor: a lane
			# the support rule refuses costs more than any crossing, since a
			# crossing is bridged and an unsupported span is a rule broken.
			# Checked only for a lane that would win, it is a few physics
			# queries a lay.
			if cost < best_cost:
				var t_check := Time.get_ticks_usec()
				if not _lane_supported(candidate):
					cost += 50.0
				_lay_us["support"] = int(_lay_us.get("support", 0)) + Time.get_ticks_usec() - t_check
			# And through nothing solid: a lane's sidestep or tier can put
			# a run into a column or a neighbouring machine the plain route
			# cleared. Checked for a lane that would
			# win, like the support rule.
			if cost < best_cost:
				var t_check := Time.get_ticks_usec()
				cost += 200.0 * clearance.hits(candidate, lay_ctx).size()
				_lay_us["solid"] = int(_lay_us.get("solid", 0)) + Time.get_ticks_usec() - t_check
			costs.append("%d:%.0f%s" % [try_lane, cost,
				("@(%.1f,%.1f,%.1f)" % [_last_overlap_at.x, _last_overlap_at.y, _last_overlap_at.z])
					if overlap > 0.0 and OS.has_environment("FLOWSTATE_ROUTE_DEBUG") else ""])
			if costs.size() == 1 and OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
				var names: Array = []
				for crossing in crossed:
					names.append("%s@%.1f" % [crossing["other"], float(crossing["at"])])
				if overlap > 0.0:
					names.append("overlap %.2f m at %s" % [overlap, _last_overlap_at])
				costs.append("(%s)" % ", ".join(names))
			if cost < best_cost:
				best_cost = cost
				best_overlap = overlap
				best_lane = try_lane
				path = candidate
			if cost <= 0.0:
				break
		chosen = best_lane
		if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
			print("[lane] %s.%s -> %s.%s: lane %d%s; costs %s" % [src_name, src_port, dst_name, dst_port, chosen,
				(" still overlaps %.2f m" % best_overlap) if best_overlap > 0.0 else "", " ".join(costs)])
	else:
		path = _route_points(src_name, src_port, dst_name, dst_port, corners, chosen, radius)
	_lay_us["lanes"] = int(_lay_us.get("lanes", 0)) + Time.get_ticks_usec() - t_start
	t_start = Time.get_ticks_usec()
	var base_path := path
	# The route the player owns: lane 0 through their waypoints, every
	# one of which is a point of it exactly. The handles stand on it:
	# the lane pass moves the drawn corners, so they are never matched
	# back to waypoints by distance.
	var own_path := base_path if chosen == 0 else _route_points(src_name, src_port, dst_name, dst_port,
		corners, 0, radius)
	path = _with_jumpers(path, radius, {}, [src_name, dst_name], order)
	_lay_us["bridges"] = int(_lay_us.get("bridges", 0)) + Time.get_ticks_usec() - t_start
	if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
		print("[laid] %s.%s -> %s.%s lane %d: %s" % [src_name, src_port, dst_name, dst_port, chosen, str(path)])
	return {"lane": chosen, "path": path, "corners": corners, "searched": searched, "base_path": base_path,
		"own_path": own_path}


# Where a lay's time goes, summed over a sweep: corners (the search),
# lanes (the loop, of which support and solid are the two checks on a
# would-be winner), bridges. Printed with the revalidate line headless.
var _lay_us: Dictionary = {}


func _lay_phases() -> String:
	var parts := PackedStringArray()
	for key: String in ["corners", "lanes", "points", "collision", "crossings", "support", "solid", "bridges",
			"dec_corners", "dec_lane", "dec_checks"]:
		parts.append("%s %d" % [key, int(_lay_us.get(key, 0)) / 1000])
	_lay_us.clear()
	return " ".join(parts)


## The path a line would be laid on, world-space, for the preview:
## the same route, lane and bridges the lay would choose, laid as the
## next run in order. Costly on a big plant (the lane search), so the
## caller asks only when the target or the waypoints change.
func preview_route(src_name: String, src_port: String, dst_name: String, dst_port: String,
		waypoints: Array) -> Array[Vector3]:
	var src := sim.get_component(src_name)
	var dst := sim.get_component(dst_name)
	if src == null or dst == null or not src.outputs.has(src_port) or not dst.inputs.has(dst_port):
		return []
	var radius := run_radius(src.outputs[src_port] as SimOutputPort)
	var local: Array = []
	for point: Vector3 in waypoints:
		local.append(to_local(point))
	var laid := _lay_route(src_name, src_port, dst_name, dst_port, local, -1, 0, _wire_serial, radius)
	var out: Array[Vector3] = []
	for point: Vector3 in laid["path"]:
		out.append(to_global(point))
	return out


## What a route (world-space) would pass through, by the clearance
## rule, as the owners' names — empty when it is clear. The preview
## names them and the lay refuses them: it is the player's
## responsibility not to route where it is truly impossible; the
## game's part is to say so rather than thread the line through.
func route_obstacles(path_global: Array, src_name: String, dst_name: String, radius: float) -> PackedStringArray:
	var out := PackedStringArray()
	if path_global.size() < 2:
		return out
	var local: Array[Vector3] = []
	for point: Vector3 in path_global:
		local.append(to_local(point))
	var own: Array = []
	if src_name != "":
		own.append(src_name)
	if dst_name != "":
		own.append(dst_name)
	var ctx := clearance.context(own, local[0], local[local.size() - 1], radius)
	for hit: Dictionary in clearance.hits(local, ctx):
		var owner: Variant = hit["owner"]
		var name_ := str(owner)
		if owner is String and name_.begins_with("structure:"):
			name_ = name_.trim_prefix("structure:")
		elif not (owner is String):
			name_ = "the building"
		if not out.has(name_):
			out.append(name_)
	return out


## The player's connect: laid, then held to the clearance rule. A line
## whose route passes through something comes out again and the reason
## is returned, like the support rule's veto.
func connect_equipment_checked(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array = []) -> String:
	var why := connect_equipment(src_name, src_port, dst_name, dst_port, waypoints)
	if why != "":
		return why
	var visual: Dictionary = _wire_visuals[_wire_visuals.size() - 1]
	var view := visual["node"] as PipeView
	if view == null:
		return ""
	var path: Array[Vector3] = _visual_path(visual)
	var path_global: Array = []
	for point: Vector3 in path:
		path_global.append(to_global(point))
	var through := route_obstacles(path_global, src_name, dst_name, view.radius())
	if through.is_empty():
		return ""
	remove_run(view)
	return "no clear route: it would pass through %s — route round it or move it" % ", ".join(through)


## The bore a line meets at a record: an inline fitting's own (built at
## the bore of the biggest line on it), or the nozzle's own, which is
## the size of the line on it once one has landed, and DN50 before.
func _end_bore(name_: String, port_: String = "") -> float:
	var view: Node3D = views.get(name_)
	if view == null:
		return LINE_RADIUS_DN50
	if PlantFactory.INLINE_FLUSH.has(str(equip_types.get(name_, ""))):
		return float(view.get("bore"))
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Variant = markers.get("%s:%s" % [name_, port_])
	if marker is Node and is_instance_valid(marker) and (marker as Node).has_meta("bore"):
		return float((marker as Node).get_meta("bore"))
	return LINE_RADIUS_DN50


## The nominal size of the material line on one port of a record, 0
## with none: what its nozzle is built to. A cable is a wire visual of
## style pipe too, so the source port's kind decides.
func _line_dn_on(name_: String, port_: String) -> int:
	for visual in _wire_visuals:
		if visual["node"] == null or not (visual["node"] is PipeView):
			continue
		var on_a := str(visual["a"]) == name_ and str(visual["a_port"]) == port_
		var on_b := str(visual["b"]) == name_ and str(visual["b_port"]) == port_
		if not on_a and not on_b:
			continue
		if (visual["node"] as PipeView).style() != "pipe":
			continue
		var src := sim.get_component(str(visual["a"]))
		if src == null or not src.outputs.has(str(visual["a_port"])) \
				or not SimTypes.is_material((src.outputs[str(visual["a_port"])] as SimOutputPort).kind):
			continue
		return int(visual.get("dn", 50))
	return 0


## The material lines on a record, as wire visuals.
func _material_lines_on(name_: String) -> Array:
	var lines: Array = []
	for visual in _wire_visuals:
		if visual["node"] == null or not (visual["node"] is PipeView):
			continue
		if str(visual["a"]) != name_ and str(visual["b"]) != name_:
			continue
		if (visual["node"] as PipeView).style() != "pipe":
			continue
		var src := sim.get_component(str(visual["a"]))
		if src == null or not src.outputs.has(str(visual["a_port"])) \
				or not SimTypes.is_material((src.outputs[str(visual["a_port"])] as SimOutputPort).kind):
			continue
		lines.append(visual)
	return lines


## Free a view's port fittings and the meshes they were merged into.
func _free_markers(view: Node3D) -> void:
	var markers: Dictionary = view.get_meta("port_markers", {})
	for key: String in markers:
		var marker := markers[key] as Node
		if is_instance_valid(marker):
			marker.queue_free()
	view.set_meta("port_markers", {})
	for child in view.get_children():
		if child.has_meta("merged_markers"):
			view.remove_child(child)
			child.queue_free()


## A nozzle is built at the size of the line on it: each material
## port of a record that is not an inline fitting gets a fitting at
## its own line's bore, DN50 with none, and a tank's kernel nozzle
## takes the size too, so its Cv follows the bore. Rebuilt when any
## port's size changes, its lines laid again to meet the new fitting.
func _sync_nozzle_bores(name_: String, type_id: String, view: Node3D, record: SimComponent) -> bool:
	var pending := int(_pending_dn.get(name_, 0))
	var hidden := record.hidden_ports()
	var wanted: Dictionary = {}   # port -> radius
	var dns: Dictionary = {}      # port -> dn
	for port_name: String in record.material_ports():
		if hidden.has(port_name):
			continue
		if mounted.has(name_) and str(PlantFactory.MOUNTED_INPUT.get(type_id, "")) == port_name:
			continue
		var dn := _line_dn_on(name_, port_name)
		if dn == 0:
			dn = pending if pending > 0 else 50
		dns[port_name] = dn
		wanted[port_name] = line_radius(dn)
	if wanted.is_empty():
		return false
	var changed := false
	if view is TankView:
		var tank_view := view as TankView
		var tank := record as SimTank
		for port_name: String in wanted:
			tank.set_nozzle_dn(port_name, int(dns[port_name]))
			if tank_view.set_nozzle_bore(port_name, float(wanted[port_name])):
				changed = true
		return changed
	var markers: Dictionary = view.get_meta("port_markers", {})
	for port_name: String in wanted:
		var marker: Variant = markers.get("%s:%s" % [name_, port_name])
		if not (marker is Node) or not is_instance_valid(marker):
			continue
		if absf(float((marker as Node).get_meta("bore", LINE_RADIUS_DN50)) - float(wanted[port_name])) > 0.001:
			changed = true
	if not changed:
		return false
	_free_markers(view)
	var skip: Array[String] = []
	var anchors: Dictionary = {}
	if mounted.has(name_):
		skip = [str(PlantFactory.MOUNTED_INPUT[type_id])]
		anchors = PlantFactory.MOUNTED_ANCHORS.get(type_id, {})
	elif type_id == "mains":
		anchors = PlantFactory.mains_anchors((record as SimMainsFeed).ways)
	PlantFactory.attach_port_markers(view, record, type_id, anchors, skip, LINE_RADIUS_DN50, wanted)
	return true


## An inline fitting is bought in the line size:
## its body is built at the bore of the biggest material line on it,
## and rebuilt — body, fittings, merge — when that changes, the lines
## on it laid again so their ends take the new bore.
func _sync_bores(names: Array) -> void:
	var touched := false
	for name_ in names:
		var type_id := str(equip_types.get(str(name_), ""))
		var view: Node3D = views.get(str(name_))
		var record := sim.get_component(str(name_))
		if view == null or record == null:
			continue
		if not PlantFactory.INLINE_FLUSH.has(type_id):
			# A nozzle takes the size of its own line.
			if _sync_nozzle_bores(str(name_), type_id, view, record):
				clearance.clear()
				for visual in _material_lines_on(str(name_)):
					_refresh_visual(visual)
				touched = true
			continue
		var dn := 0   # the biggest line on it; DN50 with none (a fresh fitting)
		var lines: Array = []
		for visual in _wire_visuals:
			if visual["node"] == null or not (visual["node"] is PipeView):
				continue
			if str(visual["a"]) != str(name_) and str(visual["b"]) != str(name_):
				continue
			if (visual["node"] as PipeView).style() != "pipe":
				continue
			# Material lines only: a cable landing on a pump or a coil is
			# a wire visual too, and it sizes nothing.
			var src := sim.get_component(str(visual["a"]))
			if src == null or not src.outputs.has(str(visual["a_port"])) 					or not SimTypes.is_material((src.outputs[str(visual["a_port"])] as SimOutputPort).kind):
				continue
			dn = maxi(dn, int(visual.get("dn", 50)))
			lines.append(visual)
		dn = maxi(dn, int(_pending_dn.get(str(name_), 0)))
		if dn == 0:
			dn = 50
		if record.get("dn") != null:
			dn = int(record.get("dn"))   # its own size, never the lines'
		var r := line_radius(dn)
		if absf(float(view.get("bore")) - r) < 0.001:
			continue
		var markers: Dictionary = view.get_meta("port_markers", {})
		for key: String in markers:
			var marker := markers[key] as Node
			if is_instance_valid(marker):
				marker.queue_free()
		view.set_meta("port_markers", {})
		view.call("set_bore", r)
		MeshMerge.merge_view(view)
		if type_id == "cap":
			PlantFactory.attach_port_markers(view, record, type_id,
				PlantFactory.cap_anchors((view as CapView).line_y), [], r)
		else:
			PlantFactory.attach_port_markers(view, record, type_id,
				PlantFactory.anchors_for(type_id, r), [], r)
		if type_id == "cap":
			_sync_caps([str(name_)])
		clearance.clear()   # the fittings just freed may sit in its cells
		for visual in lines:
			_refresh_visual(visual)
		touched = true
	if touched:
		_schedule_revalidate()


## Line sizes: nominal bores, DN50 the reference (drawn at radius
## 0.07), the rest scaled with it; a
## line's resistance is its length and bends at its bore
## (SimHydraulics.pipe_k), so it falls as the fifth power of the bore.
## Down to a millimetre: a metre of DN1
## passes about 5 mL/s at 4 bar (turbulent friction; a real capillary
## is laminar and passes less).
const LINE_SIZES: Array[int] = [1, 2, 3, 6, 10, 15, 25, 40, 50, 80, 100, 150]
const LINE_RADIUS_DN50 := 0.07


static func line_radius(dn: int) -> float:
	return LINE_RADIUS_DN50 * float(dn) / 50.0


const FEEDER_RADIUS := 0.025   # a 480 V feeder, 50 mm across
const CABLE_RADIUS := 0.004    # a 24 V or signal cable, 8 mm across


## The drawn radius of a run on this port: a process line at DN50 (its
## own bore once laid), a 480 V feeder, or a cable.
static func run_radius(port: SimPort) -> float:
	if SimTypes.is_material(port.kind) or port.kind == SimTypes.PortKind.PROCESS_LEVEL:
		return LINE_RADIUS_DN50
	if port.kind == SimTypes.PortKind.POWER and port.spec.ends_with("VAC"):
		return FEEDER_RADIUS
	return CABLE_RADIUS


func _build_pipe(src_name: String, src_port: String, dst_name: String, dst_port: String,
		waypoints: Array, lane: int = -1, preferred: int = 0, order: int = ORDER_ALL,
		fixed: bool = false, dn: int = 50) -> PipeView:
	var src := sim.get_component(src_name)
	var port: SimOutputPort = src.outputs[src_port]
	var kind := port.kind
	var getter: Callable
	var wire: SimWire = null
	if SimTypes.is_material(kind):
		# The honest live value of a pipe is the flow the network solved
		# through it. An instrument tap has no branch of its own and
		# reads the line it is tapped into.
		wire = sim.find_wire(src, src_port, sim.get_component(dst_name), dst_port)
		getter = func() -> float:
			if wire == null:
				return 0.0
			if wire.branch != null:
				return absf(wire.branch.flow_lps)
			return wire.dst.stream.flow_lps
	else:
		getter = func() -> float: return port.value
	var is_process := SimTypes.is_material(kind) \
		or kind == SimTypes.PortKind.PROCESS_LEVEL
	var radius := line_radius(dn) if is_process else run_radius(port)
	# The lane: the first one whose route does not lie inside a run
	# already laid. A run without
	# waypoints has nothing to shift and takes the route as it comes.
	var laid := _lay_route(src_name, src_port, dst_name, dst_port, waypoints, lane, preferred, order, radius, fixed)
	var chosen: int = laid["lane"]
	var path: Array[Vector3] = laid["path"]
	var corners: Array = laid["corners"]
	var searched: bool = laid["searched"]
	var base_path: Array[Vector3] = laid["base_path"]
	var own_path: Array[Vector3] = laid["own_path"]
	var pipe := PipeView.new()
	add_child(pipe)
	# A fitting is built at the bore of its line (a nozzle its own
	# line's, an inline fitting the biggest on it): a line of another
	# size meets it through a reducer.
	pipe.end_radius_a = _end_bore(src_name, src_port) if is_process else radius
	pipe.end_radius_b = _end_bore(dst_name, dst_port) if is_process else radius
	pipe.setup(path, getter, PlantFactory.KIND_COLORS[kind], radius,
		"%s.%s -> %s.%s" % [src_name, src_port, dst_name, dst_port])
	pipe.set_meta("lane", chosen)
	pipe.set_meta("path", path)
	pipe.set_meta("corners", corners)
	pipe.set_meta("src", src_name)
	pipe.set_meta("searched", searched)
	pipe.set_meta("base_path", base_path)
	pipe.set_meta("own_path", own_path)
	pipe.set_meta("order", order)
	pipe.config_cb = _configure_run
	if wire != null:
		# A line can be pressurised without moving: a dead-headed
		# discharge, a full riser under a stopped pump. Show that too.
		var live := wire
		var kernel := sim
		pipe.set_pressure_getter(func() -> float:
			return maxf(kernel.pressure_at(live.src), kernel.pressure_at(live.dst)))
	return pipe


## Does the support rule pass a candidate route as it would be laid?
func _lane_supported(path: Array[Vector3]) -> bool:
	var global_path: Array[Vector3] = []
	for point in path:
		global_path.append(to_global(point))
	return bool(SupportCheck.evaluate(global_path, get_world_3d().direct_space_state)["ok"])


## A run's route in its lane: the waypoints shifted sideways so runs
## that share a corridor lie side by side instead of inside each other
## Lane 0 is the route as laid;
## lanes 1, 2, 3… step out alternately either side, and the step is
## diagonal so legs along x and legs along z both move over.
func _route_points(src_name: String, src_port: String, dst_name: String, dst_port: String,
		corners: Array, lane: int, radius: float) -> Array[Vector3]:
	var from := _marker_pos(src_name, src_port)
	var from_dir := _marker_dir(src_name, src_port)
	var to := _marker_pos(dst_name, dst_port)
	var to_dir := _marker_dir(dst_name, dst_port)
	var lane_ctx := clearance.context([src_name, dst_name], from, to, radius)
	var squaring := clearance.router_blocked.bind(lane_ctx)   # a square-turn leg goes the clear way
	var sa := _stub_of(src_name, src_port, radius)
	var sb := _stub_of(dst_name, dst_port, radius)
	var base := PipeRoute.routed(from, from_dir, to, to_dir, corners, squaring, sa, sb)
	if lane <= 0:
		return base
	if not _has_level_corner(base):
		# A run with no corner on its horizontal has nothing a lane can
		# shift once the stub ends are fixed (a plumb drop under a stub
		# moves with the stub): give it one at the middle of its longest
		# level leg, so the lane bends it there in two shallow angles.
		# Added to its corners, never in their place: replacing them lays
		# a line raised by its two riser corners back on the ground.
		base = PipeRoute.routed(from, from_dir, to, to_dir, _with_mid_corner(base, corners), squaring, sa, sb)
	# Lane slots: either side, then the same two one tier up, then a
	# step further out. A tier is a run's width, the way cables stack
	# in a tray; a whole tier would carry a ground run past the
	# support rule's reach.
	var slot := lane - 1
	var side := 1 if slot % 2 == 0 else -1
	@warning_ignore("integer_division")
	var tier := (slot / 2) % LANE_TIERS
	@warning_ignore("integer_division")
	var k := slot / (2 * LANE_TIERS) + 1
	var step := 2.0 * radius + 0.03
	var lift := tier * (step + 0.02)
	# Room is probed at the tier's own height: a lifted lane checked at
	# the base level could rise into a valve or a beam the base route
	# passed under.
	var room_key := "%s.%s>%s.%s|%d|%d" % [src_name, src_port, dst_name, dst_port, side, tier]
	if not _lane_room.has(room_key):
		_lane_room[room_key] = _leg_room(base, side, step, lift, lane_ctx)
	var shifted := _offset_polyline(base, side, k * step, lift, _lane_room[room_key], lane_ctx)
	return PipeRoute.routed(from, from_dir, to, to_dir, shifted, squaring, sa, sb)


## A corner between two level legs, strictly between the stubs: where
## a lane can bend a line. Riser ends are not: they are corners of the
## line's own, for the handles, and the lanes must not lose the middle
## corner over them.
static func _has_level_corner(path: Array[Vector3]) -> bool:
	for i in range(2, path.size() - 2):
		if absf(path[i].y - path[i - 1].y) < 0.001 and absf(path[i + 1].y - path[i].y) < 0.001:
			return true
	return false


## The corners with one more at the middle of the longest level leg
## of `base` (between the stubs), in its place along the route.
static func _with_mid_corner(base: Array[Vector3], corners: Array) -> Array:
	var longest := -1
	var best := 0.0
	for i in range(1, base.size() - 2):
		if absf(base[i + 1].y - base[i].y) < 0.001:
			var length := base[i].distance_to(base[i + 1])
			if length > best:
				best = length
				longest = i
	if longest < 0:
		return corners
	var mid := (base[longest] + base[longest + 1]) / 2.0
	var out: Array = []
	var placed := false
	for c: Vector3 in corners:
		# A corner past the leg's start comes after the middle.
		var at := -1
		for i in base.size():
			if base[i].distance_to(c) < 0.01:
				at = i
				break
		if not placed and at > longest:
			out.append(mid)
			placed = true
		out.append(c)
	if not placed:
		out.append(mid)
	return out


const LANE_TIERS := 4
const LANE_STEPS := 4   # 33 lanes over two sides and four tiers: further out, a riser leaves its column's reach


## The order lanes are tried in: by tier first, then by step out, then
## by side — so a lane is lifted only when every step out on its tier
## is taken.
static func _lane_rank(lane: int) -> int:
	var slot := lane - 1
	@warning_ignore("integer_division")
	var tier := (slot / 2) % LANE_TIERS
	@warning_ignore("integer_division")
	var k := slot / (2 * LANE_TIERS)
	return tier * 100 + k * 10 + slot % 2
var _lane_room: Dictionary = {}
# The one answer to "may a run pass here?": see world/run_clearance.gd.
var clearance: RunClearance


## How far each horizontal leg of `base` can move to `side` before it
## meets something solid, in steps, up to LANE_STEPS of them; INF for
## a vertical leg, which moves with its neighbour.
func _leg_room(base: Array[Vector3], side: int, step: float, lift: float, ctx: Dictionary) -> Array[float]:
	var n := base.size()
	var room: Array[float] = []
	for i in n - 1:
		var d := base[i + 1] - base[i]
		if absf(d.y) > maxf(absf(d.x), absf(d.z)):
			room.append(INF)
			continue
		var dir := Vector3(d.x, 0.0, d.z).normalized()
		var normal := Vector3(-dir.z, 0.0, dir.x) * side
		var clear := 0.0
		for k in range(1, LANE_STEPS + 1):
			var o := k * step
			if not clearance.leg_clear(base[i] + normal * o + Vector3.UP * lift,
					base[i + 1] + normal * o + Vector3.UP * lift, ctx):
				break
			clear = o
		room.append(clear)
	return room


## The interior corners of `base` moved sideways by up to `want`, leg
## by leg: each horizontal leg takes the offset on its side that the
## room beside it allows, so a bundle bends round a rack column or a
## drain together instead of shifting into it.
## A corner between two horizontal legs at right angles takes both
## offsets, which is where the two shifted lines meet. A vertical leg
## takes one shift at both its ends so it stays vertical: both
## flanking offsets when the legs it joins are at right angles, and
## when they are parallel their common offset — or, if that is nil,
## a slide along them, which needs no room beside anything. Where
## legs still disagree, the re-routing that follows turns the misfit
## into a short jog. `lift` raises every corner: the tier.
func _offset_polyline(base: Array[Vector3], side: int, want: float, lift: float,
		room: Array[float], ctx: Dictionary) -> Array:
	var n := base.size()
	var from := base[0]
	var to := base[n - 1]
	var dirs: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var offs: Array[Vector3] = []
	for i in n - 1:
		var d := base[i + 1] - base[i]
		if room[i] == INF:
			dirs.append(Vector3.ZERO)
			normals.append(Vector3.ZERO)
			offs.append(Vector3.ZERO)
			continue
		var dir := Vector3(d.x, 0.0, d.z).normalized()
		var normal := Vector3(-dir.z, 0.0, dir.x) * side
		dirs.append(dir)
		normals.append(normal)
		offs.append(normal * minf(want, room[i]))
	var vertical_shift := {"ctx": ctx}
	var out: Array = []
	# A lane steps sideways off a stub end at a right angle, square to
	# the stub, never moving the stub end itself (a diagonal jog off
	# the nozzle, an acute elbow); the routed path keeps the
	# stub end and adds this corner after it, and a vertical leg off a
	# stub takes the same step so it stays plumb. Lane 0 never comes
	# here, so a lone line is stub, straight, riser, stub.
	var stub_a_shift := Vector3.ZERO
	var stub_b_shift := Vector3.ZERO
	if n >= 4:
		if room[0] != INF:
			stub_a_shift = normals[0] * minf(want, room[0])
		if room[n - 2] != INF:
			stub_b_shift = normals[n - 2] * minf(want, room[n - 2])
	for j in range(1, n - 1):
		if j == 1 or j == n - 2:
			out.append(base[j] + (stub_a_shift if j == 1 else stub_b_shift))
			continue
		var shift := Vector3.ZERO
		if normals[j - 1] != Vector3.ZERO and normals[j] != Vector3.ZERO:
			shift = _corner_shift(offs[j - 1], normals[j - 1], offs[j], normals[j])
		elif normals[j] == Vector3.ZERO:
			shift = _vertical_offset(j, base, dirs, normals, offs, side, want, lift, from, to, vertical_shift)
		else:
			shift = _vertical_offset(j - 1, base, dirs, normals, offs, side, want, lift, from, to, vertical_shift)
		if room[j - 1] == INF and j - 1 == 1:
			shift = stub_a_shift   # the foot of a drop straight off the stub
		elif room[j] == INF and j + 1 == n - 2:
			shift = stub_b_shift   # the head of a rise straight into the stub
		out.append(base[j] + shift + Vector3.UP * lift)
	return out


## Where two offset lines meet: the corner between a leg shifted by
## o1 along its normal n1 and one shifted by o2 along n2, at whatever
## angle the legs meet. At a
## right angle it is the sum of the two shifts; between parallel legs,
## or across a hairpin the lines never meet cleanly, the first leg's.
static func _corner_shift(o1: Vector3, n1: Vector3, o2: Vector3, n2: Vector3) -> Vector3:
	var c := n1.dot(n2)
	var det := 1.0 - c * c
	if det < 0.05:
		return o1
	var w1 := o1.dot(n1)
	var w2 := o2.dot(n2)
	return (n1 * (w1 - c * w2) + n2 * (w2 - c * w1)) / det


func _vertical_offset(v: int, base: Array[Vector3], dirs: Array[Vector3], normals: Array[Vector3],
		offs: Array[Vector3], side: int, want: float, lift: float, from: Vector3, to: Vector3,
		cache: Dictionary) -> Vector3:
	if cache.has(v):
		return cache[v]
	var h1 := -1
	for i in range(v - 1, -1, -1):
		if normals[i] != Vector3.ZERO:
			h1 = i
			break
	var h2 := -1
	for i in range(v + 1, normals.size()):
		if normals[i] != Vector3.ZERO:
			h2 = i
			break
	var shift := Vector3.ZERO
	if h1 >= 0 and h2 >= 0:
		# The longer of the two legs it joins keeps its line: a bundle's
		# shared leg is the long one, and the short leg from a fitting
		# or off a tray corner takes the difference in its bearing.
		var long_leg := h1 if (base[h1 + 1] - base[h1]).length() >= (base[h2 + 1] - base[h2]).length() else h2
		if absf(dirs[h1].dot(dirs[h2])) < 0.95:
			shift = _corner_shift(offs[h1], normals[h1], offs[h2], normals[h2])
		else:
			# Parallel legs share a line; legs doubling back (a drop that
			# comes back under the tray it left) have opposite normals for
			# one side, and the riser cannot stand on both lines.
			shift = offs[long_leg]
		# A tier lifts a horizontal leg clear of its neighbour but does
		# nothing for a vertical, so a riser slides along the leg by its
		# tier instead — and by the whole lane offset when there was no
		# room beside those legs at all. Sliding along the leg needs no
		# room beside anything. A quarter metre at most: further and a
		# riser leaves the reach of whatever carried it.
		var along := minf(lift + (want if shift.length() < 0.001 else 0.0), 0.3)
		if along > 0.001:
			var slide := dirs[long_leg] * (side * along)
			for attempt in 3:
				if clearance.leg_clear(base[v] + shift + slide + Vector3.UP * lift,
						base[v + 1] + shift + slide + Vector3.UP * lift, cache["ctx"]):
					shift += slide
					break
				slide *= 0.5
	elif h1 >= 0:
		shift = offs[h1]
	elif h2 >= 0:
		shift = offs[h2]
	cache[v] = shift
	return shift


## The path a run was laid on. Reports and the support check read
## what is rendered; a lane recomputed against what physics knows now
## can differ from what was laid, and that difference is the deferred
## pass's business, not the report's.
func _visual_path(visual: Dictionary) -> Array[Vector3]:
	var stored: Array = visual.get("path", [])
	if not stored.is_empty():
		var out: Array[Vector3] = []
		for p: Vector3 in stored:
			out.append(p)
		return out
	var view := visual["node"] as PipeView
	return _route_points(str(visual["a"]), str(visual["a_port"]), str(visual["b"]), str(visual["b_port"]),
		visual.get("corners", visual["waypoints"]), int(visual.get("lane", 0)),
		view.radius() if view != null else 0.025)


## The corners of a run's own route, laid round whatever is solid:
## the search runs between the waypoints the
## player gave, and the result is what the lanes then shift. Physics
## only knows a body the frame after it is added, so a run laid in the
## same frame as its equipment is re-laid by the deferred pass.
func _avoided_corners(src_name: String, src_port: String, dst_name: String, dst_port: String,
		waypoints: Array, order: int = ORDER_ALL, radius: float = -1.0) -> Array:
	var from := _marker_pos(src_name, src_port)
	var to := _marker_pos(dst_name, dst_port)
	var from_dir := _marker_dir(src_name, src_port)
	var to_dir := _marker_dir(dst_name, dst_port)
	if radius <= 0.0:
		radius = _radius_of(src_name, src_port)
	var sa := _stub_of(src_name, src_port, radius)
	var sb := _stub_of(dst_name, dst_port, radius)
	var full := PipeRoute.routed_avoiding(from, from_dir, to, to_dir, waypoints,
		clearance.router_blocked.bind(clearance.context([src_name, dst_name], from, to, radius)),
		clearance.busy.bind([src_name], order), sa, sb)
	# The corners are the route without its fittings and stubs, stripped
	# by position: the router's straightening drops a stub end that lies
	# on the last straight, so slicing by index would lose a line's only
	# corner.
	var fixed: Array[Vector3] = [from, from + from_dir * sa, to + to_dir * sb, to]
	var corners: Array = []
	for p: Vector3 in full:
		var at_end := false
		for e in fixed:
			if p.distance_to(e) < 0.001:
				at_end = true
				break
		if not at_end:
			corners.append(p)
	if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
		if PipeRoute.last_searched:
			var b := PipeRoute.last_block
			print("[route] %s.%s -> %s.%s detours at %s (%s): %s" % [src_name, src_port, dst_name, dst_port,
				b, clearance.last_block, corners])
		else:
			print("[route] %s.%s -> %s.%s plain through %s: %s" % [src_name, src_port, dst_name, dst_port,
				str(waypoints), corners])
	return corners


## Two runs with an end on the same equipment — a pump's suction and
## its power, or two circuits into one cabinet — may approach it side
## by side for a metre and a half, beside it: their fittings are a
## hand apart on one machine. Anywhere else, half a metre is the most
## two runs may share. Cabinet modules (`<cab>_m3`, `<cab>_m5_t6`)
## count as their cabinet.
func _allowed_overlap(a1: String, b1: String, a2: String, b2: String, at: Vector3) -> float:
	# Two runs from one source (a feeder's ways down one trunk) fan out
	# from the corner where they part, each on the direct line to its
	# own load: for a metre or so past that corner they
	# lie within a hand of each other, as they would in a real fan.
	if a1 == a2:
		return 1.5
	var g2 := [_approach_group(a2), _approach_group(b2)]
	for end_name: String in [a1, b1]:
		if _approach_group(end_name) in g2 and _near_record(at, end_name, 2.5):
			return 1.5
	return 0.5


func _near_record(at: Vector3, name_: String, within: float) -> bool:
	var group := _approach_group(name_)
	for record_name: String in views:
		if _approach_group(record_name) == group \
				and (views[record_name] as Node3D).position.distance_to(at) <= within:
			return true
	return false


static var _module_re: RegEx = null


static func _approach_group(name_: String) -> String:
	if name_ == "":
		return "<none>"
	# Compiled once: it is asked for every run a lane is checked
	# against, thousands of times a lay.
	if _module_re == null:
		_module_re = RegEx.create_from_string("^(.*)_m\\d+(_t\\d+)?$")
	var hit := _module_re.search(name_)
	return hit.get_string(1) if hit != null else name_


## The longest stretch this route would share with a run already laid,
## or 0. Trays do not count: a conduit belongs in one. Runs leaving
## the same fitting are allowed the stub and a jog, a metre — the
## fan-out at a nozzle or a gland plate is physics, not a mistake — and
## no more.
func _path_collision(path: Array[Vector3], radius: float, a: String, a_port: String,
		b: String, b_port: String, order: int = ORDER_ALL) -> float:
	var worst := 0.0
	for visual in _wire_visuals:
		var other := visual["node"] as PipeView
		if other == null or other.style() == "tray":
			continue
		if int(visual.get("order", -1)) >= order:
			continue  # laid later: it yields to this run, not the other way round
		var other_path: Array = visual.get("path", [])
		if other_path.size() < 2:
			continue
		if not visual.has("box"):
			visual["box"] = _path_box(other_path)
		var got := _paths_overlap(path, other_path, radius + other.radius(), visual["box"])
		if got > 0.0 and got >= _allowed_overlap(a, b, str(visual["a"]), str(visual["b"]), _last_overlap_at):
			worst = maxf(worst, got)
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		var other := entry["node"] as PipeView
		if other.style() == "tray":
			continue
		if not entry.has("laid"):
			entry["laid"] = PipeRoute.lay(entry["points"])   # a placed run's points never change
			entry["box"] = _path_box(entry["laid"])
		var got := _paths_overlap(path, entry["laid"], radius + other.radius(), entry["box"])
		if got >= 0.5:
			worst = maxf(worst, got)
	return worst


## The longest stretch two paths share within gap of each other.
## Paths whose boxes do not meet are rejected before any segment pair
## is looked at: with a hundred runs and fifty lanes, that is the cost.
static func _paths_overlap(pa: Array, pb: Array, gap: float, pb_box: AABB = AABB()) -> float:
	if pa.size() < 2 or pb.size() < 2:
		return 0.0
	var box_a := _path_box(pa).grow(gap)
	# The other path's box is kept with it: with a hundred and fifty
	# runs and thirty-three lanes a lay, computing it here would be most
	# of the lane loop.
	if not box_a.intersects(_path_box(pb) if pb_box.size == Vector3.ZERO else pb_box):
		return 0.0
	var worst := 0.0
	var where := Vector3.ZERO
	for s in range(pa.size() - 1):
		var a0: Vector3 = pa[s]
		var a1: Vector3 = pa[s + 1]
		var seg_box := AABB(a0, Vector3.ZERO).expand(a1).grow(gap)
		for t in range(pb.size() - 1):
			var b0: Vector3 = pb[t]
			var b1: Vector3 = pb[t + 1]
			if not seg_box.intersects(AABB(b0, Vector3.ZERO).expand(b1)):
				continue
			var got := _segment_overlap(a0, a1, b0, b1, gap)
			if float(got[0]) > worst:
				worst = float(got[0])
				where = got[1]
	_last_overlap_at = where
	return worst


static var _last_overlap_at := Vector3.ZERO


static func _path_box(path: Array) -> AABB:
	var box := AABB(path[0], Vector3.ZERO)
	for i in range(1, path.size()):
		box = box.expand(path[i])
	return box


## The straight a line keeps at this fitting: five of its own bores,
## or five of the fitting's where the fitting is the bigger (a DN6
## tube meets a DN50 nozzle through a reducer that needs the room).
func _stub_of(record_name: String, port_name: String, radius: float) -> float:
	var record := sim.get_component(record_name)
	if record == null or not record.material_ports().has(port_name):
		return PipeRoute.STUB   # a cable keeps its gland stub
	return PipeRoute.stub_for(maxf(radius, _end_bore(record_name, port_name)))


func _radius_of(record_name: String, port_name: String) -> float:
	var record := sim.get_component(record_name)
	if record == null:
		return LINE_RADIUS_DN50
	if record.outputs.has(port_name):
		return run_radius(record.outputs[port_name] as SimPort)
	if record.inputs.has(port_name):
		return run_radius(record.inputs[port_name] as SimPort)
	return LINE_RADIUS_DN50


func _marker_pos(record_name: String, port_name: String) -> Vector3:
	var view: Node3D = views.get(record_name)
	if view == null:
		return Vector3.ZERO
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Node3D = markers.get("%s:%s" % [record_name, port_name])
	return to_local(marker_face(marker)) if marker != null else view.position


## Where a line meets a fitting: its outer face, `face` along its
## axis from its origin, never the root of the neck. World space.
static func marker_face(marker: Node3D) -> Vector3:
	return marker.global_position + marker.global_basis.x.normalized() * float(marker.get_meta("face", 0.0))


## The fitting's outward axis (plant-local): runs must leave along it.
func _marker_dir(record_name: String, port_name: String) -> Vector3:
	var view: Node3D = views.get(record_name)
	if view == null:
		return Vector3.ZERO
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Node3D = markers.get("%s:%s" % [record_name, port_name])
	return marker.global_basis.x.normalized() if marker != null else Vector3.ZERO


## ---- the commissioned starting loop -------------------------------------

func _build_initial_plant() -> void:
	tank = place("tank", "supply_tank",
		{"capacity_l": 100.0, "level_l": 70.0},
		_world(Vector3(2.5, 0, -2.0)), 0.0, true) as SimTank
	# The level switch is on the tank's shell, not beside it.
	switch = mount_instrument("float_switch", "level_switch", {"low_l": 40.0, "high_l": 80.0},
		"supply_tank", 0.6, 0.9, true) as SimFloatSwitch
	relay = place("relay", "pump_relay", {},
		_world(Vector3(-2.5, 1.5, -4.74)) - Vector3(0, PlantFactory.Y_OFFSETS["relay"], 0),
		0.0, true) as SimRelay
	pump = place("pump", "fill_pump", {"rated_lps": 4.0},
		_world(Vector3(-0.5, 0, -2.6)), 0.0, true) as SimPump
	# Twenty-four ways: the showcase hangs every unit's loads on it.
	place("mains", "plant_mains", {"ways": 24}, _world(Vector3(-4.4, 0, -1.2)), 0.0, true)
	place("source", "raw_water", {}, _world(Vector3(-6.4, 0, -2.9)), 0.0, true)
	place("drain", "du_100", {"rate_lps": 1.5}, _world(Vector3(4.7, 0, -1.4)), 0.0, true)
	# Power first — nothing runs without a cable back to the feeder.
	# No waypoints on any of these: what the router lays here is what a
	# player gets.
	connect_equipment("plant_mains", free_way("plant_mains"), "fill_pump", "power")
	# The flow path is honest end to end: the pump pulls from the
	# supply header, and the tank's consumption is a real drain. One
	# pipe per connection.
	connect_equipment("raw_water", "outlet", "fill_pump", "inlet")
	connect_equipment("supply_tank", "outlet", "du_100", "inlet")
	connect_equipment("level_switch", "contact", "pump_relay", "coil")
	connect_equipment("pump_relay", "contact", "fill_pump", "run")
	connect_equipment("fill_pump", "outlet", "supply_tank", "inlet")
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
	if build_home:
		hmi_view = HmiView.new()
		hmi_view.position = Vector3(-4.6, 1.6, -4.75)
		add_child(hmi_view)
		hmi_view.setup(historian, tank, switch, relay, pump)
	# The material balance by unit, beside it: the standing proof that
	# what the headers fed is still somewhere, from the records' meters.
	# A blank map gets it too: it is the one display that needs nothing
	# placed to be right.
	var balance_screen := HmiScreenView.new()
	balance_screen.name = "hmi_balance"
	balance_screen.position = Vector3(-6.9, 1.6, -4.75)
	add_child(balance_screen)
	balance_panel = PlantBalancePanel.new()
	balance_panel.setup(self)
	balance_screen.setup(balance_panel, "MATERIAL BALANCE", Vector2i(1024, 640), 1.2,
		"Material balance by unit: fed, out, held against held at build, and the residual, all from the records' own meters; the plant residual trended from the historian.")


func _self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var c_tank := check.add(SimTank.new("t", 100.0, 70.0)) as SimTank
	var c_switch := check.add(SimFloatSwitch.new("s", 40.0, 80.0)) as SimFloatSwitch
	var c_relay := check.add(SimRelay.new("r")) as SimRelay
	var c_pump := check.add(SimPump.new("p", 4.0)) as SimPump
	var c_mains := check.add(SimMainsFeed.new("m")) as SimMainsFeed
	var c_src := check.add(SimSource.new("bl")) as SimSource
	var c_drn := check.add(SimDrain.new("d", 1.5)) as SimDrain
	check.connect_ports(c_mains, "way1", c_pump, "power")
	check.connect_ports(c_src, "outlet", c_pump, "inlet")
	check.connect_ports(c_pump, "outlet", c_tank, "inlet")
	check.connect_ports(c_tank, "outlet", c_drn, "inlet")
	check.connect_ports(c_tank, "level", c_switch, "level")
	check.connect_ports(c_switch, "contact", c_relay, "coil")
	check.connect_ports(c_relay, "contact", c_pump, "run")
	check.run_for(600.0)
	# Mass closes across the loop: what the header delivered is either
	# still in the tank or went down the drain.
	var closure := absf(c_src.total_l - ((c_tank.level_l - 70.0) + c_drn.total_l))
	var ok := c_tank.level_l >= 38.0 and c_tank.level_l <= 82.0 \
		and c_tank.overflowed_l == 0.0 and c_relay.cycles >= 1 and c_relay.cycles < 15 \
		and closure < 0.5
	if ok:
		print("[flowstate] kernel self-check OK — 600 s: level %.1f L, %d relay cycles, balance within %.3f L"
			% [c_tank.level_l, c_relay.cycles, closure])
	else:
		push_warning("[flowstate] kernel self-check FAILED — level %.1f L, overflow %.1f L, %d cycles, balance off by %.2f L"
			% [c_tank.level_l, c_tank.overflowed_l, c_relay.cycles, closure])
	_hydraulics_self_check()
	_control_self_check()
	_stream_self_check()


## Mirrors the Python hydraulics tests: the behaviours that separate a
## solved network from asserted flow. If a pump does not dead-head, if
## two in parallel double the flow, if a tee does not split by
## resistance, or if a tank does not drain downhill on its own, then
## pressure is decorative and we are back to bookkeeping.
func _hydraulics_self_check() -> void:
	var problems: Array[String] = []

	# A tee is a node: the split falls out of the resistances, and the
	# flow in equals the flows out. Warm-started, the next solve is
	# nearly free.
	var net := SimNetwork.new()
	var supply := net.add_node(200000.0, true)
	var tee := net.add_node()
	var easy_end := net.add_node(0.0, true)
	var hard_end := net.add_node(0.0, true)
	var feed := net.add_branch(SimResistance.new(supply, tee, 500.0))
	var easy := net.add_branch(SimResistance.new(tee, easy_end, 1000.0))
	var hard := net.add_branch(SimResistance.new(tee, hard_end, 9000.0))
	net.solve()
	if absf(feed.flow_lps - (easy.flow_lps + hard.flow_lps)) > SimNetwork.TOLERANCE_LPS:
		problems.append("tee does not conserve")
	if absf(easy.flow_lps - 3.0 * hard.flow_lps) > 0.02 * easy.flow_lps:
		problems.append("tee split is not by resistance")
	net.solve()
	if net.iterations > 3:
		problems.append("warm start took %d iterations" % net.iterations)

	# A pump makes its rating against a free discharge, dead-heads
	# against too much head, and two in parallel do not double the flow.
	if _pump_rig(300000.0, 4.0, 0.0) < 3.99:
		problems.append("free discharge did not give the rated flow")
	if _pump_rig(300000.0, 4.0, 320000.0) != 0.0:
		problems.append("pump did not dead-head")
	var one := _parallel_pumps(1)
	var two := _parallel_pumps(2)
	if not (two > one and two < 2.0 * one):
		problems.append("parallel pumps: one %.2f, two %.2f" % [one, two])

	# Two vessels and a pipe: the raised one empties into the low one
	# with no pump anywhere, and nothing is lost on the way.
	var sim := Simulation.new(SIM_DT)
	var full := sim.add(SimTank.new("full", 2000.0, 1800.0, 0.0, 3.0, 0.0, 0.0, 5.0)) as SimTank
	var low := sim.add(SimTank.new("low", 2000.0, 0.0, 0.0, 3.0)) as SimTank
	sim.connect_ports(full, "outlet", low, "inlet")
	sim.run_for(200.0)
	if low.level_l < 50.0 or full.level_l >= 1800.0:
		problems.append("raised tank did not drain into the low one")
	if absf(full.level_l + low.level_l - 1800.0) > 0.5:
		problems.append("gravity transfer lost material")

	# Both at grade, the receiving nozzle above the source's level:
	# nothing moves, and nothing should.
	sim = Simulation.new(SIM_DT)
	var src_t := sim.add(SimTank.new("a", 500.0, 400.0, 0.0, 2.0)) as SimTank
	var dst_t := sim.add(SimTank.new("b", 500.0, 0.0, 0.0, 2.0)) as SimTank
	sim.connect_ports(src_t, "outlet", dst_t, "inlet")
	sim.run_for(200.0)
	if dst_t.level_l > 0.1 or absf(src_t.level_l - 400.0) > 0.1:
		problems.append("gravity ran uphill")

	# A nozzle stands where it was welded: an
	# outlet 0.3 m up the shell drains the vessel to a 0.3 m heel and
	# no further, and a nozzle above the liquid passes nothing out.
	sim = Simulation.new(SIM_DT)
	var heel_t := sim.add(SimTank.new("heel", 100.0, 100.0, 0.0, 1.0, 0.36, 0.0, 0.0, 5.0)) as SimTank
	var heel_d := sim.add(SimDrain.new("heel_d", 50.0)) as SimDrain
	heel_t.set_nozzle_height("outlet", 0.3)
	sim.connect_ports(heel_t, "outlet", heel_d, "inlet")
	sim.run_for(240.0)
	if absf(heel_t.depth_m - 0.3) > 0.035:
		problems.append("welded-up outlet left a %.2f m heel, expected 0.3" % heel_t.depth_m)
	heel_t.set_nozzle_height("outlet", SimTank.AT_ROOF)
	var held := heel_t.level_l
	sim.run_for(30.0)
	if absf(heel_t.level_l - held) > 0.05:
		problems.append("a nozzle above the liquid passed %.2f L out" % (held - heel_t.level_l))

	# Header -> pump -> tank -> drain: the header meters what was
	# pulled, the drain runs faster under more head, and mass closes.
	sim = Simulation.new(SIM_DT)
	var header := sim.add(SimSource.new("hdr")) as SimSource
	var pump := sim.add(SimPump.new("p", 3.0, "hand")) as SimPump
	var tank_ := sim.add(SimTank.new("t", 4000.0, 0.0, 0.0, 3.0)) as SimTank
	var drain := sim.add(SimDrain.new("d", 2.0)) as SimDrain
	var mains := sim.add(SimMainsFeed.new("m")) as SimMainsFeed
	sim.connect_ports(mains, "way1", pump, "power")
	sim.connect_ports(header, "outlet", pump, "inlet")
	sim.connect_ports(pump, "outlet", tank_, "inlet")
	sim.connect_ports(tank_, "outlet", drain, "inlet")
	sim.run_for(20.0)
	var shallow := drain.flow_lps
	sim.run_for(400.0)
	var deep := drain.flow_lps
	if not (tank_.depth_m > 0.5 and deep > shallow * 1.5):
		problems.append("drain did not run faster under more head (%.2f -> %.2f)" % [shallow, deep])
	if header.total_l < 100.0 or absf(header.total_l - (tank_.level_l + drain.total_l)) > 0.5:
		problems.append("header -> tank -> drain does not close (%.1f fed, %.1f accounted)"
			% [header.total_l, tank_.level_l + drain.total_l])
	if sim.network().residual_lps > SimNetwork.TOLERANCE_LPS:
		problems.append("plant solve left a residual of %.5f L/s" % sim.network().residual_lps)

	# A pump cannot fill a tank taller than its head: the motor turns
	# and nothing moves.
	sim = Simulation.new(SIM_DT)
	var low_hdr := sim.add(SimSource.new("hdr", "water", 20.0, 0.0)) as SimSource
	var weak := sim.add(SimPump.new("p", 3.0, "hand", 4.0)) as SimPump
	var tower := sim.add(SimTank.new("tower", 8000.0, 0.0, 0.0, 20.0)) as SimTank
	var mains2 := sim.add(SimMainsFeed.new("m")) as SimMainsFeed
	sim.connect_ports(mains2, "way1", weak, "power")
	sim.connect_ports(low_hdr, "outlet", weak, "inlet")
	sim.connect_ports(weak, "outlet", tower, "inlet")
	sim.run_for(60.0)
	if not (weak.running and weak.flow_lps < 0.01):
		problems.append("pump lifted past its head (%.2f L/s)" % weak.flow_lps)

	# A pump knows its height: drawing from an
	# atmospheric header, one 9 m up sees a static suction of -88 kPa,
	# inside the prime band, and one 12 m up is past a hard vacuum and
	# moves nothing; at grade the same pump makes its rating.
	var at_grade := _pump_rig(300000.0, 4.0, 0.0, 0.0)
	var raised := _pump_rig(300000.0, 4.0, 0.0, 9.0)
	var too_high := _pump_rig(300000.0, 4.0, 0.0, 12.0)
	if not (at_grade > 3.99 and raised > 0.5 and raised < 0.8 * at_grade and too_high == 0.0):
		problems.append("pump elevation: grade %.2f, 9 m %.2f, 12 m %.2f" % [at_grade, raised, too_high])

	# An open end vents at the height it stands at now, not the height
	# it was built at: raised after the network was laid out, it spills
	# less (the cap's air node is refreshed every scan, like a header's).
	sim = Simulation.new(SIM_DT)
	var spill_hdr := sim.add(SimSource.new("hdr", "water", 20.0, 50.0)) as SimSource
	var end := sim.add(SimCap.new("end")) as SimCap
	end.open = true
	sim.connect_ports(spill_hdr, "outlet", end, "a")
	sim.run_for(2.0)
	var spill_low := end.spill_lps()
	end.elevation_m = 4.0
	sim.run_for(2.0)
	if not (end.spill_lps() > 0.0 and end.spill_lps() < spill_low):
		problems.append("open end ignores a raised height (%.3f then %.3f L/s)" % [spill_low, end.spill_lps()])

	# The valve equation: half open is more than half the flow, because
	# flow follows the square root of the drop, not the position.
	var wide := _valve_flow(100.0)
	var half := _valve_flow(50.0)
	if not (wide > 0.5 and half > wide * 0.5 and half < wide):
		problems.append("valve: wide open %.2f, half %.2f" % [wide, half])

	# Composition follows flow: two headers into one vessel blend.
	sim = Simulation.new(SIM_DT)
	var hot := sim.add(SimSource.new("hot", "solvent", 80.0, 300.0)) as SimSource
	var cold := sim.add(SimSource.new("cold", "water", 20.0, 300.0)) as SimSource
	var blend := sim.add(SimTank.new("t", 8000.0, 0.0, 0.0, 4.0)) as SimTank
	sim.connect_ports(hot, "outlet", blend, "inlet")
	sim.connect_ports(cold, "outlet", blend, "inlet")
	sim.run_for(120.0)
	var x_solv := blend.contents.frac(SimSpecies.SOLVENT)
	if not (x_solv > 0.2 and x_solv < 0.8 and blend.temp_c > 20.0 and blend.temp_c < 80.0):
		problems.append("two headers did not blend (%.2f solvent, %.1f C)" % [x_solv, blend.temp_c])

	if problems.is_empty():
		print("[flowstate] hydraulics self-check OK — tees split, pumps dead-head, gravity drains, valves follow the square root, mass closes")
	else:
		push_warning("[flowstate] hydraulics self-check FAILED — %s" % "; ".join(problems))


func _pump_rig(head_pa: float, max_lps: float, lift_pa: float, elevation_m: float = 0.0) -> float:
	var net := SimNetwork.new()
	var suction := net.add_node(0.0, true)
	var discharge := net.add_node(lift_pa, true)
	var pump := net.add_branch(SimPumpCurve.new(suction, discharge, head_pa, max_lps)) as SimPumpCurve
	pump.running = true
	pump.datum_pa = SimHydraulics.static_head_pa(elevation_m)
	net.solve()
	return pump.flow_lps


## Both pumps ride up their curves against the extra line loss, so the
## second one buys far less than the first.
func _parallel_pumps(count: int) -> float:
	var net := SimNetwork.new()
	var suction := net.add_node(0.0, true)
	var header := net.add_node()
	var outlet := net.add_node(0.0, true)
	for _i in count:
		var pump := net.add_branch(SimPumpCurve.new(suction, header, 300000.0, 4.0)) as SimPumpCurve
		pump.running = true
	var line := net.add_branch(SimResistance.new(header, outlet, 20000.0))
	net.solve()
	return line.flow_lps


## Header -> control valve -> tank, with the command wired from a hand
## controller in manual, because an input port resets every scan.
func _valve_flow(command: float) -> float:
	var sim := Simulation.new(SIM_DT)
	var header := sim.add(SimSource.new("hdr", "water", 20.0, 300.0)) as SimSource
	var valve := sim.add(SimControlValve.new("v", 6.0, 0.2)) as SimControlValve
	var tank_ := sim.add(SimTank.new("t", 9000.0, 0.0, 0.0, 4.0)) as SimTank
	var hand := sim.add(SimPID.new("hic", 0.0, 0.0, 0.0, 0.0, 0.0, 100.0)) as SimPID
	hand.set_mode("manual")
	hand.manual_out = command
	sim.connect_ports(hand, "out", valve, "cmd")
	sim.connect_ports(header, "outlet", valve, "inlet")
	sim.connect_ports(valve, "outlet", tank_, "inlet")
	sim.run_for(20.0)
	return valve.flow_lps


## Mirrors the Python stream tests: material has to be conserved when
## streams merge, a vessel has to blend what arrives into what it holds,
## and — the part save/load can quietly break — composition and
## temperature have to survive a state round-trip. A tank that forgets
## what is in it after a reload is the worst kind of bug, because
## everything still runs and only the numbers are wrong.
func _stream_self_check() -> void:
	var problems: Array[String] = []

	# Mixing conserves each species, and blends temperature by flow.
	var hot := SimStream.pure(SimSpecies.SOLVENT, 2.0, 80.0)
	var cold := SimStream.pure(SimSpecies.WATER, 6.0, 20.0)
	var mixed := SimStream.mix(hot, cold)
	if absf(mixed.flow_lps - 8.0) > 1e-4:
		problems.append("mixing lost flow")
	if absf(mixed.temp_c - 35.0) > 1e-3:
		problems.append("mixing got the temperature wrong")
	if absf(mixed.species_lps(SimSpecies.SOLVENT) - 2.0) > 1e-4 \
			or absf(mixed.species_lps(SimSpecies.WATER) - 6.0) > 1e-4:
		problems.append("mixing lost a species")

	# A vessel blends what arrives into what it holds.
	var check := Simulation.new(SIM_DT)
	var vessel := check.add(SimTank.new("v", 4000.0)) as SimTank
	var charge := SimStream.zero_amounts()
	charge[SimSpecies.WATER] = 1.0
	vessel.charge(1000.0, charge, 20.0)
	for _i in 200:  # 10 s of hot solvent at 10 L/s, stood at the nozzle
		# the way the hydraulic pass leaves it: the node stream plus a
		# signed rate into the vessel.
		vessel.inlet.stream = SimStream.pure(SimSpecies.SOLVENT, 10.0, 80.0)
		vessel.inlet.flow_lps = 10.0
		vessel.tick(SIM_DT)
	if absf(vessel.level_l - 1100.0) > 1.0:
		problems.append("vessel inventory drifted while filling")
	if absf(vessel.contents.frac(SimSpecies.SOLVENT) - 100.0 / 1100.0) > 0.01:
		problems.append("vessel did not blend the incoming composition")
	if vessel.temp_c <= 20.5 or vessel.temp_c >= 80.0:
		problems.append("hot feed did not warm the vessel")

	# Composition survives a save/load round-trip.
	var before := vessel.contents
	var restored := SimTank.new("v2", 4000.0)
	restored.apply_state(vessel.state_dict())
	if absf(restored.level_l - vessel.level_l) > 1e-4:
		problems.append("level lost in round-trip")
	if absf(restored.temp_c - before.temp_c) > 1e-3:
		problems.append("temperature lost in round-trip")
	for i in SimSpecies.COUNT:
		if absf(restored.contents.frac(i) - before.frac(i)) > 1e-3:
			problems.append("composition lost in round-trip")
			break

	if problems.is_empty():
		print("[flowstate] stream self-check OK — mixing conserves, vessels blend, composition survives save/load")
	else:
		push_warning("[flowstate] stream self-check FAILED — %s" % ", ".join(problems))


## Mirrors the Python control tests: a PID level loop must settle on
## setpoint, and a ladder seal-in must latch and drop.
func _control_self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var tank_ := check.add(SimTank.new("t", 200.0, 50.0, 2.0)) as SimTank
	var lt := check.add(SimGauge.new("lt", "level_kpa")) as SimGauge
	var lic := check.add(SimPID.new("lic", 8.0, 1.5, 0.0, 15.0)) as SimPID
	var lv := check.add(SimControlValve.new("lv", 6.0)) as SimControlValve
	var header := check.add(SimSource.new("uh")) as SimSource
	check.connect_ports(header, "outlet", lv, "inlet")
	check.connect_ports(tank_, "level", lt, "process")
	check.connect_ports(lt, "signal", lic, "pv")
	check.connect_ports(lic, "out", lv, "cmd")
	check.connect_ports(lv, "outlet", tank_, "inlet")
	check.run_for(600.0)
	var level_kpa := tank_.level_l / 45.45 * SimGauge.WATER_KPA_PER_M

	var plc := SimPLC.new("plc")
	plc.power.value = 1.0  # direct-tick check: energize the rack
	var err := plc.set_program([
		{"coil": "m_0", "logic": [
			[{"ref": "di_0"}, {"ref": "di_1", "nc": true}],
			[{"ref": "m_0"}, {"ref": "di_1", "nc": true}]]},
		{"coil": "do_0", "logic": [[{"ref": "m_0"}]]},
	])
	plc.di_ports[0].value = 1.0
	plc.tick(SIM_DT)
	plc.di_ports[0].value = 0.0
	plc.tick(SIM_DT)
	var sealed := plc.do_ports[0].value > 0.5
	plc.di_ports[1].value = 1.0
	plc.tick(SIM_DT)
	var dropped := plc.do_ports[0].value < 0.5

	if absf(level_kpa - 15.0) < 0.3 and absf(lv.flow_lps - 2.0) < 0.15 \
			and err == "" and sealed and dropped:
		print("[flowstate] control self-check OK — PID holds %.1f kPa, ladder seals and drops"
			% level_kpa)
	else:
		push_warning("[flowstate] control self-check FAILED — level %.2f kPa, flow %.2f, err '%s', sealed %s, dropped %s"
			% [level_kpa, lv.flow_lps, err, sealed, dropped])


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
		# An 8 m span 2 m over the pad stands on pipe stands; the same
		# span 8 m up is beyond a stand (6 m) and fails.
		var open_check := SupportCheck.evaluate(run, space)
		if not bool(open_check["ok"]) or int(open_check["stands"]) < 2:
			push_warning("[flowstate] support exercise FAILED: 8 m span 2 m up was not stood on stands (ok %s, %d stands)"
				% [str(open_check["ok"]), int(open_check["stands"])])
			_support_exercise_phase = 0
			return
		var high: Array[Vector3] = [origin + Vector3(-4, 8, 0), origin + Vector3(4, 8, 0)]
		var high_check := SupportCheck.evaluate(high, space)
		if bool(high_check["ok"]):
			push_warning("[flowstate] support exercise FAILED: 8 m air span 8 m up passed (max span %.2f)"
				% float(high_check["max_span"]))
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
	elif int(braced_check["stands"]) > 0:
		problems.append("braced span still stood on %d stands" % int(braced_check["stands"]))
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space) != "":
		problems.append("beam across two columns was refused")
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space, 5.8) != "":
		problems.append("stretched 5.8 m beam across columns was refused")
	# The interactive flow seats beams center-to-center: length equals
	# the column spacing exactly. Must bear: a 0.2 m end inset would
	# miss the 0.35 m column with a hairline ray.
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
	if not bool(over_tray["ok"]) or int(over_tray["stands"]) > 0:
		problems.append("conduit over the tray was not supported by it (%d stands)" % int(over_tray["stands"]))
	var without_tray := SupportCheck.evaluate(conduit, space, tray_view.collider_rids())
	if not bool(without_tray["ok"]) or int(without_tray["stands"]) == 0:
		problems.append("conduit without the tray was not stood on stands")
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

## The whole plant as a dictionary: what a save writes and what undo
## keeps.
func snapshot() -> Dictionary:
	var comps: Array[Dictionary] = []
	for name_: String in views:
		if member_of.has(name_):
			continue  # cabinet members are saved with their cabinet
		var record := sim.get_component(name_)
		var view: Node3D = views[name_]
		var comp_entry := {
			"type": equip_types[name_],
			"name": name_,
			"state": record.state_dict(),
			"params": _params_for(record),
			"pos": [view.global_position.x, view.global_position.y
				- PlantFactory.Y_OFFSETS.get(equip_types[name_], 0.0), view.global_position.z],
			"rot_y": view.rotation.y,
			"protected": protected.has(name_),
		}
		if view is TankView:
			comp_entry["nozzles"] = (view as TankView).get_nozzles()
		if mounted.has(name_):
			comp_entry["mount"] = (mounted[name_] as Dictionary).duplicate()
		comps.append(comp_entry)
	var wire_list: Array = []
	for visual in _wire_visuals:
		var path_out: Array = []
		for point: Vector3 in visual["waypoints"]:
			path_out.append([point.x, point.y, point.z])
		var locks_out: Array = []
		for point: Vector3 in visual.get("locks", []):
			locks_out.append([point.x, point.y, point.z])
		var wire_entry := {
			"src": visual["a"], "src_port": visual["a_port"],
			"dst": visual["b"], "dst_port": visual["b_port"],
			"waypoints": path_out, "locks": locks_out, "fixed": bool(visual.get("fixed", false)),
			"color": visual.get("color", ""), "label": visual.get("label", ""),
			"fitting": visual.get("fitting", ""),
			"hidden": visual.get("hidden", false),
		}
		var wire := sim.find_wire(sim.get_component(str(visual["a"])), str(visual["a_port"]),
			sim.get_component(str(visual["b"])), str(visual["b_port"]))
		if int(visual.get("dn", 50)) != 50:
			wire_entry["dn"] = int(visual["dn"])
		wire_list.append(wire_entry)
	var struct_list: Array = []
	for name_: String in structures:
		var entry: Dictionary = structures[name_]
		var node := entry["node"] as Node3D
		var size: Vector3 = StructureFactory.SIZES[entry["type"]]
		var base := node.global_position - Vector3(0, size.y / 2.0, 0)
		struct_list.append({
			"type": entry["type"], "name": name_,
			"pos": [base.x, base.y, base.z], "rot_y": node.rotation.y,
			"length": entry.get("length", -1.0), "text": entry.get("text", ""),
		})
	var run_list: Array = []
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		var pts: Array = []
		for point: Vector3 in entry["points"]:
			pts.append([point.x, point.y, point.z])
		run_list.append({"kind": entry["kind"], "name": name_, "points": pts,
			"color": entry.get("color", ""), "label": entry.get("label", ""),
			"fitting": entry.get("fitting", ""), "circuits": entry.get("circuits", [])})
	var cab_list: Array = []
	for name_: String in cabinets:
		var entry: Dictionary = cabinets[name_]
		var node := entry["node"] as Node3D
		var module_list: Array = []
		var states := {}
		for module_v: Variant in entry["modules"]:
			var module := module_v as Dictionary
			module_list.append({"id": module["id"], "type": module["type"],
				"rail": module["rail"], "slot": module["slot"], "bank": module["bank"]})
			for record_name: String in module["records"]:
				var record := sim.get_component(record_name)
				if record != null:
					var state := record.state_dict()
					if not state.is_empty():
						states[record_name] = state
		cab_list.append({
			"name": name_,
			"pos": [node.global_position.x, node.global_position.y, node.global_position.z],
			"rot_y": node.rotation.y,
			"modules": module_list, "states": states,
		})
	var jb_list: Array = []
	for name_: String in junction_boxes:
		var entry: Dictionary = junction_boxes[name_]
		var node := entry["node"] as Node3D
		var states := {}
		for record_name: String in entry["records"]:
			var record := sim.get_component(record_name)
			if record != null and not record.state_dict().is_empty():
				states[record_name] = record.state_dict()
		jb_list.append({
			"name": name_,
			"pos": [node.global_position.x, node.global_position.y - (JunctionBoxView.POST_H if entry["on_post"] else 0.0),
				node.global_position.z],
			"rot_y": node.rotation.y, "channels": entry["channels"], "on_post": entry["on_post"],
			"states": states,
		})
	var station_list: Array = []
	for name_: String in control_stations:
		var entry: Dictionary = control_stations[name_]
		var node := entry["node"] as Node3D
		var states := {}
		for record_name: String in entry["records"]:
			var record := sim.get_component(record_name)
			if record != null and not record.state_dict().is_empty():
				states[record_name] = record.state_dict()
		station_list.append({
			"name": name_,
			"pos": [node.global_position.x, node.global_position.y - (ControlStationView.POST_H if entry["on_post"] else 0.0),
				node.global_position.z],
			"rot_y": node.rotation.y, "devices": entry["devices"], "on_post": entry["on_post"],
			"states": states,
		})
	var payload := {
		"version": SAVE_VERSION, "time": sim.time, "junction_boxes": jb_list,
		"campaign": campaign.state_dict() if campaign != null else {},
		"control_stations": station_list,
		"components": comps, "wires": wire_list, "structures": struct_list,
		"runs": run_list, "cabinets": cab_list,
		# The solver's answer, nozzle by nozzle, so a load starts where the
		# plant was rather than cold.
		"pressures": sim.port_pressures(),
	}
	return payload


func save_game() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot(), "  "))
	return true


func _params_for(record: SimComponent) -> Dictionary:
	if record is SimTank:
		var tank_rec := record as SimTank
		return {"height_m": tank_rec.height_m, "diameter_m": tank_rec.diameter_m,
			"nozzle_cv_lps": tank_rec.nozzle_cv_lps, "open_top": tank_rec.open_top}
	if record is SimOrifice:
		return {"cv_lps": (record as SimOrifice).cv_lps}
	if record is SimNeedleValve:
		var nv := record as SimNeedleValve
		return {"cv_lps": nv.cv_lps, "turns": nv.turns}
	if record is SimBallValve:
		var bv := record as SimBallValve
		return {"cv_lps": bv.cv_lps, "stroke_s": bv.stroke_s}
	if record is SimSolenoidValve:
		return {"cv_lps": (record as SimSolenoidValve).cv_lps}
	if record is SimMeteringPump:
		var mp := record as SimMeteringPump
		return {"rated_lps": mp.rated_lps, "max_head_m": mp.max_head_m}
	if record is SimRegulator:
		var pr := record as SimRegulator
		return {"set_kpa": pr.set_kpa, "cv_lps": pr.cv_lps}
	if record is SimRotameter:
		return {"range_lps": (record as SimRotameter).range_lps}
	if record is SimVialMagazine:
		var vm := record as SimVialMagazine
		return {"vial_ml": vm.vial_ml, "rate_per_min": vm.rate_per_min}
	if record is SimVialTrack:
		var vt := record as SimVialTrack
		return {"length_m": vt.length_m, "speed_mps": vt.speed_mps}
	if record is SimStarWheel:
		var sw := record as SimStarWheel
		return {"pockets": sw.pockets, "pitch_radius_m": sw.pitch_radius_m, "index_s": sw.index_s,
			"out_station": sw.out_station}
	if record is SimStopGate:
		return {"stroke_s": (record as SimStopGate).stroke_s}
	if record is SimLoadCell:
		var lc := record as SimLoadCell
		return {"range_g": lc.range_g, "target_g": lc.target_g}
	if record is SimFillNeedle:
		return {"cv_lps": (record as SimFillNeedle).cv_lps}
	if record is SimCapper:
		return {"cap_s": (record as SimCapper).cap_s}
	if record is SimPump:
		var pump_rec := record as SimPump
		return {"rated_lps": pump_rec.rated_lps, "head_m": pump_rec.head_m}
	if record is SimFloatSwitch:
		var fs := record as SimFloatSwitch
		return {"low_l": fs.low_l, "high_l": fs.high_l}
	if record is SimGauge:
		var g := record as SimGauge
		return {"liters_per_meter": g.liters_per_meter, "species": g.species_key(), "meter_k": g.meter_k,
			"range_kpa": g.range_kpa}
	if record is SimColumn:
		var col := record as SimColumn
		return {"charge_l": col.charge_l, "max_duty_kw": col.max_duty_kw}
	if record is SimControlValve:
		var cvalve := record as SimControlValve
		return {"cv_lps": cvalve.cv_lps, "tau_s": cvalve.tau_s, "dn": cvalve.dn}
	if record is SimBlockValve:
		var xv := record as SimBlockValve
		return {"cv_lps": xv.cv_lps, "stroke_s": xv.stroke_s, "dn": xv.dn}
	if record is SimPID:
		var pid := record as SimPID
		return {"kp": pid.kp, "ki": pid.ki, "kd": pid.kd, "sp": pid.sp,
			"out_min": pid.out_min, "out_max": pid.out_max}
	if record is SimTerminal:
		return {"kind": (record as SimTerminal).kind}
	if record is SimMainsFeed:
		return {"spec": (record as SimMainsFeed).spec, "ways": (record as SimMainsFeed).ways}
	if record is SimTee:
		return {"mode": (record as SimTee).mode, "dn": (record as SimTee).dn}
	if record is SimCap:
		var cap_view := views.get(record.comp_name) as CapView
		return {"line_y": cap_view.line_y if cap_view != null else 0.35}
	if record is SimTrendScreen:
		var screen := record as SimTrendScreen
		return {"tags": screen.tags.duplicate(), "window_s": screen.window_s}
	if record is SimDrain:
		return {"rate_lps": (record as SimDrain).rate_lps}
	if record is SimReactor:
		var reac := record as SimReactor
		return {"capacity_l": reac.capacity_l, "rate_lps": reac.rate_lps,
			"height_m": reac.height_m}
	if record is SimCentrifuge:
		return {"rate_lps": (record as SimCentrifuge).rate_lps}
	if record is SimHeatExchanger:
		return {"max_duty_kw": (record as SimHeatExchanger).max_duty_kw}
	if record is SimSteamGen:
		return {"rated_kgps": (record as SimSteamGen).rated_kgps}
	if record is SimSource:
		var src := record as SimSource
		return {"species": src.species_key(), "temp_c": src.temp_c,
			"pressure_kpa": src.pressure_kpa}
	if record is SimCrystallizer:
		var cx := record as SimCrystallizer
		return {"capacity_l": cx.capacity_l, "height_m": cx.height_m}
	if record is SimDryer:
		return {"rate_lps": (record as SimDryer).rate_lps}
	if record is SimStill:
		var st := record as SimStill
		return {"rate_lps": st.rate_lps, "cut_c": st.cut_c, "sharpness": st.sharpness}
	return {}


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) < 3:
		return false
	return restore(parsed as Dictionary)


## Rebuild the plant from a snapshot: everything placed is freed and
## laid again from the payload. Undo and redo restore through here,
## and no checkpoint is taken while it runs.
func restore(payload: Dictionary) -> bool:
	_restoring = true
	_vial_line_dirty = true
	if campaign != null and payload.has("campaign"):
		campaign.apply_state(payload["campaign"])

	for name_: String in views:
		if not member_of.has(name_):  # members share the cabinet node
			(views[name_] as Node).queue_free()
	for visual in _wire_visuals:
		if visual["node"] != null:
			(visual["node"] as Node).queue_free()
	for name_: String in structures:
		((structures[name_] as Dictionary)["node"] as Node).queue_free()
	for name_: String in runs:
		((runs[name_] as Dictionary)["node"] as Node).queue_free()
	for name_: String in cabinets:
		((cabinets[name_] as Dictionary)["node"] as Node).queue_free()
	# Enclosures too, or the saved ones are refused as duplicates and
	# their terminals never come back.
	for name_: String in junction_boxes:
		((junction_boxes[name_] as Dictionary)["node"] as Node).queue_free()
	for name_: String in control_stations:
		((control_stations[name_] as Dictionary)["node"] as Node).queue_free()
	views.clear()
	equip_types.clear()
	protected.clear()
	structures.clear()
	runs.clear()
	cabinets.clear()
	junction_boxes.clear()
	control_stations.clear()
	member_of.clear()
	mounted.clear()
	_wire_visuals.clear()
	_new_graph()

	for entry: Dictionary in payload.get("cabinets", []):
		var pos_arr: Array = entry["pos"]
		place_cabinet(entry["name"],
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]), float(entry.get("rot_y", 0.0)))
		for module_v: Variant in entry.get("modules", []):
			var module := module_v as Dictionary
			cabinet_add_module(entry["name"], str(module["type"]),
				int(module["rail"]), int(module["slot"]),
				str(module["id"]), int(module.get("bank", -1)))
		var states: Dictionary = entry.get("states", {})
		for record_name: String in states:
			var record := sim.get_component(record_name)
			if record != null:
				record.apply_state(states[record_name])

	for entry: Dictionary in payload.get("junction_boxes", []):
		var pos_arr: Array = entry["pos"]
		place_junction_box(entry["name"], Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			float(entry.get("rot_y", 0.0)), int(entry.get("channels", 12)), bool(entry.get("on_post", true)))
		var jb_states: Dictionary = entry.get("states", {})
		for record_name: String in jb_states:
			var record := sim.get_component(record_name)
			if record != null:
				record.apply_state(jb_states[record_name])

	for entry: Dictionary in payload.get("control_stations", []):
		var pos_arr: Array = entry["pos"]
		place_control_station(entry["name"], Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			float(entry.get("rot_y", 0.0)), entry.get("devices", default_station_devices()),
			bool(entry.get("on_post", true)))
		var station_states: Dictionary = entry.get("states", {})
		for record_name: String in station_states:
			var record := sim.get_component(record_name)
			if record != null:
				record.apply_state(station_states[record_name])

	for entry: Dictionary in payload.get("runs", []):
		var pts: Array = []
		for point: Array in entry["points"]:
			pts.append(Vector3(point[0], point[1], point[2]))
		# A multicore's circuits come back with it, and its getter reads
		# the reloaded wires by name.
		var circuits: Array = entry.get("circuits", [])
		place_run(entry["kind"], entry["name"], pts,
			_multicore_getter(circuits.duplicate(true)) if not circuits.is_empty() else Callable())
		if not circuits.is_empty():
			(runs[entry["name"]] as Dictionary)["circuits"] = circuits.duplicate(true)
		if str(entry.get("color", "")) != "":
			set_run_service((runs[entry["name"]] as Dictionary)["node"] as PipeView,
				Color.html(str(entry["color"])), str(entry.get("label", "")), str(entry.get("fitting", "")))

	for entry: Dictionary in payload.get("structures", []):
		var pos_arr: Array = entry["pos"]
		place_structure(entry["type"], entry["name"],
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]), float(entry.get("rot_y", 0.0)),
			float(entry.get("length", -1.0)))
		if str(entry.get("text", "")) != "":
			set_sign_text(entry["name"], str(entry["text"]))

	for entry: Dictionary in payload["components"]:
		if entry.has("mount"):
			continue  # after its host
		var pos_arr: Array = entry["pos"]
		var record := place(entry["type"], entry["name"], entry.get("params", {}),
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			float(entry.get("rot_y", 0.0)), bool(entry.get("protected", false)))
		if record != null:
			record.apply_state(entry.get("state", {}))
			var loaded_view: Node3D = views.get(entry["name"])
			if loaded_view is TankView:
				(loaded_view as TankView).rebuild()  # sized by restored state
				if entry.has("nozzles"):
					(loaded_view as TankView).apply_nozzles(entry["nozzles"])
	for entry: Dictionary in payload["components"]:
		if not entry.has("mount"):
			continue
		var spot: Dictionary = entry["mount"]
		var record := mount_instrument(entry["type"], entry["name"], entry.get("params", {}),
			str(spot["host"]), float(spot["frac"]), float(spot["angle"]),
			bool(entry.get("protected", false)))
		if record != null:
			record.apply_state(entry.get("state", {}))
	for wire_entry: Dictionary in payload["wires"]:
		var waypoints: Array = []
		for point: Array in wire_entry.get("waypoints", []):
			waypoints.append(Vector3(point[0], point[1], point[2]))
		_next_wire_fixed = bool(wire_entry.get("fixed", false))
		var error := connect_equipment(wire_entry["src"], wire_entry["src_port"],
			wire_entry["dst"], wire_entry["dst_port"], waypoints,
			not bool(wire_entry.get("hidden", false)))
		_next_wire_fixed = false
		if error == "" and not (wire_entry.get("locks", []) as Array).is_empty():
			var locks: Array = []
			for point: Array in wire_entry["locks"]:
				locks.append(Vector3(point[0], point[1], point[2]))
			(_wire_visuals[_wire_visuals.size() - 1] as Dictionary)["locks"] = locks
		if error == "" and str(wire_entry.get("color", "")) != "":
			set_run_service((_wire_visuals[_wire_visuals.size() - 1] as Dictionary)["node"] as PipeView,
				Color.html(str(wire_entry["color"])), str(wire_entry.get("label", "")),
				str(wire_entry.get("fitting", "")))
		# An older save's hand-set "k" is ignored: the line's length and
		# size make its resistance.
		if error == "" and wire_entry.has("dn"):
			set_run_size((_wire_visuals[_wire_visuals.size() - 1] as Dictionary)["node"] as PipeView,
				int(wire_entry["dn"]))
	sim.time = float(payload.get("time", 0.0))
	sim.load_pressures(payload.get("pressures", {}) as Dictionary)
	_sync_bores(views.keys())
	_sync_catches()   # an open end finds its vessel again at once, not at the sweep

	tank = sim.get_component("supply_tank") as SimTank
	switch = sim.get_component("level_switch") as SimFloatSwitch
	relay = sim.get_component("pump_relay") as SimRelay
	pump = sim.get_component("fill_pump") as SimPump
	if hmi_view != null and tank != null:
		hmi_view.panel.setup(historian, tank, switch, relay, pump)
	_restoring = false
	return true
