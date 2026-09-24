class_name FillLineDemo
## The filling line demo on the Maine site, a vial filler built from
## individual parts, a demo of its own and not part of the showcase.
## Every part is a placeable
## record, every link the plant's own rule (VialLine), and the PLC's
## program is the whole of the machine's intelligence.
##
## A filling room of 16 m by 8 m, a seamless floor, walled, with an open bay in the
## north wall. The line runs along the south side:
##
##   VM-601  magazine of 10 mL vials, forty a minute
##   VT-601  3.6 m track at 0.3 m/s with two fill stations, 1.2 m apart,
##           each a stop gate, a photo-eye, a load cell and a fill needle
##           on its own solenoid valve: station A puts in about half the
##           dose, station B tops it up to 10 mL, so each vial spends half
##           as long under a needle and two vials fill at once
##   SW-601  six-pocket star wheel on a 1.2 s beat, capper CP-601 at station 2
##   VT-602  1.6 m track to the outfeed table VX-601, the batch record
##
## The stations never let a queue form: forty a minute at 0.3 m/s stand the
## vials 0.45 m apart, and a station takes about a second from a vial's
## arrival to its release, well inside the 1.4 s the next one needs to
## close the gap. A queue would defeat the gates: a vial following nose to
## tail keeps the beam broken as the filled one leaves, the latch holds,
## and it slips through unfilled. A real line spaces its vials the same
## way, or with a timing screw.
##
## The product comes from a header through a tee to the two valves on DN6
## tubing. The cabinet with the PLC and its feeder stand along the north
## wall, three metres from the line. The cabinet's own 24 V supply feeds
## a fused distribution strip on its rail, one way per load; those leads
## run in a cable tray, and the field cables together in one clear
## sleeve.

const Z := -20.0              # the line
const CONTROLS_Z := -16.9     # the cabinet and its feeder, along the north wall
const CABINET_X := 8.0
const FLOOR := 0.06           # the top of the slab
const ROOM := Rect2(-2.0, -24.0, 16.0, 8.0)   # x, z, width, depth
const TUBE_DN := 6
const PRODUCT := Color(0.13, 0.55, 0.28)   # ASME green, as the drip demo's water
## Each setpoint sits below what it is for by what is still falling when
## its valve shuts: the contact reaches the PLC a scan late, its output
## reaches the coil a scan later, and the plunger takes a scan to seat
## (in-flight compensation, as every gravimetric filler has). Station A
## is for 5 mL, station B for 10.
const TARGET_A_G := 1.7
const TARGET_B_G := 6.97
const GATE_A := 1.2           # the stations along VT-601, metres
const GATE_B := 2.4


