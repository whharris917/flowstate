class_name TankConfigPanel
extends Control
## Vessel size editor: height and diameter spinboxes with a live
## derived-capacity readout. Apply resizes the real record, rebuilds
## the view, and re-anchors connected pipes.

var _plant: Plant = null
var _tank_name := ""
var _height: SpinBox
var _diameter: SpinBox
var _capacity: Label
var _title: Label


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
	_title.add_theme_font_size_override("font_size", 16)
	column.add_child(_title)

	_height = _spin(column, "Height", 0.5, 12.0)
	_diameter = _spin(column, "Diameter", 0.4, 6.0)
	_capacity = Label.new()
	_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capacity.add_theme_color_override("font_color", Color(0.65, 0.85, 0.70))
	column.add_child(_capacity)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var apply := Button.new()
	apply.text = "  Apply  "
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "  Cancel  "
	cancel.pressed.connect(close)
	buttons.add_child(cancel)


func _spin(parent: Control, label_text: String, min_v: float, max_v: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag := Label.new()
	tag.text = label_text
	tag.custom_minimum_size = Vector2(80, 0)
	row.add_child(tag)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 0.1
	spin.suffix = " m"
	spin.custom_minimum_size = Vector2(140, 0)
	spin.value_changed.connect(func(_v: float) -> void: _update_capacity())
	row.add_child(spin)
	parent.add_child(row)
	return spin


func open(plant: Plant, tank_name: String) -> void:
	_plant = plant
	_tank_name = tank_name
	var record := plant.sim.get_component(tank_name) as SimTank
	if record == null:
		return
	_title.text = "%s — vessel size" % tank_name
	_height.value = record.height_m
	_diameter.value = record.diameter_m
	_update_capacity()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_capacity() -> void:
	var capacity := PI * pow(_diameter.value / 2.0, 2) * _height.value * 1000.0
	_capacity.text = "capacity %.0f L" % capacity


func _apply() -> void:
	if _plant != null:
		_plant.resize_tank(_tank_name, _height.value, _diameter.value)
	close()


func close() -> void:
	visible = false
	_plant = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
