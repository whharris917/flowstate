class_name Hud
extends Control
## Crosshair, look-at readout, quick toast messages, and a small live
## tag readout. All text comes from sim records via main.gd.

var _look_label: Label
var _readout_label: Label
var _toast_label: Label
var _mode_label: Label
var _alarm_label: Label
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


func _process(_delta: float) -> void:
	queue_redraw()


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