static func build(plant: Plant) -> void:
	_room(plant)
	var d: float = SimVial.SIZES[10][0]
	var y := FLOOR
	# ---- the line, west to east along z = Z ------------------------------
	plant.place("vial_magazine", "vm_601", {"vial_ml": 10, "rate_per_min": 40.0},
		Vector3(0.5, y, Z), 0.0, false)
	var in_x := 0.5 + 0.35
	var t1 := plant.place("vial_track", "vt_601", {"length_m": 3.6, "speed_mps": 0.3},
		Vector3(in_x + 1.8, y, Z), 0.0, false) as SimVialTrack
	_station(plant, "a", in_x + GATE_A, d, TARGET_A_G)
	_station(plant, "b", in_x + GATE_B, d, TARGET_B_G)
	var wheel_x := in_x + 3.6 + 0.12
	var wheel := plant.place("star_wheel", "sw_601", {"index_s": 0.3}, Vector3(wheel_x, y, Z), 0.0, false) as SimStarWheel
	var station := StarWheelView.station_point(wheel.pitch_radius_m, wheel.pockets, 2.0)
	plant.place("capper", "cp_601", {"cap_s": 0.5}, Vector3(wheel_x + station.x, y, Z + station.z),
		atan2(station.x, station.z), false)
	var t2 := plant.place("vial_track", "vt_602", {"length_m": 1.6, "speed_mps": 0.3},
		Vector3(wheel_x + 0.12 + 0.8, y, Z), 0.0, false) as SimVialTrack
	plant.place("vial_table", "vx_601", {},
		Vector3(wheel_x + 0.12 + 1.6 + VialTableView.RADIUS + 0.05, y, Z), 0.0, false)
	t1.hand_on = true
	t2.hand_on = true
	VialLine.sync(plant)

	# ---- the product to the two needles ----------------------------------
	plant.place("source", "supply_601", {"species": "product", "pressure_kpa": 60.0},
		Vector3(-0.5, y, Z + 2.4), 0.0, false)
	plant.place("tee_split", "tee_601", {"dn": TUBE_DN}, Vector3(0.9, y, Z + 2.4), 0.0, false)
	plant.place("solenoid_valve", "sv_601a", {"cv_lps": 0.3}, Vector3(1.4, y, Z + 1.4), 0.0, false)
	plant.place("solenoid_valve", "sv_601b", {"cv_lps": 0.3}, Vector3(2.6, y, Z + 2.4), 0.0, false)
	_tube(plant, "supply_601", "outlet", "tee_601", "in")
	_tube(plant, "tee_601", "b", "sv_601a", "inlet")
	_tube(plant, "tee_601", "a", "sv_601b", "inlet")
	_tube(plant, "sv_601a", "outlet", "fn_601a", "inlet")
	_tube(plant, "sv_601b", "outlet", "fn_601b", "inlet")

	# ---- the cabinet, its PLC and its program ----------------------------
	var cab := "cab_601"
	plant.place_cabinet(cab, Vector3(CABINET_X, y, CONTROLS_Z), PI)
	plant.cabinet_add_module(cab, "psu", 0, 0)
	plant.cabinet_add_module(cab, "plc", 0, 4)
	plant.cabinet_add_module(cab, "card_di", 0, 8)
	plant.cabinet_add_module(cab, "card_do", 0, 10)
	plant.cabinet_add_module(cab, "tb8d", 1, 0)
	plant.cabinet_add_module(cab, "tb8d", 2, 0)
	plant.cabinet_add_module(cab, "pd8", 1, 4)
	var plc_name := plant.cabinet_plc(cab)
	var plc := plant.sim.get_component(plc_name) as SimPLC
	var cab_psu := ""
	for record_name in plant.cabinet_all_records(cab):
		if plant.equip_types.get(record_name) == "psu":
			cab_psu = record_name
	var di := "%s_m5_t" % cab
	var do := "%s_m6_t" % cab
	var strip := ""
	for record_name in plant.cabinet_all_records(cab):
		if plant.equip_types.get(record_name) == "power_dist":
			strip = record_name
	# The supply feeds the strip; the PLC rides on its last way.
	plant.connect_equipment(cab_psu, "dc_out", strip, "in", [], false)
	plant.connect_equipment(strip, "way8", plc_name, "power", [], false)
	for i in 6:
		plant.connect_equipment(di + str(i + 1), "out", plc_name, "di_%d" % i, [], false)
		plant.connect_equipment(plc_name, "do_%d" % i, do + str(i + 1), "in", [], false)
	# 480 V from a feeder beside the cabinet to its supply: the one
	# feeder the line needs.
	plant.place("mains", "mains_601", {"ways": 2}, Vector3(CABINET_X + 2.4, y, CONTROLS_Z), 0.0, false)
	_cable(plant, "mains_601", plant.free_way("mains_601"), cab_psu, "ac_in")
	# 24 V to each load from its own fused way of the strip, in one 150 mm
	# cable tray, CT-601, on stands a little off the floor: from the
	# cabinet's field-out flank down the room and along the line, each
	# cable climbing out at its load.
	var loads: Array[String] = ["vt_601", "sw_601", "cp_601", "vt_602"]
	var west := INF
	for load in loads:
		west = minf(west, plant._marker_pos(load, "power").x)
	var tray_y := FLOOR + 0.35
	var tray_x := CABINET_X - 1.0
	plant.place_run("run_tray_150", "ct_601", [plant.to_local(Vector3(tray_x, tray_y, CONTROLS_Z - 0.2)),
		plant.to_local(Vector3(tray_x, tray_y, Z + 1.4)),
		plant.to_local(Vector3(west - 0.3, tray_y, Z + 1.4))])
	for i in loads.size():
		var way := "way%d" % (i + 1)
		_cable(plant, strip, way, loads[i], "power")
		var why := plant.thread_cable(plant.line_between(strip, way, loads[i], "power"), "ct_601")
		if why != "":
			push_error("fill line, tray: %s: %s" % [loads[i], why])
	# The terminal strips in the order the cables arrive, so none crosses
	# another: each input or output is named once here and the ladder is
	# written against the names. Laid in this order.
	var inputs := [["sw_601", "home"], ["ze_601b", "present"], ["wt_601b", "at_target"],
		["wt_601a", "at_target"], ["ze_601a", "present"]]
	var outputs := [["sv_601a", "coil"], ["xg_601a", "release"], ["sv_601b", "coil"],
		["sw_601", "index"], ["cp_601", "cap"], ["xg_601b", "release"]]
	# Every field cable runs through one sleeve, SL-601, laid on the
	# floor from in front of the line to in front of the cabinet: each
	# cable's tails fan out from its ends to the device and the terminal.
	var di_of := {}
	var field: Array = []
	for i in inputs.size():
		var point: Array = inputs[i]
		_cable(plant, str(point[0]), str(point[1]), di + str(i + 1), "in")
		di_of[str(point[0])] = "di_%d" % i
		field.append([str(point[0]), str(point[1]), di + str(i + 1), "in"])
	var do_of := {}
	for i in outputs.size():
		var point: Array = outputs[i]
		_cable(plant, do + str(i + 1), "out", str(point[0]), str(point[1]))
		do_of[str(point[0]) + "." + str(point[1])] = "do_%d" % i
		field.append([do + str(i + 1), "out", str(point[0]), str(point[1])])
	var line_x := 0.0
	for point: Array in inputs + outputs:
		line_x += plant._marker_pos(str(point[0]), str(point[1])).x
	line_x /= float((inputs + outputs).size())
	var sleeve_z := CONTROLS_Z - 0.8
	plant.place_run("run_sleeve", "sl_601", [plant.to_local(Vector3(line_x, FLOOR, Z + 1.3)),
		plant.to_local(Vector3(line_x, FLOOR, sleeve_z)), plant.to_local(Vector3(CABINET_X, FLOOR, sleeve_z))])
	# Clear, so the circuits can be watched inside it.
	plant.set_sleeve_look("sl_601", true, "SL-601")
	for ends: Array in field:
		var view := plant.line_between(str(ends[0]), str(ends[1]), str(ends[2]), str(ends[3]))
		var why := "no line" if view == null else plant.thread_cable(view, "sl_601")
		if why != "":
			push_error("fill line, sleeve: %s.%s: %s" % [ends[0], ends[1], why])
	var program: Array = []
	program.append_array(_station_rungs(di_of["ze_601a"], di_of["wt_601a"], "t_0", "m_0",
		do_of["sv_601a.coil"], do_of["xg_601a.release"]))
	program.append_array(_station_rungs(di_of["ze_601b"], di_of["wt_601b"], "t_2", "m_1",
		do_of["sv_601b.coil"], do_of["xg_601b.release"]))
	program.append_array([
		# The wheel's beat: t_1 restarts itself, so its done bit is a
		# one-scan pulse every preset.
		{"coil": "t_1", "logic": [[{"ref": "t_1", "nc": true}]]},
		{"coil": do_of["sw_601.index"], "logic": [[{"ref": "t_1"}]]},
		# Cap whatever stands under the head while the wheel is at rest.
		{"coil": do_of["cp_601.cap"], "logic": [[{"ref": di_of["sw_601"]}]]},
	])
	plc.set_program(program)
	plc.set_timer_preset(0, 0.2)
	plc.set_timer_preset(1, 1.2)
	plc.set_timer_preset(2, 0.2)


