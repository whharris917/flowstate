class_name UnitHmiPanel
extends Control
## An operator overview of Unit 400: a simplified P&ID with every
## reading taken live from the records it names — vessel levels,
## switch states, valve travel, pumps running and their flow, the
## sequence step from the PLC's memories — and a ten-minute trend of
## the three levels from the historian. Nothing here is inferred or
## smoothed; a line is drawn as flowing only when the record it stands
## for is passing material. Renders inside a SubViewport that an
## HmiScreenView displays in the world.
##
## The drawing helpers (vessel with switch marks, pump, block valve,
## line, header, sewer) are general; another unit's overview would be
## another layout over the same helpers.

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
const STEPS: Array[String] = ["FILL", "LIFT", "DRAIN T-401", "DRAIN T-402", "SEWER"]

var plant: Plant
var cab: String
var _step: int = -1
var _step_since: float = 0.0
var _font: Font


func setup(plant_: Plant, cab_: String) -> void:
	plant = plant_
	cab = cab_
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	var step := _current_step()
	if step != _step:
		_step = step
		_step_since = plant.sim.time
	queue_redraw()


## ---- data ------------------------------------------------------------------

func _rec(name_: String) -> SimComponent:
	return plant.sim.get_component(name_)


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


static func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
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
	if t401 == null or t403 == null or p401 == null or xv401 == null or header == null:
		_text(Vector2(size.x / 2.0, size.y / 2.0), "NO DATA", 28, COL_ALARM, HORIZONTAL_ALIGNMENT_CENTER)
		return

	# ---- header bar and the sequence ----
	draw_rect(Rect2(0, 0, size.x, 46), COL_PANEL)
	_text(Vector2(16, 31), "UNIT 400 · STAGED TRANSFER", 22, COL_INK)
	_text(Vector2(size.x - 16, 31), "t %s" % _clock(plant.sim.time), 18, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var plc_on := plant.cabinet_plc(cab) != "" and (_rec(plant.cabinet_plc(cab)) as SimPLC).power.value > 0.5
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
	var step_text := "PLC UNPOWERED" if not plc_on else (
		"no step" if _step < 0 else "in step %s" % _clock(plant.sim.time - _step_since))
	_text(Vector2(700, 77), step_text, 14, COL_ALARM if not plc_on else COL_MUTED)

	# ---- the P&ID ----
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

	# Vessels, with their switches marked at the level each trips at.
	_vessel(Rect2(300, 110, 80, 120), t401, "T-401", [
		[_rec("lsh_401"), 700.0, "LSH-401"], [_rec("lsl_401"), 200.0, "LSL-401"]])
	_vessel(Rect2(300, 292, 80, 120), t402, "T-402", [[_rec("lsl_402"), 200.0, "LSL-402"]])
	_vessel(Rect2(270, 476, 140, 100), t403, "T-403 SUMP", [
		[_rec("lsh_403"), 1000.0, "LSH-403"], [_rec("lsl_403"), 500.0, "LSL-403"]])

	# Valves, pumps, meter, header, sewer.
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

	# ---- right panel: the lists and the trend ----
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
	_trend(Rect2(x0, y + 14, x1 - x0, panel.end.y - y - 22), [t401, t402, t403], [COL_T401, COL_T402, COL_T403])


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
		var trip_l := float(entry[1])
		var y := rect.end.y - rect.size.y * clampf(trip_l / tank.capacity_l, 0.0, 1.0)
		draw_line(Vector2(rect.end.x - 6, y), Vector2(rect.end.x + 6, y), COL_INK, 1.5)
		var mark := Vector2(rect.end.x + 14, y)
		if ls.closed:
			draw_circle(mark, 5, COL_STROKE)
		else:
			draw_arc(mark, 5, 0.0, TAU, 20, COL_MUTED, 1.5)
		_text(Vector2(rect.end.x + 24, y + 4), str(entry[2]), 11, COL_INK if ls.closed else COL_MUTED)


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
func _trend(rect: Rect2, tanks: Array, colors: Array) -> void:
	var historian := plant.historian
	draw_rect(rect, COL_BG)
	if historian == null or historian.sample_count() < 2:
		return
	var times := historian.time
	var t1 := times[times.size() - 1]
	var t0 := maxf(times[0], t1 - TREND_S)
	var y_max := 1100.0
	for tick_l: int in [500, 1000]:
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
