class_name UnitHmiPanel
extends Control
## An operator screen for Unit 400 in three pages, every reading taken
## live from the records it names, nothing inferred or smoothed.
##
## OVERVIEW: a simplified P&ID — vessel levels with each switch marked
## at the level it trips at, block valves coloured by travel, pumps
## green when moving material and red when running against nothing,
## the sequence step from the PLC's memories, header and sewer totals,
## and a ten-minute trend of the three levels from the historian.
##
## HYDRAULICS: the proof that the flows and pressures are sensible.
## Both pump curves with their operating points and the static lift
## drawn across them, so P-402's dead-head is a picture; the hydraulic
## grade line along the lift path from node pressures the solver just
## produced; and each transfer checked against the valve equation.
##
## BALANCE: the proof that mass is conserved. Fed by the header, out to
## the sewer, held now against held at build, the residual, and that
## residual replayed from the historian over ten minutes.
##
## Renders inside a SubViewport that an HmiScreenView displays; E on
## the screen turns the page. The drawing helpers are general; another
## unit's screen is another layout over them.

const COL_BG := Color(0.09, 0.10, 0.11)
const COL_PANEL := Color(0.13, 0.14, 0.15)
const COL_INK := Color(0.94, 0.94, 0.92)
const COL_MUTED := Color(0.55, 0.55, 0.53)
const COL_LINE := Color(0.40, 0.42, 0.44)
const COL_FLOW := Color(0.30, 0.78, 0.95)
const COL_LEVEL := Color(0.22, 0.53, 0.90)
const COL_RUN := Color(0.20, 0.80, 0.40)
const COL_STROKE := Color(0.95, 0.70, 0.15)
const COL_ALARM := Color(0.92, 0.28, 0.22)
const COL_T401 := Color(0.95, 0.70, 0.15)
const COL_T402 := Color(0.30, 0.78, 0.95)
const COL_T403 := Color(0.22, 0.53, 0.90)
const TREND_S := 600.0
const FLOWING_LPS := 0.05
const G_PER_M := 9810.0   # Pa per metre of water
const STEPS: Array[String] = ["FILL", "LIFT", "DRAIN T-401", "DRAIN T-402", "SEWER"]
const PAGES: Array[String] = ["OVERVIEW", "HYDRAULICS", "BALANCE", "LOOP SHEET"]

var plant: Plant
var cab: String
var page: int = 0
var _step: int = -1
var _step_since: float = 0.0
var _font: Font
var _held0: float = NAN
var _since_redraw: float = 0.0


func setup(plant_: Plant, cab_: String) -> void:
	plant = plant_
	cab = cab_
	_font = ThemeDB.fallback_font


func next_page() -> void:
	page = (page + 1) % PAGES.size()
	queue_redraw()


func page_name() -> String:
	return PAGES[page]


func _process(delta: float) -> void:
	var step := _current_step()
	if step != _step:
		_step = step
		_step_since = plant.sim.time
	if is_nan(_held0):
		var names := _unit_names()
		if not names.is_empty():
			var acc := SimBalance.accounts(plant.sim, names)
			_held0 = float(acc["held"]) - (float(acc["fed"]) - float(acc["out"]))
	# Five redraws a second on every page (2026-09-13: the overview
	# replayed its trend every frame): the process is 20 Hz, the eye
	# reads a screen slower than that, and a redraw is real work.
	_since_redraw += delta
	if _since_redraw >= 0.2:
		_since_redraw = 0.0
		queue_redraw()


## ---- data ------------------------------------------------------------------

func _rec(name_: String) -> SimComponent:
	return plant.sim.get_component(name_)


func _unit_names() -> Array[String]:
	return SimBalance.names_in(plant.sim, 400)


func _current_step() -> int:
	var plc_name := plant.cabinet_plc(cab)
	if plc_name == "":
		return -1
	var plc := _rec(plc_name) as SimPLC
	if plc == null:
		return -1
	for i in STEPS.size():
		if plc.mem[i]:
			return i
	return -1


func _pressure(comp_name: String, port_name: String) -> float:
	var comp := _rec(comp_name)
	if comp == null:
		return 0.0
	var port: SimPort = comp.outputs.get(port_name)
	if port == null:
		port = comp.inputs.get(port_name)
	if port == null:
		return 0.0
	return plant.sim.pressure_at(port)