## One fill station at `gate_x` on VT-601: the gate, and the eye, the load
## cell and the needle at the spot where the gate holds a vial.
static func _station(plant: Plant, tag: String, gate_x: float, d: float, target_g: float) -> void:
	var hold_x := gate_x - d / 2.0
	plant.place("stop_gate", "xg_601" + tag, {}, Vector3(gate_x, FLOOR, Z), 0.0, false)
	plant.place("photo_eye", "ze_601" + tag, {}, Vector3(hold_x, FLOOR, Z), 0.0, false)
	plant.place("load_cell", "wt_601" + tag, {"target_g": target_g}, Vector3(hold_x, FLOOR, Z), 0.0, false)
	plant.place("fill_needle", "fn_601" + tag, {"cv_lps": 0.015}, Vector3(hold_x, FLOOR, Z), 0.0, false)


## A station's ladder. A vial in the beam for the settle time (the TON)
## opens the valve until the setpoint contact makes; FILLED latches at
## the setpoint and holds while the vial is in the beam, releasing the
## gate meanwhile. Without the latch the valve would open again as the
## full vial rolls off the pan still in the beam, onto the bare belt; and
## the beam is asked again beside its own timer because a timer's done
## bit is updated at the end of the scan, so in the scan the vial leaves
## the beam the timer still reads done while the latch has already
## dropped, and the valve would pulse open for a scan.
static func _station_rungs(eye: String, at: String, settle: String, filled: String,
		valve: String, gate: String) -> Array:
	return [
		{"coil": settle, "logic": [[{"ref": eye}]]},
		{"coil": filled, "logic": [[{"ref": at}, {"ref": eye}], [{"ref": filled}, {"ref": eye}]]},
		{"coil": valve, "logic": [[{"ref": eye}, {"ref": settle}, {"ref": filled, "nc": true},
			{"ref": at, "nc": true}]]},
		{"coil": gate, "logic": [[{"ref": filled}]]},
	]


