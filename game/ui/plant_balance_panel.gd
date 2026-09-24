class_name PlantBalancePanel
extends Control
## The plant's material balance by unit, live, from the records' own
## meters through SimBalance: what each unit was fed across the plant
## boundary, what it sent out, what it holds against what it held when
## it was built, and the residual a closed balance keeps at zero. A
## ten-minute trend of the whole plant's residual from the historian
## sits underneath, which is the proof: a flat line at zero is mass
## conserved through every pump, valve, tee and vessel between the
## meters. Renders inside a SubViewport that an HmiScreenView shows.

const COL_BG := Color(0.09, 0.10, 0.11)
const COL_PANEL := Color(0.13, 0.14, 0.15)
const COL_INK := Color(0.94, 0.94, 0.92)
const COL_MUTED := Color(0.55, 0.55, 0.53)
const COL_LINE := Color(0.40, 0.42, 0.44)
const COL_OK := Color(0.20, 0.80, 0.40)
const COL_WARN := Color(0.95, 0.70, 0.15)
const COL_BAD := Color(0.92, 0.28, 0.22)
const COL_SERIES := Color(0.30, 0.78, 0.95)
const TREND_S := 600.0
const REDRAW_S := 1.0  # a ten-minute trend and a residual: once a second is plenty

var plant: Plant
var _held0: Dictionary = {}   # unit -> held when first seen, corrected for the scans before
var _font: Font
var _since_redraw: float = 0.0


func setup(plant_: Plant) -> void:
	plant = plant_
	_font = ThemeDB.fallback_font


## Held at build, per unit. A unit first seen a few scans after it was
## built has already moved a little material between its own meters,
## so its baseline is corrected by what it fed and sent out by then.
func held0(unit: int) -> float:
	_see_units()
	return float(_held0.get(unit, 0.0))


func _see_units() -> void:
	if plant == null:
		return
	for unit in SimBalance.units(plant.sim):
		if not _held0.has(unit):
			var acc := SimBalance.accounts(plant.sim, SimBalance.names_in(plant.sim, unit))
			_held0[unit] = float(acc["held"]) - (float(acc["fed"]) - float(acc["out"]))


func _process(delta: float) -> void:
	_see_units()
	_since_redraw += delta
	if _since_redraw >= REDRAW_S:
		_since_redraw = 0.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if plant == null:
		return
	draw_rect(Rect2(0, 0, size.x, 46), COL_PANEL)
	_text(Vector2(16, 31), "MATERIAL BALANCE · BY UNIT", 22, COL_INK)
	_text(Vector2(size.x - 16, 31), "t %s" % _clock(plant.sim.time), 18, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)

	# The table: one row per unit, then the plant.
	var cols := [16.0, 190.0, 330.0, 470.0, 610.0, 760.0, 900.0]
	var heads := ["UNIT", "FED L", "OUT L", "HELD L", "HELD AT BUILD", "RESIDUAL L", "CLOSED"]
	var y := 78.0
	for i in heads.size():
		_text(Vector2(cols[i], y), heads[i], 12, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
	y += 8
	draw_line(Vector2(16, y), Vector2(size.x - 16, y), COL_LINE, 1.0)
	y += 22
	var total := {"fed": 0.0, "out": 0.0, "held": 0.0}
	var total_h0 := 0.0
	var all_names: Array = []
	for unit in SimBalance.units(plant.sim):
		var names := SimBalance.names_in(plant.sim, unit)
		all_names.append_array(names)
		var acc := SimBalance.accounts(plant.sim, names)
		var h0 := held0(unit)
		_row(y, cols, SimBalance.unit_label(unit), acc, h0)
		for k: String in ["fed", "out", "held"]:
			total[k] = float(total[k]) + float(acc[k])
		total_h0 += h0
		y += 22
	y += 4
	draw_line(Vector2(16, y), Vector2(size.x - 16, y), COL_LINE, 1.0)
	y += 22
	_row(y, cols, "PLANT", total, total_h0, true)
	y += 30
	_text(Vector2(16, y), "Fed: headers, the lock's condensate, the steam drum's makeup. Out: drains, vials, dryer vapour, boil-off, overflow. Held: vessel inventories. Every number is a record's own meter.",
		11, COL_MUTED)

	# The proof: the plant residual over the last ten minutes.
	var rect := Rect2(16, y + 24, size.x - 32, size.y - y - 40)
	_trend(rect, all_names, total_h0)


func _row(y: float, cols: Array, label: String, acc: Dictionary, h0: float, bold: bool = false) -> void:
	var res := SimBalance.residual(acc, h0)
	var fed := float(acc["fed"])
	var tol := maxf(1.0, 0.005 * fed)
	var col := COL_OK if absf(res) <= tol else (COL_WARN if absf(res) <= 5.0 * tol else COL_BAD)
	var sz := 15 if bold else 13
	_text(Vector2(float(cols[0]), y), label, sz, COL_INK)
	_text(Vector2(float(cols[1]), y), "%.1f" % fed, sz, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(float(cols[2]), y), "%.1f" % float(acc["out"]), sz, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(float(cols[3]), y), "%.1f" % float(acc["held"]), sz, COL_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(float(cols[4]), y), "%.1f" % h0, sz, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(float(cols[5]), y), "%+.2f" % res, sz, col, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(float(cols[6]), y), "%.2f %%" % SimBalance.closure_pct(acc, h0) if fed > 1e-6 else "idle", sz, col,
		HORIZONTAL_ALIGNMENT_RIGHT)


func _trend(rect: Rect2, names: Array, held0_total: float) -> void:
	draw_rect(rect, COL_PANEL)
	_text(Vector2(rect.position.x + 8, rect.position.y + 16), "PLANT RESIDUAL, LAST 10 MIN · fed - out - (held - held at build)", 12, COL_MUTED)
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
	var tagset := SimBalance.tags(plant.sim, names)
	var points := SimBalance.residual_points(historian, tagset, held0_total, t0, stride)
	var span := 2.0
	for p in points:
		span = maxf(span, absf(p.y) * 1.2)
	var mid := plot.position.y + plot.size.y / 2.0
	for frac: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var yy := mid - frac * plot.size.y / 2.0
		draw_line(Vector2(plot.position.x, yy), Vector2(plot.end.x, yy), COL_LINE if frac != 0.0 else COL_INK, 1.0)
		_text(Vector2(plot.position.x - 6, yy + 4), "%+.1f L" % (frac * span), 10, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var packed := PackedVector2Array()
	for p in points:
		packed.append(Vector2(
			plot.position.x + plot.size.x * (p.x - t0) / (t1 - t0 + 0.001),
			mid - clampf(p.y / span, -1.0, 1.0) * plot.size.y / 2.0))
	if packed.size() >= 2:
		draw_polyline(packed, COL_SERIES, 2.0)
	if points.size() > 0:
		var last := points[points.size() - 1]
		_text(Vector2(plot.end.x, plot.position.y - 4), "now %+.2f L" % last.y, 12,
			COL_OK if absf(last.y) <= 1.0 else COL_WARN, HORIZONTAL_ALIGNMENT_RIGHT)


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


static func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]
