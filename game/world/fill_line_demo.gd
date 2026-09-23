class_name FillLineDemo
## The filling line demo on the Maine site (director, 2026-09-22: "build a
## vial filler from individual parts, rather than have an all-in-one
## object"; a demo of its own, not part of the showcase). Every part is a
## placeable record, every link the plant's own rule (VialLine), and the
## PLC's program is the whole of the machine's intelligence:
##
##   VM-601  magazine of 10 mL vials, twenty a minute
##   VT-601  2.4 m track; at its fill station a stop gate XG-601, a
##           photo-eye ZE-601, a load cell WT-601 (setpoint 10 g) and a
##           fill needle FN-601 fed through solenoid valve SV-601 on DN6
##           tubing from a product header at 60 kPa
##   SW-601  six-pocket star wheel, the capper CP-601 at station 2
##   VT-602  1.2 m track to the outfeed table VX-601, the batch record
##
## Ladder (PLC in CAB-601): a vial in the beam for 0.3 s (TON t_0) opens
## the valve until the setpoint contact makes; the setpoint latches
## FILLED (m_0) until the vial clears the beam and releases the gate
## meanwhile; t_1 indexes the wheel every 1.5 s; the capper caps at rest.
## Fifteen vials a minute arrive 0.4 m apart and a fill takes under
## three seconds, so no queue forms at the gate.

const Z := -16.0
## The setpoint sits below the 10 mL wanted by what is still falling when
## the valve shuts: the contact reaches the PLC a scan late, its output
## reaches the coil a scan later, and the plunger takes a scan to seat
## (in-flight compensation, as every gravimetric filler has).
const TARGET_G := 9.05
const TUBE_DN := 6
const PRODUCT := Color(0.13, 0.55, 0.28)   # ASME green, as the drip demo's water