## The filling room: a seamless floor of 4 m slabs and walls of 4 m panels
## round it, windows along the west, and an open bay in the north wall
## where the site's walkway comes in.
static func _room(plant: Plant) -> void:
	var x0 := ROOM.position.x
	var z0 := ROOM.position.y
	var cols := int(ROOM.size.x / 4.0)
	var rows := int(ROOM.size.y / 4.0)
	for i in cols:
		for j in rows:
			plant.place_structure("s_slab_seamless", "fl_601_%d_%d" % [i, j],
				Vector3(x0 + 2.0 + 4.0 * i, 0.0, z0 + 2.0 + 4.0 * j), 0.0)
	for i in cols:
		var x := x0 + 2.0 + 4.0 * i
		plant.place_structure("s_wall", "wl_601_s%d" % i, Vector3(x, FLOOR, z0), 0.0)
		if i != 1:   # the bay
			plant.place_structure("s_wall", "wl_601_n%d" % i, Vector3(x, FLOOR, z0 + ROOM.size.y), 0.0)
	for j in rows:
		var z := z0 + 2.0 + 4.0 * j
		plant.place_structure("s_window", "wl_601_w%d" % j, Vector3(x0, FLOOR, z), PI / 2.0)
		plant.place_structure("s_wall", "wl_601_e%d" % j, Vector3(x0 + ROOM.size.x, FLOOR, z), PI / 2.0)


static func _tube(plant: Plant, a: String, a_port: String, b: String, b_port: String) -> void:
	plant.next_line_size(TUBE_DN)
	var why := plant.connect_equipment(a, a_port, b, b_port)
	if why != "":
		push_error("fill line, %s -> %s: %s" % [a, b, why])
		return
	var visuals: Array = plant.get("_wire_visuals")
	for i in range(visuals.size() - 1, -1, -1):
		var visual: Dictionary = visuals[i]
		if str(visual["a"]) == a and str(visual["a_port"]) == a_port and visual["node"] is PipeView:
			plant.set_run_service(visual["node"] as PipeView, PRODUCT, "", "tube")
			return


