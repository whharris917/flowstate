class_name RoutingExercises
## Routing exercises on the Maine site (director, 2026-09-19: the
## showcase's auto-routed pipes are "a spaghettified mess"; rather than
## work on the showcase, simple configurations go on the Maine factory
## one at a time, the director examines each auto-routed line and
## says what is wrong). Every exercise is a few pieces of equipment
## and a line laid with no waypoints, so what is seen is the router's
## own answer. They accumulate here in the order they were asked for.
##
## Exercise 2 is the drip demo (director, 2026-09-20): the small-bore
## family on one little line, ending in the air over an open tank.


static func build(plant: Plant) -> void:
	_one_source_one_pump(plant)
	_drip_demo(plant)


## Exercise 1: a single supply header leading to a single pump, on the
## pad, eight metres apart on one axis: the header's outlet faces the
## pump's inlet exactly in plan. The heights differ, a header at 1.55 m
## and a pump inlet at 0.42 m, so the line must drop once. (A tank was
## the first version; its inlet nozzle could not be aligned this way.)
static func _one_source_one_pump(plant: Plant) -> void:
	plant.place("source", "supply_1", {}, Vector3(-4.0, 0.0, -2.0), 0.0, false)
	plant.place("pump", "p_1", {"rated_lps": 3.0}, Vector3(4.0, 0.0, -2.0), 0.0, false)
	var err := plant.connect_equipment("supply_1", "outlet", "p_1", "inlet")
	if err != "":
		push_error("routing exercise 1: " + err)


## Exercise 2, the drip demo (director, 2026-09-20: "fill an open tank
## by routing a supply line to the air above the tank, adding a flow
## limiter, and letting the tank fill drop by drop, where the drops are
## audible"). A water header through a pressure regulator, a ball
## valve, a needle valve, a rotameter and a restriction orifice, all
## on DN6 tubing, the line rising to an open end over an open-topped
## tank. E on the needle valve turns the drip up a turn at a time; the
## CONFIGURE tab sets it exactly. Beside it the dosing line: a metering
## pump draws from the open tank through a solenoid valve into a second
## tank, the pump hand-started at its own switch on 24 V from a power
## supply, the solenoid from the DOSE button on a control station.
const LINE_Z := 10.0
const DOSE_Z := 8.6
const TUBE_DN := 6
const TUBE_COLOR := Color(0.13, 0.55, 0.28)   # water, ASME


