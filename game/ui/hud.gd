class_name Hud
extends Control
## Crosshair, look-at readout, quick toast messages, and a small live
## tag readout. All text comes from sim records via main.gd.

var _look_label: Label
var _readout_label: Label
var _toast_label: Label
var _mode_label: Label
var _toast_tween: Tween


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	_look_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_look_label.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_look_label.position.y -= 140.0
	_look_label.grow_horizontal = GROW_DIRECTION_BOTH

	_readout_label = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_readout_label.set_anchors_preset(PRESET_TOP_LEFT)
	_readout_label.position = Vector2(12, 10)

	_toast_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.set_anchors_preset(PRESET_CENTER_TOP)
	_toast_label.position.y += 40.0
	_toast_label.grow_horizontal = GROW_DIRECTION_BOTH
	_toast_label.modulate.a = 0.0

	_mode_label = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_mode_label.set_anchors_preset(PRESET_BOTTOM_LEFT)
	_mode_label.grow_vertical = GROW_DIRECTION_BEGIN
	_mode_label.position = Vector2(12, -12)


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