static func _cable(plant: Plant, a: String, a_port: String, b: String, b_port: String,
		waypoints: Array = []) -> void:
	var why := plant.connect_equipment(a, a_port, b, b_port, waypoints)
	if why != "":
		push_error("fill line, %s.%s -> %s.%s: %s" % [a, a_port, b, b_port, why])


## What the line is doing, for the headless smoke.
static func report(plant: Plant) -> PackedStringArray:
	var out := PackedStringArray()
	var vm := plant.sim.get_component("vm_601") as SimVialMagazine
	var t1 := plant.sim.get_component("vt_601") as SimVialTrack
	var sw := plant.sim.get_component("sw_601") as SimStarWheel
	var t2 := plant.sim.get_component("vt_602") as SimVialTrack
	var vx := plant.sim.get_component("vx_601") as SimVialTable
	var fa := plant.sim.get_component("fn_601a") as SimFillNeedle
	var fb := plant.sim.get_component("fn_601b") as SimFillNeedle
	var cp := plant.sim.get_component("cp_601") as SimCapper
	var src := plant.sim.get_component("supply_601") as SimSource
	if vm == null or vx == null:
		return out
	var on_line := t1.vials_on + sw.vials_on + t2.vials_on
	out.append("[flowstate] fill line: %d vials in, %d on the line, %d out (%d capped) · links %s" % [
		vm.supplied, on_line, vx.count, vx.capped_count, _links(plant)])
	var spilled := fa.spilled_l + fb.spilled_l
	out.append("[flowstate] fill line: fills %.2f mL mean (%.2f to %.2f) · %d caps · station A %.2f mL, B %.2f mL in vials, %.2f mL spilled" % [
		vx.mean_ml, vx.min_ml, vx.max_ml, cp.caps_used, fa.delivered_l * 1000.0, fb.delivered_l * 1000.0,
		spilled * 1000.0])
	var held := t1.held_l + sw.held_l + t2.held_l
	out.append("[flowstate] fill line: header %.2f mL = vials out %.2f + on the line %.2f + spilled %.2f (residual %.4f mL) · mounts %s" % [
		src.total_l * 1000.0, vx.out_l * 1000.0, held * 1000.0, spilled * 1000.0,
		(src.total_l - vx.out_l - held - spilled) * 1000.0, _mounts(plant)])
	var sleeved := 0
	for visual: Dictionary in plant.get("_wire_visuals"):
		if visual["node"] is PipeView and plant.cable_sleeve(visual["node"] as PipeView) == "sl_601":
			sleeved += 1
	var sleeve: Dictionary = plant.runs.get("sl_601", {})
	out.append("[flowstate] fill line: sleeve sl_601 carries %d cables, %d mm across" % [sleeved,
		roundi((sleeve["node"] as PipeView).radius() * 2000.0) if not sleeve.is_empty() else 0])
	return out


static func _links(plant: Plant) -> String:
	var parts := PackedStringArray()
	for wire in plant.sim.wires:
		if wire.src.kind == SimTypes.PortKind.ITEM:
			parts.append("%s>%s" % [wire.src.owner_name, wire.dst.owner_name])
	return ", ".join(parts)


static func _mounts(plant: Plant) -> String:
	var parts := PackedStringArray()
	for name_: String in ["xg_601a", "ze_601a", "wt_601a", "fn_601a", "xg_601b", "ze_601b", "wt_601b",
			"fn_601b", "cp_601"]:
		var device := plant.sim.get_component(name_) as SimVialMount
		if device != null:
			parts.append("%s@%s:%.3f" % [name_, device.host, device.s_m])
	return ", ".join(parts)
