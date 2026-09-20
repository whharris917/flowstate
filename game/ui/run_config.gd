class_name RunConfigPanel
extends Control
## In-game editor for run service color + line label, and for sign
## text. Opens with the mouse released over a dimmed backdrop; OK
## applies via the callable the opener provided, then the mouse is
## captured again. ASME A13.1-flavored service palette.

const PALETTE: Array = [
	["gas", Color(0.93, 0.79, 0.10)],
	["water", Color(0.13, 0.55, 0.28)],
	["air", Color(0.15, 0.35, 0.75)],
	["fire", Color(0.80, 0.15, 0.12)],
	["acid", Color(0.90, 0.45, 0.10)],
	["alkali", Color(0.55, 0.30, 0.75)],
	["steam", Color(0.78, 0.79, 0.82)],
	["oil", Color(0.45, 0.30, 0.18)],
]

var _apply: Callable = Callable()
var _picked: Color = Color.WHITE
var _title: Label
var _grid: GridContainer
var _swatches: Array[Button] = []
var _line: LineEdit
var _fitting: OptionButton
var _size: OptionButton
var _size_row: HBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	panel.grow_horizontal = GROW_DIRECTION_BOTH
	panel.grow_vertical = GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.13, 0.97)
	style.border_color = Color(0.40, 0.42, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_grid)
	for entry: Array in PALETTE:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(92, 40)
		swatch.text = entry[0]
		var color: Color = entry[1]
		swatch.add_theme_stylebox_override("normal", _swatch_style(color, false))
		swatch.add_theme_stylebox_override("hover", _swatch_style(color, true))
		swatch.add_theme_stylebox_override("pressed", _swatch_style(color, true))
		swatch.add_theme_color_override("font_color",
			Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE)
		swatch.pressed.connect(func() -> void: _pick(color))
		_grid.add_child(swatch)
		_swatches.append(swatch)

	_line = LineEdit.new()
	_line.placeholder_text = "line label, e.g. PW-101"
	_line.custom_minimum_size = Vector2(340, 0)
	_line.text_submitted.connect(func(_t: String) -> void: _ok())
	column.add_child(_line)
	# What the line ends in: flanges, sanitary clamps, or on a small
	# line compression fittings on tubing (director, 2026-09-20).
	var fitting_row := HBoxContainer.new()
	fitting_row.add_theme_constant_override("separation", 8)
	column.add_child(fitting_row)
	var fitting_label := Label.new()
	fitting_label.text = "fittings"
	fitting_row.add_child(fitting_label)
	_fitting = OptionButton.new()
	_fitting.add_item("flanged pipe", 0)
	_fitting.add_item("sanitary tri-clamp", 1)
	_fitting.add_item("tubing, compression fittings", 2)
	fitting_row.add_child(_fitting)
	# The line size (director, 2026-09-20): a nominal bore.
	_size_row = HBoxContainer.new()
	_size_row.add_theme_constant_override("separation", 8)
	column.add_child(_size_row)
	var size_label := Label.new()
	size_label.text = "line size"
	_size_row.add_child(size_label)
	_size = OptionButton.new()
	for dn: int in Plant.LINE_SIZES:
		_size.add_item("DN%d" % dn, dn)
	_size_row.add_child(_size)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var ok := Button.new()
	ok.text = "  Apply  "
	ok.pressed.connect(_ok)
	buttons.add_child(ok)
	var cancel := Button.new()
	cancel.text = "  Cancel  "
	cancel.pressed.connect(close)
	buttons.add_child(cancel)


func _swatch_style(color: Color, bright: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.lightened(0.15) if bright else color
	style.set_corner_radius_all(5)
	style.border_color = Color(0.9, 0.9, 0.9) if bright else Color(0.25, 0.25, 0.28)
	style.set_border_width_all(2)
	return style


func _pick(color: Color) -> void:
	_picked = color


## Color + label editor for a run.
func open_for_run(current: Color, label_text: String, apply: Callable, fitting: String = "flange",
		dn: int = 0) -> void:
	_apply = apply
	_picked = current
	_title.text = "Run service — pick a color, name the line"
	_grid.visible = true
	_fitting.get_parent().set("visible", true)
	_fitting.select({"clamp": 1, "tube": 2}.get(fitting, 0))
	_size_row.visible = dn > 0
	if dn > 0:
		_size.select(_size.get_item_index(dn))
	_line.text = label_text
	_open()


## Text-only editor for a sign.
func open_for_sign(text: String, apply: Callable) -> void:
	_apply = apply
	_title.text = "Sign text"
	_grid.visible = false
	_fitting.get_parent().set("visible", false)
	_size_row.visible = false
	_line.text = text
	_open()


func _open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_line.grab_focus()


func _ok() -> void:
	if _apply.is_valid():
		if _grid.visible:
			var dn := _size.get_item_id(_size.selected) if _size_row.visible else 0
			_apply.call(_picked, _line.text, ["flange", "clamp", "tube"][_fitting.selected], dn)
		else:
			_apply.call(_line.text)
	close()


func close() -> void:
	visible = false
	MouseMode.capture()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