static func _drip_demo(plant: Plant) -> void:
	# The drip line, west to east along z = 10.
	plant.place("source", "supply_2", {"pressure_kpa": 400.0}, Vector3(-4.5, 0.0, LINE_Z), 0.0, false)
	plant.place("regulator", "pr_2", {"set_kpa": 150.0, "cv_lps": 0.5}, Vector3(-2.5, 0.0, LINE_Z), 0.0, false)
	var bv := plant.place("ball_valve", "bv_2", {"cv_lps": 0.5}, Vector3(-1.0, 0.0, LINE_Z), 0.0, false) as SimBallValve
	var nv := plant.place("needle_valve", "nv_2", {"cv_lps": 0.0005, "turns": 10.0},
		Vector3(0.5, 0.0, LINE_Z), 0.0, false) as SimNeedleValve
	plant.place("rotameter", "fi_2", {"range_lps": 0.001}, Vector3(2.0, 0.0, LINE_Z), 0.0, false)
	plant.place("orifice", "ro_2", {"cv_lps": 0.0005}, Vector3(3.5, 0.0, LINE_Z), 0.0, false)
	var t2 := plant.place("tank", "t_2", {"height_m": 0.6, "diameter_m": 0.4, "open_top": true},
		Vector3(6.5, 0.0, LINE_Z), 0.0, false) as SimTank
	if bv != null:
		bv.open = true
		bv.position = 100.0
	if nv != null:
		nv.turns_open = 2.0
	if t2 != null:
		t2.charge(20.0, SimStream.pure(SimSpecies.WATER, 1.0).comp, SimStream.AMBIENT_C)
	_line(plant, "supply_2", "outlet", "pr_2", "inlet")
	_line(plant, "pr_2", "outlet", "bv_2", "inlet")
	_line(plant, "bv_2", "outlet", "nv_2", "inlet")
	_line(plant, "nv_2", "outlet", "fi_2", "inlet")
	_line(plant, "fi_2", "outlet", "ro_2", "inlet")
	# The open end: up past the tank's rim and over its middle. The
	# rise stands short of the tank so the riser is clear of it.
	var why := plant.connect_open("ro_2", "outlet",
		[Vector3(5.7, 0.32, LINE_Z), Vector3(5.7, 1.3, LINE_Z), Vector3(6.5, 1.3, LINE_Z)])
	if why != "":
		push_error("drip demo, open end: " + why)
	else:
		_style_last(plant, "ro_2")

	# The dosing line: the open tank's bottom nozzle to a metering
	# pump, a solenoid valve, and a closed tank.
	plant.place("metering_pump", "mp_2", {"rated_lps": 0.01, "max_head_m": 50.0},
		Vector3(9.0, 0.0, DOSE_Z), 0.0, false)
	plant.place("solenoid_valve", "sv_2", {"cv_lps": 0.3}, Vector3(10.5, 0.0, DOSE_Z), 0.0, false)
	plant.place("tank", "t_3", {"height_m": 0.6, "diameter_m": 0.4}, Vector3(13.0, 0.0, DOSE_Z), 0.0, false)
	_line(plant, "t_2", "outlet", "mp_2", "inlet")
	_line(plant, "mp_2", "outlet", "sv_2", "inlet")
	_line(plant, "sv_2", "outlet", "t_3", "inlet")
	# Power and control: 480 V from a feeder into a 24 V supply for the
	# pump; the solenoid's coil from a maintained DOSE button.
	plant.place("mains", "mains_2", {"ways": 2}, Vector3(9.0, 0.0, 6.0), 0.0, false)
	plant.place("psu", "psu_2", {}, Vector3(10.6, 0.0, 6.0), 0.0, false)
	plant.place_control_station("lcs_2", Vector3(12.2, 0.0, 6.0), 0.0, [
		{"kind": "button", "id": "dose", "legend": "DOSE", "color": "green", "momentary": false, "nc": false},
		{"kind": "light", "id": "dosing", "legend": "DOSING", "color": "green"},
	])
	var errs: Array[String] = []
	errs.append(plant.connect_equipment("mains_2", plant.free_way("mains_2"), "psu_2", "ac_in"))
	errs.append(plant.connect_equipment("psu_2", "dc_out", "mp_2", "power"))
	errs.append(plant.connect_equipment("lcs_2_dose", "contact", "sv_2", "coil"))
	for e in errs:
		if e != "":
			push_error("drip demo, wiring: " + e)
	var mp := plant.sim.get_component("mp_2") as SimMeteringPump
	if mp != null:
		mp.hand_on = true


## A line of the demo: laid by the router, then sized to tubing with
## compression fittings and painted for water.
static func _line(plant: Plant, a: String, a_port: String, b: String, b_port: String) -> void:
	var why := plant.connect_equipment(a, a_port, b, b_port)
	if why != "":
		push_error("drip demo, %s -> %s: %s" % [a, b, why])
		return
	_style_last(plant, a)


static func _style_last(plant: Plant, a: String) -> void:
	var visuals: Array = plant.get("_wire_visuals")
	if visuals.is_empty():
		return
	var visual: Dictionary = visuals[visuals.size() - 1]
	if str(visual["a"]) != a or visual["node"] == null:
		return
	var view := plant.set_run_size(visual["node"] as PipeView, TUBE_DN)
	plant.set_run_service(view, TUBE_COLOR, "", "tube")


