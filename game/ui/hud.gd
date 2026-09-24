class_name Hud
extends Control
## Crosshair, look-at readout, quick toast messages, and a small live
## tag readout. All text comes from sim records via main.gd.

var _look_label: Label
var _readout_label: Label
var _toast_label: Label
var _mode_label: Label
var _alarm_label: Label
var _fps_label: Label
var _fps_note := ""
var _fps_left := 0.0
var _toast_tween: Tween


func _ready() -> void:
	# set_anchors_preset alone compensates offsets to preserve the
	# current (zero) rect — the whole HUD collapses to a point at the
	# top-left. This variant zeroes the offsets too: a real full rect.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	_look_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_look_label.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	_look_label.position.y -= 140.0
	_look_label.grow_horizontal = GROW_DIRECTION_BOTH

	_readout_label = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_readout_label.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	_readout_label.position = Vector2(12, 10)

	_toast_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_toast_label.position.y += 40.0
	_toast_label.grow_horizontal = GROW_DIRECTION_BOTH
	_toast_label.modulate.a = 0.0

	_mode_label = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_mode_label.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	# A fixed region tucked 12 px inside the corner, tall enough for the
	# build catalog list; bottom-aligned text reads as growing upward.
	# Fixed rect + alignment beats relying on min-size auto-grow, which
	# extends downward off-screen regardless of grow direction.
	_mode_label.offset_left = 12.0
	_mode_label.offset_right = 560.0
	_mode_label.offset_top = -300.0
	_mode_label.offset_bottom = -12.0
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	# Active alarms, top right: the annunciator. Hidden when the plant
	# has nothing to say.
	_alarm_label = _make_label(HORIZONTAL_ALIGNMENT_RIGHT)
	_alarm_label.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	_alarm_label.offset_left = -520.0
	_alarm_label.offset_right = -12.0
	_alarm_label.offset_top = 10.0
	_alarm_label.offset_bottom = 160.0
	_alarm_label.add_theme_color_override("font_color", Color(0.98, 0.45, 0.35))
	_alarm_label.visible = false

	# The frame-rate overlay: under the readout, what the
	# frame costs and what the graphics preset is, so the balance
	# between speed and looks can be read while walking.
	_fps_label = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_fps_label.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	_fps_label.position = Vector2(12, 32)
	_fps_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	_fps_label.visible = false


func _make_label(align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", Color(0.93, 0.93, 0.90))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label


func _draw() -> void:
	draw_circle(size / 2.0, 2.5, Color(0.95, 0.95, 0.93, 0.9))


var _cpu_acc := 0.0
var _phys_acc := 0.0
var _cpu_n := 0


func _process(delta: float) -> void:
	queue_redraw()
	if not _fps_label.visible:
		return
	_cpu_acc += Performance.get_monitor(Performance.TIME_PROCESS)
	_phys_acc += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_cpu_n += 1
	_fps_left -= delta
	if _fps_left > 0.0:
		return
	_fps_left = 0.25
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	# The window's pixels, not the stretched 1280x720 the HUD is laid out in.
	var out := Vector2(get_window().size)
	var scale := get_viewport().scaling_3d_scale
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	# The CPU's share of the frame, averaged over the window: the main
	# loop and a physics tick. When the loop is close to the frame
	# time, no graphics knob will help.
	var n := maxi(_cpu_n, 1)
	var cpu := _cpu_acc / n * 1000.0
	var phys := _phys_acc / n * 1000.0
	_cpu_acc = 0.0
	_phys_acc = 0.0
	_cpu_n = 0
	_fps_label.text = "%d fps · %.1f ms (loop %.1f · physics %.1f · sim tick %.1f) · %dx%d of %dx%d · %.2f M tris · %d draws · %.0f MB\n%s" % [
		fps, 1000.0 / maxf(fps, 1.0), cpu, phys, sim_ms, roundi(out.x * scale), roundi(out.y * scale),
		roundi(out.x), roundi(out.y), tris / 1.0e6, draws, vram / (1024.0 * 1024.0), _fps_note]


## What the latest simulation scan cost; the world sets it each frame.
var sim_ms := 0.0


## The overlay on or off, with the graphics summary it shows under the numbers.
func set_fps_overlay(on: bool, note: String) -> void:
	_fps_note = note
	_fps_label.visible = on
	_fps_left = 0.0


func set_look_text(text: String) -> void:
	_look_label.text = text


func set_readout_text(text: String) -> void:
	_readout_label.text = text


## The annunciator: one line per active alarm, oldest first, at most
## six with a count of the rest.
func set_alarms(lines: PackedStringArray) -> void:
	if lines.is_empty():
		_alarm_label.visible = false
		return
	var shown := lines.slice(0, mini(lines.size(), 6))
	if lines.size() > 6:
		shown.append("… and %d more" % (lines.size() - 6))
	_alarm_label.text = "\n".join(shown)
	_alarm_label.visible = true


func set_mode_text(text: String) -> void:
	_mode_label.text = text


func toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.6)