static func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if _rec("t_401") == null or _rec("p_401") == null or _rec("xv_401") == null:
		_text(Vector2(size.x / 2.0, size.y / 2.0), "NO DATA", 28, COL_ALARM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	_draw_header()
	match page:
		0:
			_draw_overview()
		1:
			_draw_hydraulics()
		2:
			_draw_balance()
		3:
			_draw_loop_sheet()


func _draw_header() -> void:
	draw_rect(Rect2(0, 0, size.x, 46), COL_PANEL)
	_text(Vector2(16, 31), "UNIT 400 · STAGED TRANSFER · %s" % PAGES[page], 22, COL_INK)
	_text(Vector2(size.x - 16, 31), "t %s" % _clock(plant.sim.time), 18, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var plc_name := plant.cabinet_plc(cab)
	var plc_on := plc_name != "" and (_rec(plc_name) as SimPLC).power.value > 0.5
	for i in STEPS.size():
		var pill := Rect2(16 + i * 136, 56, 128, 30)
		var active := i == _step
		if active:
			draw_rect(pill, COL_RUN)
		else:
			draw_rect(pill, COL_PANEL)
			draw_rect(pill, COL_LINE, false, 1.0)
		_text(pill.get_center() + Vector2(0, 6), "%d %s" % [i + 1, STEPS[i]], 14,
			COL_BG if active else COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var running := plc_on and (_rec(plc_name) as SimPLC).mem.size() > 5 and (_rec(plc_name) as SimPLC).mem[5]
	var step_text := "PLC UNPOWERED" if not plc_on else (
		"STOPPED at LCS-401 · START to resume" if not running else (
		"no step" if _step < 0 else "in step %s" % _clock(plant.sim.time - _step_since)))
	_text(Vector2(700, 77), step_text, 14, COL_ALARM if (not plc_on or not running) else COL_MUTED)
	_text(Vector2(size.x - 16, 77), "page %d/%d · E next" % [page + 1, PAGES.size()], 12, COL_MUTED,
		HORIZONTAL_ALIGNMENT_RIGHT)


# ---- page 1: overview ----------------------------------------------------

func _draw_overview() -> void:
	var t401 := _rec("t_401") as SimTank
	var t402 := _rec("t_402") as SimTank
	var t403 := _rec("t_403") as SimTank
	var p401 := _rec("p_401") as SimPump
	var p402 := _rec("p_402") as SimPump
	var k401 := _rec("k_401") as SimRelay
	var fi := _rec("fi_401") as SimGauge
	var xv401 := _rec("xv_401") as SimBlockValve
	var xv402 := _rec("xv_402") as SimBlockValve
	var xv403 := _rec("xv_403") as SimBlockValve
	var xv404 := _rec("xv_404") as SimBlockValve
	var header := _rec("supply_401") as SimSource
	var sewer := _rec("du_401") as SimDrain

	# Riser and header lines first, so symbols paint over them.
	var riser_x := 96.0
	var tee := Vector2(200, 566)
	_line([Vector2(128, 446), Vector2(riser_x, 446)], p401.flow_lps)
	_line([Vector2(128, 530), Vector2(riser_x, 530)], p402.flow_lps)
	_line([Vector2(riser_x, 530), Vector2(riser_x, 130), Vector2(300, 130)], p401.flow_lps + p402.flow_lps)
	_line([tee, Vector2(200, 446), Vector2(172, 446)], p401.flow_lps)
	_line([tee, Vector2(200, 530), Vector2(172, 530)], p402.flow_lps)
	_line([Vector2(270, 566), tee], p401.flow_lps + p402.flow_lps + xv403.flow_lps)
	_line([tee, Vector2(200, 600), Vector2(172, 600)], xv403.flow_lps)
	_line([Vector2(128, 600), Vector2(70, 600)], xv403.flow_lps)
	_line([Vector2(340, 230), Vector2(340, 292)], xv401.flow_lps)
	_line([Vector2(340, 412), Vector2(340, 476)], xv402.flow_lps)
	_line([Vector2(550, 520), Vector2(410, 520)], xv404.flow_lps)
	_dot(tee)
	_dot(Vector2(riser_x, 446))

	_vessel(Rect2(300, 110, 80, 120), t401, "T-401", [
		[_rec("lsh_401"), "LSH-401"], [_rec("lsl_401"), "LSL-401"]])
	_vessel(Rect2(300, 292, 80, 120), t402, "T-402", [[_rec("lsl_402"), "LSL-402"]])
	_vessel(Rect2(270, 476, 140, 100), t403, "T-403 SUMP", [
		[_rec("lsh_403"), "LSH-403"], [_rec("lsl_403"), "LSL-403"]])

	_valve(Vector2(340, 261), xv401, "XV-401", true)
	_valve(Vector2(340, 444), xv402, "XV-402", true)
	_valve(Vector2(150, 600), xv403, "XV-403", false)
	_valve(Vector2(480, 520), xv404, "XV-404", false)
	_pump(Vector2(150, 446), p401, "P-401")
	_pump(Vector2(150, 530), p402, "P-402")
	if fi != null:
		draw_circle(Vector2(riser_x, 300), 18, COL_PANEL)
		draw_arc(Vector2(riser_x, 300), 18, 0.0, TAU, 32, COL_INK, 1.5)
		_text(Vector2(riser_x, 305), "FI", 12, COL_INK, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(riser_x + 26, 297), "FI-401", 12, COL_MUTED)
		_text(Vector2(riser_x + 26, 313), "%.2f L/s" % fi.reading, 13, COL_INK)
	var hdr := Rect2(550, 504, 120, 32)
	draw_rect(hdr, COL_PANEL)
	draw_rect(hdr, COL_INK, false, 1.5)
	_text(Vector2(610, 517), "SUPPLY-401", 12, COL_INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(610, 531), "%.0f kPa · Σ %.0f L" % [header.pressure_kpa, header.total_l], 11, COL_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER)
	if sewer != null:
		draw_colored_polygon(PackedVector2Array([Vector2(48, 590), Vector2(92, 590), Vector2(78, 616), Vector2(62, 616)]),
			COL_PANEL)
		draw_polyline(PackedVector2Array([Vector2(48, 590), Vector2(92, 590), Vector2(78, 616), Vector2(62, 616), Vector2(48, 590)]),
			COL_INK, 1.5)
		_text(Vector2(70, 632), "SEWER Σ %.0f L" % sewer.total_l, 11, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	if k401 != null:
		_text(Vector2(150, 402), "K-401 %s · %d cycles" % ["ON" if k401.energized else "off", k401.cycles], 11,
			COL_RUN if k401.energized else COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)

	# Right panel: the lists and the trend.
	var panel := Rect2(700, 100, size.x - 716, size.y - 116)
	draw_rect(panel, COL_PANEL)
	var y := 122.0
	var x0 := panel.position.x + 12
	var x1 := panel.end.x - 12
	_text(Vector2(x0, y), "SWITCHES", 12, COL_MUTED)
	y += 18
	for row: Array in [["LSH-403", "lsh_403"], ["LSL-403", "lsl_403"], ["LSH-401", "lsh_401"],
			["LSL-401", "lsl_401"], ["LSL-402", "lsl_402"]]:
		var ls := _rec(str(row[1])) as SimFloatSwitch
		if ls == null:
			continue
		_text(Vector2(x0, y), str(row[0]), 13, COL_INK)
		_text(Vector2(x1, y), "closed" if ls.closed else "open", 13, COL_STROKE if ls.closed else COL_MUTED,
			HORIZONTAL_ALIGNMENT_RIGHT)
		y += 17
	y += 8
	_text(Vector2(x0, y), "VALVES", 12, COL_MUTED)
	y += 18
	for row: Array in [["XV-404 makeup", xv404], ["XV-401 top", xv401], ["XV-402 mid", xv402], ["XV-403 sewer", xv403]]:
		var xv := row[1] as SimBlockValve
		if xv == null:
			continue
		_text(Vector2(x0, y), str(row[0]), 13, COL_INK)
		var st := xv.state()
		var col := COL_RUN if st == "OPEN" else (COL_MUTED if st == "CLOSED" else COL_STROKE)
		_text(Vector2(x1, y), st if (st == "OPEN" or st == "CLOSED") else "%s %.0f %%" % [st, xv.position], 13, col,
			HORIZONTAL_ALIGNMENT_RIGHT)
		y += 17
	y += 8
	_text(Vector2(x0, y), "PUMPS", 12, COL_MUTED)
	y += 18
	for row: Array in [["P-401 lift", p401], ["P-402 5 m", p402]]:
		var pump := row[1] as SimPump
		if pump == null:
			continue
		_text(Vector2(x0, y), str(row[0]), 13, COL_INK)
		_text(Vector2(x1, y), _pump_state(pump), 13, COL_RUN if pump.running and pump.flow_lps > FLOWING_LPS
			else (COL_ALARM if pump.running else COL_MUTED), HORIZONTAL_ALIGNMENT_RIGHT)
		y += 17
	y += 8
	_text(Vector2(x0, y), "INVENTORY", 12, COL_MUTED)
	y += 18
	var in_rig := t401.level_l + t402.level_l + t403.level_l
	for row: Array in [["in the rig", "%.0f L" % in_rig], ["header delivered", "%.0f L" % header.total_l],
			["to sewer", "%.0f L" % (sewer.total_l if sewer != null else 0.0)]]:
		_text(Vector2(x0, y), str(row[0]), 13, COL_INK)
		_text(Vector2(x1, y), str(row[1]), 13, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 17
	_level_trend(Rect2(x0, y + 14, x1 - x0, panel.end.y - y - 22), [t401, t402, t403], [COL_T401, COL_T402, COL_T403])


# ---- page 2: hydraulics --------------------------------------------------

func _draw_hydraulics() -> void:
	var t401 := _rec("t_401") as SimTank
	var t403 := _rec("t_403") as SimTank
	var p401 := _rec("p_401") as SimPump
	var p402 := _rec("p_402") as SimPump
	# Static lift: from the sump's surface to the top tank's top nozzle.
	var static_m := (t401.elevation_m + t401.height_m) - (t403.elevation_m + t403.depth_m)
	_pump_chart(Rect2(16, 100, 484, 290), [p401, p402], ["P-401", "P-402"], [COL_RUN, COL_STROKE], static_m)
	_grade_line(Rect2(520, 100, size.x - 536, 290))
	_transfer_table(Rect2(16, 404, size.x - 32, size.y - 416))


## Both pump curves, H = H0 (1 - (Q/Qr)^2), each operating point from
## the record, and the static lift the system asks of them.
func _pump_chart(rect: Rect2, pumps: Array, tags: Array, colors: Array, static_m: float) -> void:
	draw_rect(rect, COL_PANEL)
	_text(Vector2(rect.position.x + 8, rect.position.y + 16), "PUMP CURVES · operating points from the records", 12, COL_MUTED)
	var plot := Rect2(rect.position.x + 44, rect.position.y + 28, rect.size.x - 56, rect.size.y - 52)
	var q_max := 1.0
	var h_max := static_m * 1.2
	for p_v: Variant in pumps:
		var p := p_v as SimPump
		q_max = maxf(q_max, p.rated_lps * 1.05)
		h_max = maxf(h_max, p.head_m * 1.1)
	var q_step := 5.0 if q_max > 12.0 else 1.0
	var h_step := 10.0 if h_max > 25.0 else 2.0
	var q := 0.0
	while q <= q_max:
		var x := plot.position.x + plot.size.x * q / q_max
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), COL_LINE, 1.0)
		_text(Vector2(x, plot.end.y + 14), "%.0f" % q, 10, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		q += q_step
	var h := 0.0
	while h <= h_max:
		var y := plot.end.y - plot.size.y * h / h_max
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), COL_LINE, 1.0)
		_text(Vector2(plot.position.x - 4, y + 4), "%.0f m" % h, 10, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		h += h_step
	_text(Vector2(plot.end.x, plot.end.y + 14), "L/s", 10, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	# The static lift: what the system asks before any friction.
	var ys := plot.end.y - plot.size.y * static_m / h_max
	draw_dashed_line(Vector2(plot.position.x, ys), Vector2(plot.end.x, ys), COL_INK, 1.0, 6.0)
	_text(Vector2(plot.end.x - 4, ys - 4), "static lift %.1f m" % static_m, 10, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	for k in pumps.size():
		var p := pumps[k] as SimPump
		var col := colors[k] as Color
		var curve := PackedVector2Array()
		for i in 41:
			var qq := p.rated_lps * i / 40.0
			var hh := p.head_m * (1.0 - pow(qq / p.rated_lps, 2.0))
			curve.append(Vector2(plot.position.x + plot.size.x * qq / q_max, plot.end.y - plot.size.y * hh / h_max))
		draw_polyline(curve, col, 2.0)
		var op := Vector2(plot.position.x + plot.size.x * clampf(p.flow_lps / q_max, 0.0, 1.0),
			plot.end.y - plot.size.y * clampf(p.head_pa / G_PER_M / h_max, 0.0, 1.0))
		if p.running:
			draw_circle(op, 6, col)
			draw_arc(op, 6, 0.0, TAU, 20, COL_INK, 1.5)
		else:
			draw_arc(op, 6, 0.0, TAU, 20, col, 1.5)
		var label := "%s %s · %.1f L/s at %.1f m" % [tags[k], "RUN" if p.running else "STOP", p.flow_lps, p.head_pa / G_PER_M]
		if p.running and p.flow_lps <= FLOWING_LPS:
			label += " · needs %.1f, has %.1f" % [p.head_pa / G_PER_M, p.head_m]
		_text(Vector2(plot.position.x + 6, plot.position.y + 14 + k * 15), label, 11, col)


## Piezometric head at each nozzle along the lift path, straight from
## the solver's node pressures.
func _grade_line(rect: Rect2) -> void:
	draw_rect(rect, COL_PANEL)
	_text(Vector2(rect.position.x + 8, rect.position.y + 16), "HYDRAULIC GRADE LINE · lift path, node pressures this scan", 12, COL_MUTED)
	var stations := [["t_403", "outlet", "SUMP OUT"], ["p_401", "inlet", "P-401 IN"], ["p_401", "outlet", "P-401 OUT"],
		["fi_401", "inlet", "FI IN"], ["fi_401", "outlet", "FI OUT"], ["t_401", "inlet", "T-401 IN"]]
	var plot := Rect2(rect.position.x + 44, rect.position.y + 28, rect.size.x - 56, rect.size.y - 60)
	var heads: Array[float] = []
	var h_max := 10.0
	for st: Array in stations:
		var m := _pressure(str(st[0]), str(st[1])) / G_PER_M
		heads.append(m)
		h_max = maxf(h_max, m * 1.15)
	var h_step := 10.0 if h_max > 25.0 else 2.0
	var h := 0.0
	while h <= h_max:
		var y := plot.end.y - plot.size.y * h / h_max
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), COL_LINE, 1.0)
		_text(Vector2(plot.position.x - 4, y + 4), "%.0f m" % h, 10, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		h += h_step
	var points := PackedVector2Array()
	for i in stations.size():
		var x := plot.position.x + plot.size.x * (i + 0.5) / stations.size()
		var y := plot.end.y - plot.size.y * clampf(heads[i] / h_max, -0.05, 1.0)
		points.append(Vector2(x, y))
		_text(Vector2(x, plot.end.y + 14), str(stations[i][2]), 10, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(x, y - 10), "%.0f kPa" % (heads[i] * G_PER_M / 1000.0), 10, COL_INK, HORIZONTAL_ALIGNMENT_CENTER)
	var p401 := _rec("p_401") as SimPump
	draw_polyline(points, COL_FLOW if p401.flow_lps > FLOWING_LPS else COL_LINE, 2.0)
	for p in points:
		draw_circle(p, 3.5, COL_INK)
	_text(Vector2(plot.end.x, plot.position.y + 14), "piezometric: elevation is in the number", 10, COL_MUTED,
		HORIZONTAL_ALIGNMENT_RIGHT)


## Each transfer against the valve equation: Q should equal
## Cv * (x/100) * sqrt(dP / 1 bar) with dP read across the valve.
func _transfer_table(rect: Rect2) -> void:
	draw_rect(rect, COL_PANEL)
	var x0 := rect.position.x + 12
	var cols := [x0, x0 + 190, x0 + 340, x0 + 480, x0 + 640, x0 + 800, x0 + 960]
	var y := rect.position.y + 18
	_text(Vector2(x0, y), "TRANSFERS · the valve equation, checked live", 12, COL_MUTED)
	y += 20
	var heads := ["VALVE", "TRAVEL", "dP ACROSS kPa", "Q L/s", "Cv·x·√(dP/1bar)", "Q / THAT", "LINE"]
	for i in heads.size():
		_text(Vector2(float(cols[i]), y), heads[i], 11, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
	y += 6
	draw_line(Vector2(x0, y), Vector2(rect.end.x - 12, y), COL_LINE, 1.0)
	y += 18
	for row: Array in [["XV-404", "xv_404", "header to sump"], ["XV-401", "xv_401", "T-401 to T-402"],
			["XV-402", "xv_402", "T-402 to sump"], ["XV-403", "xv_403", "sump to sewer"]]:
		var xv := _rec(str(row[1])) as SimBlockValve
		if xv == null:
			continue
		var dp := (plant.sim.pressure_at(xv.inlet) - plant.sim.pressure_at(xv.outlet))
		var q := xv.flow_lps
		var expected := xv.cv_lps * (xv.position / 100.0) * sqrt(maxf(dp, 0.0) / 100000.0)
		_text(Vector2(float(cols[0]), y), "%s (Cv %.0f)" % [row[0], xv.cv_lps], 13, COL_INK)
		var st := xv.state()
		_text(Vector2(float(cols[1]), y), "%.0f %% %s" % [xv.position, st.to_lower()], 13,
			COL_RUN if st == "OPEN" else (COL_MUTED if st == "CLOSED" else COL_STROKE), HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(float(cols[2]), y), "%.1f" % (dp / 1000.0), 13, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(float(cols[3]), y), "%.2f" % q, 13, COL_FLOW if q > FLOWING_LPS else COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(float(cols[4]), y), "%.2f" % expected, 13, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
		var ratio_text := "—"
		var ratio_col := COL_MUTED
		if expected > 0.02 and q > FLOWING_LPS:
			var ratio := q / expected
			ratio_text = "%.3f" % ratio
			ratio_col = COL_RUN if absf(ratio - 1.0) < 0.02 else COL_STROKE
		elif st == "CLOSED":
			ratio_text = "shut, holds %.1f kPa" % (dp / 1000.0)
		_text(Vector2(float(cols[5]), y), ratio_text, 13, ratio_col, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(float(cols[6]), y), str(row[2]), 12, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 20
	y += 6
	_text(Vector2(x0, y), "A ratio of 1.000 is the valve equation holding to the solver's tolerance; dP is read across the valve's own two nozzles.", 11, COL_MUTED)


# ---- page 3: balance -----------------------------------------------------

func _draw_balance() -> void:
	var names := _unit_names()
	var acc := SimBalance.accounts(plant.sim, names)
	var h0 := 0.0 if is_nan(_held0) else _held0
	var res := SimBalance.residual(acc, h0)
	var fed := float(acc["fed"])
	var out := float(acc["out"])
	var held := float(acc["held"])
	# Four tiles.
	var tiles := [
		["FED BY HEADER", "%.1f L" % fed, "supply_401 total", COL_INK],
		["OUT TO SEWER", "%.1f L" % out, "du_401 total", COL_INK],
		["HELD IN VESSELS", "%.1f L" % held, "was %.1f L at build" % h0, COL_INK],
		["RESIDUAL", "%+.2f L" % res, "fed - out - (held - built) · %.2f %% closed" % SimBalance.closure_pct(acc, h0),
			COL_RUN if absf(res) <= maxf(1.0, 0.005 * fed) else COL_ALARM],
	]
	for i in tiles.size():
		var tile := Rect2(16 + (i % 2) * 246, 100 + int(i / 2.0) * 118, 236, 106)
		draw_rect(tile, COL_PANEL)
		_text(tile.position + Vector2(12, 22), str(tiles[i][0]), 12, COL_MUTED)
		_text(tile.position + Vector2(12, 62), str(tiles[i][1]), 30, tiles[i][3] as Color)
		_text(tile.position + Vector2(12, 90), str(tiles[i][2]), 11, COL_MUTED)
	# The bar: fed on top, out + change in held below it; equal lengths close.
	var bar := Rect2(16, 348, 482, 70)
	draw_rect(bar, COL_PANEL)
	var scale := bar.size.x - 24
	var denom := maxf(maxf(fed, out + maxf(held - h0, 0.0)), 1.0)
	_text(Vector2(28, 366), "fed", 11, COL_MUTED)
	draw_rect(Rect2(28, 370, scale * fed / denom, 12), COL_FLOW)
	_text(Vector2(28, 398), "out + change in held", 11, COL_MUTED)
	draw_rect(Rect2(28, 402, scale * out / denom, 12), COL_STROKE)
	draw_rect(Rect2(28 + scale * out / denom, 402, scale * maxf(held - h0, 0.0) / denom, 12), COL_LEVEL)
	_text(Vector2(16, 440), "Every number is a record's own meter: the header's total, the sewer's total, the three levels. Nothing here integrates a flow.", 11, COL_MUTED)
	_text(Vector2(16, 458), "The residual is what a closed balance keeps at zero, scan after scan, through two pumps, four valves, two tees and three vessels.", 11, COL_MUTED)
	# The residual over ten minutes, from the historian.
	_residual_trend(Rect2(520, 100, size.x - 536, 360), names, h0)


func _residual_trend(rect: Rect2, names: Array, h0: float) -> void:
	draw_rect(rect, COL_PANEL)
	_text(Vector2(rect.position.x + 8, rect.position.y + 16), "RESIDUAL, LAST 10 MIN · replayed from historian samples", 12, COL_MUTED)
	var historian := plant.historian
	if historian == null or historian.sample_count() < 2:
		return
	var plot := Rect2(rect.position.x + 50, rect.position.y + 30, rect.size.x - 60, rect.size.y - 46)
	var times := historian.time
	var t1 := times[times.size() - 1]
	var t0 := maxf(times[0], t1 - TREND_S)
	var count := 0
	var i := times.size() - 1
	while i > 0 and times[i - 1] >= t0:
		i -= 1
		count += 1
	var stride := maxi(1, ceili(count / (plot.size.x * 0.5)))
	var points := SimBalance.residual_points(historian, SimBalance.tags(plant.sim, names), h0, t0, stride)
	var span := 2.0
	for p in points:
		span = maxf(span, absf(p.y) * 1.2)
	var mid := plot.position.y + plot.size.y / 2.0
	for frac: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var yy := mid - frac * plot.size.y / 2.0
		draw_line(Vector2(plot.position.x, yy), Vector2(plot.end.x, yy), COL_INK if frac == 0.0 else COL_LINE, 1.0)
		_text(Vector2(plot.position.x - 6, yy + 4), "%+.1f L" % (frac * span), 10, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var packed := PackedVector2Array()
	for p in points:
		packed.append(Vector2(plot.position.x + plot.size.x * (p.x - t0) / (t1 - t0 + 0.001),
			mid - clampf(p.y / span, -1.0, 1.0) * plot.size.y / 2.0))
	if packed.size() >= 2:
		draw_polyline(packed, COL_FLOW, 2.0)


# ---- page 4: loop sheet ---------------------------------------------------
## Every PLC channel traced through the real wiring: cabinet terminal,
## multicore, junction box terminal, field device, with the live state
## at both ends. Nothing is drawn from a drawing; it is the kernel's
## wire list, walked.

func _draw_loop_sheet() -> void:
	var plc_name := plant.cabinet_plc(cab)
	if plc_name == "":
		_text(Vector2(size.x / 2.0, size.y / 2.0), "NO PLC IN %s" % cab.to_upper(), 24, COL_ALARM, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var plc := _rec(plc_name) as SimPLC
	var x0 := 16.0
	var cols := [x0, x0 + 90, x0 + 300, x0 + 470, x0 + 590, x0 + 760, x0 + 900]
	var y := 112.0
	_text(Vector2(x0, y), "%s · every channel with a wire, traced through the terminals it lands on" % cab.to_upper(), 12, COL_MUTED)
	y += 20
	var heads := ["PLC", "FIELD DEVICE", "JB TERMINAL", "CABLE", "CABINET TB", "PLC", "STATE"]
	for i in heads.size():
		_text(Vector2(float(cols[i]), y), heads[i], 11, COL_MUTED)
	y += 6
	draw_line(Vector2(x0, y), Vector2(size.x - 16, y), COL_LINE, 1.0)
	y += 18
	var rows: Array = []
	for i in plc.n_di:
		var chain := _trace(plc_name, "di_%d" % i, true)
		if not chain.is_empty():
			rows.append(["di_%d" % i, chain, plc.di_ports[i].value > 0.5])
	for i in plc.n_do:
		var chain := _trace(plc_name, "do_%d" % i, false)
		if not chain.is_empty():
			rows.append(["do_%d" % i, chain, plc.do_ports[i].value > 0.5])
	for row: Array in rows:
		if y > size.y - 30:
			_text(Vector2(x0, y), "…", 12, COL_MUTED)
			break
		var chain := row[1] as Dictionary
		var live := bool(row[2])
		_text(Vector2(float(cols[0]), y), str(row[0]), 12, COL_INK)
		_text(Vector2(float(cols[1]), y), str(chain.get("device", "—")), 12, COL_INK)
		_text(Vector2(float(cols[2]), y), str(chain.get("jb", "—")), 12, COL_MUTED)
		_text(Vector2(float(cols[3]), y), str(chain.get("cable", "direct")), 12, COL_MUTED)
		_text(Vector2(float(cols[4]), y), str(chain.get("tb", "—")), 12, COL_MUTED)
		_text(Vector2(float(cols[5]), y), str(row[0]), 12, COL_MUTED)
		draw_circle(Vector2(float(cols[6]) + 6, y - 4), 5, COL_RUN if live else COL_PANEL)
		draw_arc(Vector2(float(cols[6]) + 6, y - 4), 5, 0.0, TAU, 16, COL_INK, 1.0)
		_text(Vector2(float(cols[6]) + 18, y), "ON" if live else "off", 12, COL_RUN if live else COL_MUTED)
		y += 18
	if rows.is_empty():
		_text(Vector2(x0, y), "no channel has a wire", 12, COL_MUTED)
	y += 10
	_text(Vector2(x0, size.y - 14), "A row is a circuit: the PLC channel, the terminals it passes, the cable that carries it, and the device at the far end. Each terminal costs a scan.",
		11, COL_MUTED)


## Walk a channel's circuit through terminal records to whatever is at
## the far end. Inputs are walked upstream from the PLC, outputs down.
func _trace(plc_name: String, port_name: String, upstream: bool) -> Dictionary:
	var out := {}
	var record := plc_name
	var port := port_name
	var hops := 0
	while hops < 12:
		hops += 1
		var wire := _wire_at(record, port, upstream)
		if wire.is_empty():
			return out if out.has("device") else {}
		var next_record := str(wire["a"] if upstream else wire["b"])
		var next_port := str(wire["a_port"] if upstream else wire["b_port"])
		var cable := _cable_of(wire)
		if cable != "":
			out["cable"] = cable
		var comp := _rec(next_record)
		if comp is SimTerminal:
			var owner := str(plant.member_of.get(next_record, ""))
			var short := next_record.trim_prefix(owner + "_").to_upper()
			if plant.junction_boxes.has(owner):
				out["jb"] = "%s %s" % [owner.to_upper().replace("_", "-"), short]
			else:
				out["tb"] = short
			record = next_record
			port = "in" if upstream else "out"
			continue
		out["device"] = "%s.%s" % [next_record, next_port]
		return out
	return out


func _wire_at(record: String, port: String, upstream: bool) -> Dictionary:
	for visual: Dictionary in plant._wire_visuals:
		if upstream and str(visual["b"]) == record and str(visual["b_port"]) == port:
			return visual
		if not upstream and str(visual["a"]) == record and str(visual["a_port"]) == port:
			return visual
	return {}


func _cable_of(wire: Dictionary) -> String:
	for run_name: String in plant.runs:
		var entry: Dictionary = plant.runs[run_name]
		for pair: Array in entry.get("circuits", []):
			if str(pair[0]) == str(wire["a"]) and str(pair[1]) == str(wire["a_port"]) \
					and str(pair[2]) == str(wire["b"]) and str(pair[3]) == str(wire["b_port"]):
				return run_name
	return ""


# ---- helpers ---------------------------------------------------------------

func _pump_state(pump: SimPump) -> String:
	if not pump.running:
		return "STOP"
	if pump.cavitating:
		return "CAVITATING"
	if pump.flow_lps <= FLOWING_LPS:
		return "DEAD-HEADED"
	return "RUN %.2f L/s" % pump.flow_lps


func _text(pos: Vector2, text: String, size_px: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := -1.0
	var at := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		width = 400.0
		at.x -= 200.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		width = 400.0
		at.x -= 400.0
	draw_string(_font, at, text, align, width, size_px, color)


## A process line, bright and thick while its record is passing material.
func _line(points: Array, flow_lps: float) -> void:
	var packed := PackedVector2Array()
	for p: Vector2 in points:
		packed.append(p)
	var flowing := flow_lps > FLOWING_LPS
	draw_polyline(packed, COL_FLOW if flowing else COL_LINE, 3.0 if flowing else 2.0)


func _dot(at: Vector2) -> void:
	draw_circle(at, 3.5, COL_LINE)


## A vessel: outline, a level fill from the bottom, the reading, and a
## mark at each switch's trip level, filled while that contact is closed.
func _vessel(rect: Rect2, tank: SimTank, tag: String, switches: Array) -> void:
	var frac := clampf(tank.level_l / tank.capacity_l, 0.0, 1.0)
	draw_rect(rect, COL_PANEL)
	draw_rect(Rect2(rect.position.x, rect.end.y - rect.size.y * frac, rect.size.x, rect.size.y * frac), COL_LEVEL)
	draw_rect(rect, COL_INK, false, 1.5)
	_text(Vector2(rect.get_center().x, rect.position.y - 6), tag, 13, COL_INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(rect.get_center().x, rect.get_center().y + 1), "%.0f L" % tank.level_l, 16, COL_INK,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(rect.get_center().x, rect.get_center().y + 17), "%.0f %% · %.2f m" % [frac * 100.0, tank.depth_m], 11,
		COL_INK, HORIZONTAL_ALIGNMENT_CENTER)
	for entry: Array in switches:
		var ls := entry[0] as SimFloatSwitch
		if ls == null:
			continue
		# A single-point switch trips at its one level; a two-point one
		# is drawn at its low point.
		var trip_l := ls.low_l
		var y := rect.end.y - rect.size.y * clampf(trip_l / tank.capacity_l, 0.0, 1.0)
		draw_line(Vector2(rect.end.x - 6, y), Vector2(rect.end.x + 6, y), COL_INK, 1.5)
		var mark := Vector2(rect.end.x + 14, y)
		if ls.closed:
			draw_circle(mark, 5, COL_STROKE)
		else:
			draw_arc(mark, 5, 0.0, TAU, 20, COL_MUTED, 1.5)
		_text(Vector2(rect.end.x + 24, y + 4), str(entry[1]), 11, COL_INK if ls.closed else COL_MUTED)


## A block valve as a bowtie: green when open, outline when shut, amber
## while it travels.
func _valve(center: Vector2, xv: SimBlockValve, tag: String, vertical: bool) -> void:
	var st := xv.state()
	var fill := COL_RUN if st == "OPEN" else (COL_PANEL if st == "CLOSED" else COL_STROKE)
	var a := 12.0
	var b := 8.0
	var tri1: PackedVector2Array
	var tri2: PackedVector2Array
	if vertical:
		tri1 = PackedVector2Array([center + Vector2(-b, -a), center + Vector2(b, -a), center])
		tri2 = PackedVector2Array([center + Vector2(-b, a), center + Vector2(b, a), center])
	else:
		tri1 = PackedVector2Array([center + Vector2(-a, -b), center + Vector2(-a, b), center])
		tri2 = PackedVector2Array([center + Vector2(a, -b), center + Vector2(a, b), center])
	for tri: PackedVector2Array in [tri1, tri2]:
		draw_colored_polygon(tri, fill)
		var outline := PackedVector2Array(tri)
		outline.append(tri[0])
		draw_polyline(outline, COL_INK, 1.5)
	var label := "%s %s" % [tag, st] if (st == "OPEN" or st == "CLOSED") else "%s %s %.0f %%" % [tag, st, xv.position]
	if vertical:
		_text(center + Vector2(18, 4), label, 11, COL_INK)
	else:
		_text(center + Vector2(0, -14), label, 11, COL_INK, HORIZONTAL_ALIGNMENT_CENTER)


## A pump as a circle with an impeller triangle, green while it moves
## material, red while it runs and moves nothing.
func _pump(center: Vector2, pump: SimPump, tag: String) -> void:
	var moving := pump.running and pump.flow_lps > FLOWING_LPS
	var fill := COL_RUN if moving else (COL_ALARM if pump.running else COL_PANEL)
	draw_circle(center, 22, fill)
	draw_arc(center, 22, 0.0, TAU, 40, COL_INK, 1.5)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-8, -10), center + Vector2(-8, 10), center + Vector2(10, 0)]),
		COL_BG if moving or pump.running else COL_INK)
	_text(Vector2(center.x, center.y - 30), tag, 12, COL_INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(center.x, center.y + 38), _pump_state(pump), 11,
		COL_RUN if moving else (COL_ALARM if pump.running else COL_MUTED), HORIZONTAL_ALIGNMENT_CENTER)


## The three levels over the last ten minutes, from the historian.
func _level_trend(rect: Rect2, tanks: Array, colors: Array) -> void:
	var historian := plant.historian
	draw_rect(rect, COL_BG)
	if historian == null or historian.sample_count() < 2:
		return
	var times := historian.time
	var t1 := times[times.size() - 1]
	var t0 := maxf(times[0], t1 - TREND_S)
	# The axis reaches a little past the highest trip level on the unit.
	var top_trip := 0.0
	for switch_name: String in ["lsh_403", "lsh_401", "lsl_402"]:
		var ls := _rec(switch_name) as SimFloatSwitch
		if ls != null:
			top_trip = maxf(top_trip, ls.high_l)
	var y_max := maxf(100.0, ceilf(top_trip * 1.15 / 100.0) * 100.0)
	var tick_step := 100 if y_max <= 800.0 else 500
	for tick_l: int in range(tick_step, int(y_max), tick_step):
		var y := rect.end.y - rect.size.y * tick_l / y_max
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COL_LINE, 1.0)
		_text(Vector2(rect.position.x + 2, y - 2), "%d L" % tick_l, 9, COL_MUTED)
	var start := times.size() - 1
	while start > 0 and times[start - 1] >= t0:
		start -= 1
	var count := times.size() - start
	var stride := maxi(1, ceili(count / (rect.size.x * 2.0)))
	for k in tanks.size():
		var tank := tanks[k] as SimTank
		var tag := tank.level.path()
		var series := historian.series(tag)
		var offset := historian.start_index(tag)
		var points := PackedVector2Array()
		var i := maxi(start, offset)
		while i < times.size():
			var local := i - offset
			if local >= series.size():
				break
			points.append(Vector2(
				rect.position.x + rect.size.x * (times[i] - t0) / (t1 - t0 + 0.001),
				rect.end.y - rect.size.y * clampf(series[local] / y_max, 0.0, 1.0)))
			i += stride
		if points.size() >= 2:
			draw_polyline(points, colors[k] as Color, 1.5)
		_text(Vector2(rect.end.x - 4 - (tanks.size() - 1 - k) * 46, rect.position.y - 4), tank.comp_name.to_upper().replace("_", "-"),
			10, colors[k] as Color, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(rect.position.x + 2, rect.position.y - 4), "LEVELS · last 10 min", 10, COL_MUTED)
