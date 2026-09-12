class_name TrendScreenPanel
extends Control
## The face of a placeable trend screen: up to four historian tags
## over the record's window, each pen scaled to its own range, the
## live value and the range in the legend. Everything drawn here is
## replayed from historian samples, so the screen shows exactly what a
## plant historian would — nothing smoothed, nothing invented. (The
## home loop's fixed HMI page is TrendPanel; this one is configurable.)

const COL_BG := Color(0.09, 0.10, 0.11)
const COL_INK := Color(0.94, 0.94, 0.92)
const COL_MUTED := Color(0.55, 0.55, 0.53)
const COL_LINE := Color(0.28, 0.30, 0.32)
const PENS: Array[Color] = [Color(0.95, 0.70, 0.15), Color(0.30, 0.78, 0.95),
	Color(0.20, 0.80, 0.40), Color(0.92, 0.45, 0.75)]

var record: SimTrendScreen
var plant: Plant
var _font: Font
var _since := 0.0


func setup(record_: SimTrendScreen, plant_: Plant) -> void:
	record = record_
	plant = plant_
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_since += delta
	if _since >= 0.25:
		_since = 0.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var window := record.window_s if record != null else 600.0
	_text(Vector2(16, 30), "%s   TREND · last %s" % [
		record.comp_name.to_upper().replace("_", "-") if record != null else "TREND",
		("%d min" % int(window / 60.0)) if window >= 120.0 else ("%d s" % int(window))],
		18, COL_INK)
	var rect := Rect2(Vector2(60, 50), Vector2(size.x - 80, size.y - 150))
	draw_rect(rect, Color(0.11, 0.12, 0.13))
	for k in range(1, 5):
		var y := rect.position.y + rect.size.y * k / 5.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COL_LINE, 1.0)
	for k in range(0, 6):
		var x := rect.position.x + rect.size.x * k / 5.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), COL_LINE, 1.0)
		var back := window * (5 - k) / 5.0
		_text(Vector2(x, rect.end.y + 16), "now" if k == 5 else
			("-%d min" % int(roundf(back / 60.0)) if window >= 120.0 else "-%d s" % int(back)),
			10, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var historian: SimHistorian = plant.historian if plant != null else null
	if record == null or historian == null or historian.sample_count() < 2:
		_text(Vector2(rect.position.x + 12, rect.position.y + 24), "no historian samples yet", 12, COL_MUTED)
		return
	var times := historian.time
	var t1 := times[times.size() - 1]
	var t0 := maxf(times[0], t1 - window)
	var start := times.size() - 1
	while start > 0 and times[start - 1] >= t0:
		start -= 1
	var count := times.size() - start
	var stride := maxi(1, ceili(count / (rect.size.x * 2.0)))
	var legend_y := rect.end.y + 44
	for k in SimTrendScreen.MAX_PENS:
		var tag := record.tags[k]
		var color := PENS[k]
		var lx := 20.0 + k * (size.x - 40.0) / SimTrendScreen.MAX_PENS
		if tag == "":
			_text(Vector2(lx, legend_y), "pen %d — none" % (k + 1), 11, COL_MUTED)
			continue
		if not historian.data.has(tag):
			_text(Vector2(lx, legend_y), "pen %d — %s: not a tag" % [k + 1, tag], 11, COL_MUTED)
			continue
		var series := historian.series(tag)
		var offset := historian.start_index(tag)
		var lo := INF
		var hi := -INF
		var i := maxi(start, offset)
		while i < times.size():
			var local := i - offset
			if local >= series.size():
				break
			lo = minf(lo, series[local])
			hi = maxf(hi, series[local])
			i += 1
		if lo == INF:
			_text(Vector2(lx, legend_y), "pen %d — %s: no samples" % [k + 1, tag], 11, COL_MUTED)
			continue
		# Each pen on its own scale, padded so a flat line sits mid-chart.
		var span := hi - lo
		if span < 1e-9:
			span = maxf(absf(hi) * 0.1, 1.0)
			lo -= span / 2.0
			hi += span / 2.0
		var points := PackedVector2Array()
		i = maxi(start, offset)
		while i < times.size():
			var local := i - offset
			if local >= series.size():
				break
			points.append(Vector2(
				rect.position.x + rect.size.x * (times[i] - t0) / (t1 - t0 + 0.001),
				rect.end.y - rect.size.y * clampf((series[local] - lo) / (hi - lo), 0.0, 1.0)))
			i += stride
		if points.size() >= 2:
			draw_polyline(points, color, 1.6)
		var last := series[series.size() - 1] if series.size() > 0 else 0.0
		draw_rect(Rect2(lx, legend_y - 10, 10, 10), color)
		_text(Vector2(lx + 16, legend_y), tag, 11, color)
		_text(Vector2(lx + 16, legend_y + 16), "%s   [%s … %s]" % [_fmt(last), _fmt(lo), _fmt(hi)], 11, COL_INK)


func _fmt(v: float) -> String:
	if absf(v) >= 1000.0:
		return "%.0f" % v
	if absf(v) >= 10.0:
		return "%.1f" % v
	return "%.3f" % v


func _text(pos: Vector2, text: String, size_px: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := -1
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		width = 300
		pos.x -= 150 if align == HORIZONTAL_ALIGNMENT_CENTER else 300
	draw_string(_font, pos, text, align, width, size_px, color)
