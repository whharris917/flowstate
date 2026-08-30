class_name TrendPanel
extends Control
## The HMI screen's face: a level trend drawn straight from historian
## samples — the same no-faked-data contract as the Python GUI. Renders
## inside a SubViewport that an HmiView quad displays in the world.

const WINDOW_S := 120.0
const MARGIN_L := 46.0
const MARGIN_R := 10.0
const MARGIN_T := 30.0
const MARGIN_B := 20.0

const COL_BG := Color(0.10, 0.10, 0.10)
const COL_GRID := Color(0.17, 0.17, 0.165)
const COL_INK := Color(0.95, 0.95, 0.93)
const COL_MUTED := Color(0.54, 0.53, 0.51)
const COL_SERIES := Color(0.22, 0.53, 0.90)

var historian: SimHistorian
var tank: SimTank
var switch: SimFloatSwitch
var relay: SimRelay
var pump: SimPump
var _level_tag: String


func setup(historian_: SimHistorian, tank_: SimTank, switch_: SimFloatSwitch,
		relay_: SimRelay, pump_: SimPump) -> void:
	historian = historian_
	tank = tank_
	switch = switch_
	relay = relay_
	pump = pump_
	_level_tag = tank_.level.path()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if historian == null or historian.sample_count() < 2:
		return
	var font := ThemeDB.fallback_font
	var plot := Rect2(MARGIN_L, MARGIN_T,
		size.x - MARGIN_L - MARGIN_R, size.y - MARGIN_T - MARGIN_B)
	var times := historian.time
	var levels := historian.series(_level_tag)
	var offset := historian.start_index(_level_tag)
	var t1 := times[times.size() - 1]
	var t0 := maxf(times[0], t1 - WINDOW_S)
	var y_max := tank.capacity_l

	for tick_l: int in range(0, int(y_max) + 1, 25):
		var y := plot.position.y + plot.size.y * (1.0 - tick_l / y_max)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), COL_GRID, 1.0)
		draw_string(font, Vector2(4, y + 4), str(tick_l),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_MUTED)

	for trip: float in [switch.low_l, switch.high_l]:
		var y := plot.position.y + plot.size.y * (1.0 - trip / y_max)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), COL_MUTED, 1.0)

	var points := PackedVector2Array()
	var start := times.size() - 1
	while start > 0 and times[start - 1] >= t0:
		start -= 1
	var count := times.size() - start
	var stride := maxi(1, ceili(count / (plot.size.x * 2.0)))
	var i := maxi(start, offset)
	while i < times.size():
		var local := i - offset
		if local >= levels.size():
			break
		points.append(Vector2(
			plot.position.x + plot.size.x * (times[i] - t0) / (t1 - t0 + 0.001),
			plot.position.y + plot.size.y * (1.0 - clampf(levels[local] / y_max, 0.0, 1.0))))
		i += stride
	if points.size() >= 2:
		draw_polyline(points, COL_SERIES, 2.0, true)

	draw_string(font, Vector2(6, 20), "%s — last %d s (historized)" % [_level_tag, int(WINDOW_S)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_MUTED)
	draw_string(font, Vector2(size.x - 120, 20), "%.1f L" % tank.level_l,
		HORIZONTAL_ALIGNMENT_RIGHT, 110, 15, COL_INK)
	draw_string(font, Vector2(6, size.y - 5),
		"relay %d cyc · pump %d starts · pump %s" % [
			relay.cycles, pump.starts, pump.mode.to_upper()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_MUTED)