static func build(plant: Plant) -> void:
	var deck := VialPartView.DECK
	var d: float = SimVial.SIZES[10][0]
	# ---- the line, west to east along z = Z ------------------------------
	plant.place("vial_magazine", "vm_601", {"vial_ml": 10, "rate_per_min": 15.0},
		Vector3(0.0, 0.0, Z), 0.0, false)
	var t1 := plant.place("vial_track", "vt_601", {"length_m": 2.4, "speed_mps": 0.1},
		Vector3(0.35 + 1.2, 0.0, Z), 0.0, false) as SimVialTrack
	var gate_s := 1.6
	var hold_x := 0.35 + gate_s - d / 2.0
	plant.place("stop_gate", "xg_601", {}, Vector3(0.35 + gate_s, 0.0, Z), 0.0, false)
	plant.place("photo_eye", "ze_601", {}, Vector3(hold_x, 0.0, Z), 0.0, false)
	plant.place("load_cell", "wt_601", {"target_g": TARGET_G}, Vector3(hold_x, 0.0, Z), 0.0, false)
	plant.place("fill_needle", "fn_601", {"cv_lps": 0.005}, Vector3(hold_x, 0.0, Z), 0.0, false)
	var wheel_x := 0.35 + 2.4 + 0.12
	var wheel := plant.place("star_wheel", "sw_601", {}, Vector3(wheel_x, 0.0, Z), 0.0, false) as SimStarWheel
	var station := StarWheelView.station_point(wheel.pitch_radius_m, wheel.pockets, 2.0)
	plant.place("capper", "cp_601", {"cap_s": 0.8}, Vector3(wheel_x + station.x, 0.0, Z + station.z),
		atan2(station.x, station.z), false)
	var t2 := plant.place("vial_track", "vt_602", {"length_m": 1.2, "speed_mps": 0.1},
		Vector3(wheel_x + 0.12 + 0.6, 0.0, Z), 0.0, false) as SimVialTrack
	plant.place("vial_table", "vx_601", {},
		Vector3(wheel_x + 0.12 + 1.2 + VialTableView.RADIUS + 0.05, 0.0, Z), 0.0, false)
	t1.hand_on = true
	t2.hand_on = true
	VialLine.sync(plant)

	# ---- the product to the needle ---------------------------------------
	# Behind the fill station, on the side every part of the line keeps
	# its fittings.
	plant.place("source", "supply_601", {"species": "product", "pressure_kpa": 60.0},
		Vector3(-0.6, 0.0, Z + 0.9), 0.0, false)
	plant.place("solenoid_valve", "sv_601", {"cv_lps": 0.3}, Vector3(0.8, 0.0, Z + 0.9), 0.0, false)
	_tube(plant, "supply_601", "outlet", "sv_601", "inlet")
	_tube(plant, "sv_601", "outlet", "fn_601", "inlet")

	# ---- power: a feeder, a 24 V supply behind each load ----------------
	# Each supply turned to face the line, its output toward its load and
	# its input toward the feeder behind.
	plant.place("mains", "mains_601", {"ways": 8}, Vector3(-1.0, 0.0, Z + 3.0), 0.0, false)
	var loads := {"vt_601": 2.35, "sw_601": 2.95, "cp_601": 3.55, "vt_602": 4.15}
	var n := 1
	for load: String in loads:
		var psu := "psu_60%d" % n
		plant.place("psu", psu, {}, Vector3(float(loads[load]), 0.0, Z + 1.3), PI / 2.0, false)
		_cable(plant, "mains_601", plant.free_way("mains_601"), psu, "ac_in")
		_cable(plant, psu, "dc_out", load, "power")
		n += 1

	# ---- the cabinet, its PLC and its program ----------------------------
	var cab := "cab_601"
	plant.place_cabinet(cab, Vector3(1.0, 0.0, Z + 2.2), PI)
	plant.cabinet_add_module(cab, "psu", 0, 0)
	plant.cabinet_add_module(cab, "plc", 0, 4)
	plant.cabinet_add_module(cab, "card_di", 0, 8)
	plant.cabinet_add_module(cab, "card_do", 0, 10)
	plant.cabinet_add_module(cab, "tb8d", 1, 0)
	plant.cabinet_add_module(cab, "tb8d", 2, 0)
	var plc_name := plant.cabinet_plc(cab)
	var plc := plant.sim.get_component(plc_name) as SimPLC
	var cab_psu := ""
	for record_name in plant.cabinet_all_records(cab):
		if plant.equip_types.get(record_name) == "psu":
			cab_psu = record_name
	var di := "%s_m5_t" % cab
	var do := "%s_m6_t" % cab
	plant.connect_equipment(cab_psu, "dc_out", plc_name, "power", [], false)
	for i in 4:
		plant.connect_equipment(di + str(i + 1), "out", plc_name, "di_%d" % i, [], false)
		plant.connect_equipment(plc_name, "do_%d" % i, do + str(i + 1), "in", [], false)
	_cable(plant, "mains_601", plant.free_way("mains_601"), cab_psu, "ac_in")
	# di_0 ZE-601 vial present, di_1 WT-601 at target, di_2 SW-601 home.
	# The wheel's cable is laid first: it comes furthest, and the eye's
	# and the cell's, laid after it, find their way round it.
	_cable(plant, "sw_601", "home", di + "3", "in")
	_cable(plant, "ze_601", "present", di + "1", "in")
	_cable(plant, "wt_601", "at_target", di + "2", "in")
	# do_0 SV-601, do_1 XG-601, do_2 SW-601 index, do_3 CP-601.
	_cable(plant, do + "1", "out", "sv_601", "coil")
	_cable(plant, do + "2", "out", "xg_601", "release")
	_cable(plant, do + "3", "out", "sw_601", "index")
	_cable(plant, do + "4", "out", "cp_601", "cap")
	plc.set_program([
		# The vial has settled in the beam: 0.3 s.
		{"coil": "t_0", "logic": [[{"ref": "di_0"}]]},
		# m_0 FILLED: set at the setpoint, held while the vial is in the
		# beam. Without it the valve opened again as the full vial rolled
		# off the pan still in the beam, onto the bare belt (the first
		# version did, 2026-09-22).
		{"coil": "m_0", "logic": [[{"ref": "di_1"}, {"ref": "di_0"}], [{"ref": "m_0"}, {"ref": "di_0"}]]},
		# Fill while it is settled there and not yet filled. The beam is
		# asked again beside its own timer: a timer's done bit is updated
		# at the end of the scan, so in the scan the vial leaves the beam
		# t_0 still reads done while m_0 has already dropped, and without
		# di_0 here the valve pulsed open for a scan onto the bare belt.
		{"coil": "do_0", "logic": [[{"ref": "di_0"}, {"ref": "t_0"}, {"ref": "m_0", "nc": true},
			{"ref": "di_1", "nc": true}]]},
		# Filled: let it go, until it has cleared the beam.
		{"coil": "do_1", "logic": [[{"ref": "m_0"}]]},
		# The wheel's beat: t_1 restarts itself, so its done bit is a
		# one-scan pulse every preset.
		{"coil": "t_1", "logic": [[{"ref": "t_1", "nc": true}]]},
		{"coil": "do_2", "logic": [[{"ref": "t_1"}]]},
		# Cap whatever stands under the head while the wheel is at rest.
		{"coil": "do_3", "logic": [[{"ref": "di_2"}]]},
	])
	plc.set_timer_preset(0, 0.3)
	plc.set_timer_preset(1, 1.5)


