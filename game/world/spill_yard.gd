class_name SpillYard
## The spill yard on the Maine site: overflowing, spilling, gushing
## nozzles, puddles and splashes.
## Every piece is a real record and every stream the flow the network
## solved; the tanks are charged near their working levels so the yard
## is running within seconds of arrival, as the showcase's Unit 300 is.
##
##   A  the hose: a DN50 line from a 400 kPa header ending 3 m up,
##      gushing east onto the ground.
##   B  over and in: two jets at one open tank from the same height, a
##      gentle DN15 from the west that falls into it and a hard DN40 from
##      the north that carries clean over it -- the catch follows each
##      stream's own arc, so the first counts as delivered and the second
##      as spilled.
##   C  the cascade: that tank drains by gravity through a spout over a
##      small open tank, which brims over onto the ground.
##   D  a closed tank fed past full, running over down its shell.
##   E  the bores: four open ends side by side on one pressure, DN2 to
##      DN25 -- drops, a thread, a stream, a gush.

const Z := 36.0
const WATER := Color(0.13, 0.55, 0.28)   # ASME: water


static func build(plant: Plant) -> void:
	var water := SimStream.pure(SimSpecies.WATER, 1.0).comp
	# A: the hose.
	_header(plant, "hs_hose", 400.0, Vector3(-8.0, 0.0, Z - 8.0))
	_open(plant, "hs_hose", 50, [Vector3(-6.0, 3.0, Z - 8.0), Vector3(-4.5, 3.0, Z - 8.0)])
	# B: the open tank, and the two jets at it from 2.4 m.
	var tk_a := plant.place("tank", "tk_yard_a", {"height_m": 1.6, "diameter_m": 1.2, "open_top": true},
		Vector3(6.0, 0.0, Z), 0.0, false) as SimTank
	if tk_a != null:
		tk_a.charge(tk_a.capacity_l * 0.9, water, SimStream.AMBIENT_C)
	_header(plant, "hs_gentle", 40.0, Vector3(0.0, 0.0, Z))
	_open(plant, "hs_gentle", 15, [Vector3(4.4, 2.4, Z), Vector3(4.9, 2.4, Z)])
	_header(plant, "hs_hard", 400.0, Vector3(3.0, 0.0, Z - 5.0))
	_open(plant, "hs_hard", 40, [Vector3(6.0, 2.4, Z - 4.0), Vector3(6.0, 2.4, Z - 2.5)])
	# C: the cascade, out of the open tank's bottom nozzle to a spout.
	var tk_b := plant.place("tank", "tk_yard_b", {"height_m": 0.5, "diameter_m": 0.8, "open_top": true},
		Vector3(8.7, 0.0, Z), 0.0, false) as SimTank
	if tk_b != null:
		tk_b.charge(tk_b.capacity_l - 3.0, water, SimStream.AMBIENT_C)
	plant.next_line_size(40)
	var why := plant.connect_open("tk_yard_a", "outlet", [Vector3(7.6, 0.9, Z), Vector3(8.1, 0.9, Z)])
	if why != "":
		push_error("spill yard, spout: " + why)
	else:
		_paint(plant, "tk_yard_a")
	# D: the closed tank fed past full.
	var tk_c := plant.place("tank", "tk_yard_c", {"height_m": 1.8, "diameter_m": 0.9},
		Vector3(14.0, 0.0, Z), 0.0, false) as SimTank
	if tk_c != null:
		tk_c.charge(tk_c.capacity_l - 3.0, water, SimStream.AMBIENT_C)
	_header(plant, "hs_fill", 300.0, Vector3(11.0, 0.0, Z + 4.0))
	plant.next_line_size(25)
	why = plant.connect_equipment("hs_fill", "outlet", "tk_yard_c", "inlet")
	if why != "":
		push_error("spill yard, fill: " + why)
	else:
		_paint(plant, "hs_fill")
	# E: the bores, thrown north over open ground.
	var x := -6.0
	for dn: int in [2, 6, 15, 25]:
		var header := "hs_bore_%d" % dn
		_header(plant, header, 400.0, Vector3(x, 0.0, Z + 8.0))
		_open(plant, header, dn, [Vector3(x + 1.5, 1.3, Z + 8.0), Vector3(x + 1.5, 1.3, Z + 9.0)])
		x += 4.0


static func _header(plant: Plant, name_: String, kpa: float, at: Vector3) -> void:
	plant.place("source", name_, {"pressure_kpa": kpa}, at, 0.0, false)


static func _open(plant: Plant, header: String, dn: int, waypoints: Array) -> void:
	plant.next_line_size(dn)
	var why := plant.connect_open(header, "outlet", waypoints)
	if why != "":
		push_error("spill yard, %s: %s" % [header, why])
		return
	_paint(plant, header)


static func _paint(plant: Plant, a: String) -> void:
	var visuals: Array = plant.get("_wire_visuals")
	for i in range(visuals.size() - 1, -1, -1):
		var visual: Dictionary = visuals[i]
		if str(visual["a"]) == a and visual["node"] is PipeView:
			var dn := int(visual.get("dn", 50))
			plant.set_run_service(visual["node"] as PipeView, WATER, "", "tube" if dn <= 6 else "flange")
			return


## What the yard is doing, for the headless smoke: each open end's flow,
## exit speed and where it lands, and each tank's level and overflow.
static func report(plant: Plant) -> PackedStringArray:
	var out := PackedStringArray()
	var names: Array[String] = []
	for name_: String in plant.views:
		names.append(name_)
	names.sort()
	for name_ in names:
		var cap := plant.sim.get_component(name_) as SimCap
		if cap == null or not cap.open:
			continue
		var view := plant.views[name_] as CapView
		var src := _source_of(plant, name_)
		if not (src.begins_with("hs_") or src.begins_with("tk_yard")):
			continue
		var q := cap.spill_lps()
		out.append("[flowstate] spill yard: %s from %s DN%d · %s at %.1f m/s · %s · delivered %.1f L, spilled %.1f L" % [
			name_, src, roundi(view.bore_diameter_m() * 1000.0), SimTypes.flow_text(q),
			SpillJet.exit_speed(q, view.bore_diameter_m()),
			"into " + cap.catch.comp_name if cap.lands() else "to the ground", cap.delivered_l, cap.spilled_l])
	for name_: String in ["tk_yard_a", "tk_yard_b", "tk_yard_c"]:
		var tank := plant.sim.get_component(name_) as SimTank
		if tank != null:
			out.append("[flowstate] spill yard: %s %.0f of %.0f L · overflowed %.1f L" % [
				name_, tank.level_l, tank.capacity_l, tank.overflowed_l])
	return out


static func _source_of(plant: Plant, cap_name: String) -> String:
	for visual: Dictionary in plant.get("_wire_visuals"):
		if str(visual["b"]) == cap_name:
			return str(visual["a"])
	return ""