## What the demo is doing, for the headless smoke: the drip's rate in
## drops a second, where it lands, and the dosing line's state.
static func report(plant: Plant) -> PackedStringArray:
	var out := PackedStringArray()
	var caps: Array[String] = []
	for name_: String in plant.views:
		if plant.sim.get_component(name_) is SimCap:
			caps.append(name_)
	caps.sort()
	for name_ in caps:
		var cap := plant.sim.get_component(name_) as SimCap
		if not cap.open:
			continue
		var q := cap.spill_lps()
		out.append("[flowstate] drip demo: %s open end %s (%.1f drops/s) -> %s · delivered %.3f L · spilled %.3f L" % [
			name_, SimTypes.flow_text(q), q * 1000.0 / DripStream.DROP_ML,
			cap.catch.comp_name if cap.lands() else "the ground", cap.delivered_l, cap.spilled_l])
	var pr := plant.sim.get_component("pr_2") as SimRegulator
	var nv := plant.sim.get_component("nv_2") as SimNeedleValve
	var fi := plant.sim.get_component("fi_2") as SimRotameter
	if pr != null and nv != null and fi != null:
		var net := plant.sim.network()
		out.append("[flowstate] drip demo: regulator out %.0f kPa (%.0f %% open) · needle %.1f turns · rotameter %s (%.0f %%) · solve %d iterations, residual %s" % [
			pr.out_kpa, pr.opening * 100.0, nv.turns_open, SimTypes.flow_text(fi.flow_lps), fi.float_frac * 100.0,
			net.iterations, SimTypes.flow_text(net.residual_lps)])
	var mp := plant.sim.get_component("mp_2") as SimMeteringPump
	var sv := plant.sim.get_component("sv_2") as SimSolenoidValve
	var t2 := plant.sim.get_component("t_2") as SimTank
	if mp != null and sv != null and t2 != null:
		out.append("[flowstate] drip demo: t_2 %.2f L · pump %s %s · solenoid %s" % [
			t2.level_l, mp.status(), SimTypes.flow_text(mp.flow_lps),
			"OPEN" if sv.position > 99.0 else "SHUT"])
	return out


## The demo through a save and a load: every new type, the open tank,
## the open end and its landing, the tubing and its size must come
## back as they were. Headless only; "" if it did, else what differed.
static func round_trip(plant: Plant) -> String:
	var before := _fingerprint(plant)
	var payload := plant.snapshot()
	if not plant.restore(payload):
		return "restore refused the snapshot"
	# The signals need scans to propagate and the solve a few to land
	# from its cold start, as at startup.
	for _k in 40:
		plant.sim.tick()
	var after := _fingerprint(plant)
	var problems: Array[String] = []
	for key: String in before:
		if not after.has(key):
			problems.append("%s missing after load" % key)
		elif str(before[key]) != str(after[key]):
			problems.append("%s: %s -> %s" % [key, before[key], after[key]])
	return ", ".join(problems)


static func _fingerprint(plant: Plant) -> Dictionary:
	var out := {}
	var nv := plant.sim.get_component("nv_2") as SimNeedleValve
	var pr := plant.sim.get_component("pr_2") as SimRegulator
	var ro := plant.sim.get_component("ro_2") as SimOrifice
	var bv := plant.sim.get_component("bv_2") as SimBallValve
	var fi := plant.sim.get_component("fi_2") as SimRotameter
	var mp := plant.sim.get_component("mp_2") as SimMeteringPump
	var sv := plant.sim.get_component("sv_2") as SimSolenoidValve
	var t2 := plant.sim.get_component("t_2") as SimTank
	if nv != null:
		out["needle"] = "%.4f/%.1f/%.1f" % [nv.cv_lps, nv.turns, nv.turns_open]
	if pr != null:
		out["regulator"] = "%.0f/%.2f" % [pr.set_kpa, pr.cv_lps]
	if ro != null:
		out["orifice"] = "%.5f" % ro.cv_lps
	if bv != null:
		out["ball"] = "%.2f/%s" % [bv.cv_lps, "open" if bv.open else "shut"]
	if fi != null:
		out["rotameter"] = "%.4f" % fi.range_lps
	if mp != null:
		out["metering"] = "%.4f/%.0f/%.0f/%s" % [mp.rated_lps, mp.max_head_m, mp.stroke_pct, "on" if mp.hand_on else "off"]
	if sv != null:
		out["solenoid"] = "%.2f" % sv.cv_lps
	if t2 != null:
		out["tank"] = "%s/%.1f" % ["open" if t2.open_top else "closed", t2.level_l]
	for name_: String in plant.views:
		var cap := plant.sim.get_component(name_) as SimCap
		if cap != null and cap.open:
			out["cap"] = "%s -> %s" % [name_, cap.catch.comp_name if cap.lands() else "ground"]
	var tubes := 0
	var dn6 := 0
	for visual: Dictionary in plant.get("_wire_visuals"):
		if visual["node"] == null:
			continue
		if str(visual.get("fitting", "")) == "tube":
			tubes += 1
		if int(visual.get("dn", 50)) == 6:
			dn6 += 1
	out["tubing"] = "%d tube lines, %d at DN6" % [tubes, dn6]
	return out