static func _tube(plant: Plant, a: String, a_port: String, b: String, b_port: String) -> void:
	plant.next_line_size(TUBE_DN)
	var why := plant.connect_equipment(a, a_port, b, b_port)
	if why != "":
		push_error("fill line, %s -> %s: %s" % [a, b, why])
		return
	var visuals: Array = plant.get("_wire_visuals")
	for i in range(visuals.size() - 1, -1, -1):
		var visual: Dictionary = visuals[i]
		if str(visual["a"]) == a and visual["node"] is PipeView:
			plant.set_run_service(visual["node"] as PipeView, PRODUCT, "", "tube")
			return


static func _cable(plant: Plant, a: String, a_port: String, b: String, b_port: String) -> void:
	var why := plant.connect_equipment(a, a_port, b, b_port)
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
	var fn := plant.sim.get_component("fn_601") as SimFillNeedle
	var cp := plant.sim.get_component("cp_601") as SimCapper
	var src := plant.sim.get_component("supply_601") as SimSource
	if vm == null or vx == null:
		return out
	var on_line := t1.vials_on + sw.vials_on + t2.vials_on
	out.append("[flowstate] fill line: %d vials in, %d on the line, %d out (%d capped) · links %s" % [
		vm.supplied, on_line, vx.count, vx.capped_count, _links(plant)])
	out.append("[flowstate] fill line: fills %.2f mL mean (%.2f to %.2f) · %d caps · needle %.2f mL in vials, %.2f mL spilled" % [
		vx.mean_ml, vx.min_ml, vx.max_ml, cp.caps_used, fn.delivered_l * 1000.0, fn.spilled_l * 1000.0])
	var held := t1.held_l + sw.held_l + t2.held_l
	out.append("[flowstate] fill line: header %.2f mL = vials out %.2f + on the line %.2f + spilled %.2f (residual %.4f mL) · mounts %s" % [
		src.total_l * 1000.0, vx.out_l * 1000.0, held * 1000.0, fn.spilled_l * 1000.0,
		(src.total_l - vx.out_l - held - fn.spilled_l) * 1000.0, _mounts(plant)])
	return out


static func _links(plant: Plant) -> String:
	var parts := PackedStringArray()
	for wire in plant.sim.wires:
		if wire.src.kind == SimTypes.PortKind.ITEM:
			parts.append("%s>%s" % [wire.src.owner_name, wire.dst.owner_name])
	return ", ".join(parts)


static func _mounts(plant: Plant) -> String:
	var parts := PackedStringArray()
	for name_: String in ["xg_601", "ze_601", "wt_601", "fn_601", "cp_601"]:
		var device := plant.sim.get_component(name_) as SimVialMount
		if device != null:
			parts.append("%s@%s:%.3f" % [name_, device.host, device.s_m])
	return ", ".join(parts)
