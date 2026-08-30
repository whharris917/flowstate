class_name CabinetPanel
extends Control
## The cabinet's internal schematic: terminal strip on the left, PLC
## channels on the right, live wires drawn between them. Click a
## source node (terminal OUT, or PLC DO/AO) then a destination node
## (PLC DI/AI, or terminal IN) to land an internal wire — the kernel's
## rules judge it. Wires light with the real signal each frame; the
## list at the bottom removes them. Field wiring stays out in the 3D
## world; only the hookup inside the enclosure lives here.

var _plant: Plant = null
var _cab := ""
var _members: Dictionary = {}     # member comp name -> true
var _selected := ""               # "comp:port" pending source
var _buttons: Dictionary = {}     # "comp:port" -> Button
var _canvas: Control
var _rows: VBoxContainer
var _status: Label
var _title: Label
var _wires_box: VBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	panel.grow_horizontal = GROW_DIRECTION_BOTH
	panel.grow_vertical = GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 0.98)
	style.border_color = Color(0.40, 0.42, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 17)
	column.add_child(_title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.75, 0.85, 0.78))
	column.add_child(_status)

	_rows = VBoxContainer.new()
	column.add_child(_rows)

	var wires_label := Label.new()
	wires_label.text = "Internal wires"
	wires_label.add_theme_font_size_override("font_size", 14)
	column.add_child(wires_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	column.add_child(scroll)
	_wires_box = VBoxContainer.new()
	_wires_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_wires_box)

	var close := Button.new()
	close.text = "  Close (Esc)  "
	close.pressed.connect(close_panel)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(close)
	column.add_child(foot)


func open(plant: Plant, cab_name: String) -> void:
	_plant = plant
	_cab = cab_name
	_selected = ""
	var entry: Dictionary = plant.cabinets.get(cab_name, {})
	if entry.is_empty():
		return
	_members.clear()
	_members[str(entry["plc"])] = true
	for term: String in entry["terminals"]:
		_members[term] = true
	_title.text = "%s — internal wiring" % cab_name
	_status.text = "click a SOURCE (terminal OUT / PLC DO / AO), then a DESTINATION (PLC DI / AI / terminal IN)"
	_rebuild()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	visible = false
	_plant = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


## ---- layout ---------------------------------------------------------------

func _rebuild() -> void:
	for old in _rows.get_children():
		old.queue_free()
	for old in _wires_box.get_children():
		old.queue_free()
	_buttons.clear()

	var entry: Dictionary = _plant.cabinets[_cab]
	var plc_name := str(entry["plc"])
	var plc := _plant.sim.get_component(plc_name) as SimPLC

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_rows.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	body.add_child(left)
	left.add_child(_header("TERMINALS"))
	for term: String in entry["terminals"]:
		var record := _plant.sim.get_component(term) as SimTerminal
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var tag := Label.new()
		tag.text = term.trim_prefix(_cab + "_").to_upper()
		tag.custom_minimum_size = Vector2(46, 0)
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color",
			Color(0.65, 0.80, 0.95) if record.kind == "analog" else Color(0.80, 0.82, 0.80))
		row.add_child(tag)
		row.add_child(_node_button(term, "out", true))
		row.add_child(_node_button(term, "in", false))
		left.add_child(row)

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(260, 0)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_wires)
	body.add_child(_canvas)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	body.add_child(right)
	right.add_child(_header("PLC I/O"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	right.add_child(grid)
	for i in range(plc.n_di):
		grid.add_child(_node_button(plc_name, "di_%d" % i, false))
	for i in range(plc.n_do):
		grid.add_child(_node_button(plc_name, "do_%d" % i, true))
	for i in range(plc.n_ai):
		grid.add_child(_node_button(plc_name, "ai_%d" % i, false))
	for i in range(plc.n_ao):
		grid.add_child(_node_button(plc_name, "ao_%d" % i, true))

	for visual: Dictionary in _internal_wires():
		var row := HBoxContainer.new()
		var text := Label.new()
		text.text = "%s.%s  →  %s.%s" % [_short(visual["a"]), visual["a_port"],
			_short(visual["b"]), visual["b_port"]]
		text.add_theme_font_size_override("font_size", 13)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var remove := Button.new()
		remove.text = "✕"
		var target := visual
		remove.pressed.connect(func() -> void:
			_plant.remove_internal_wire(target)
			_status.text = "removed %s.%s → %s.%s" % [_short(target["a"]), target["a_port"],
				_short(target["b"]), target["b_port"]]
			_rebuild())
		row.add_child(remove)
		_wires_box.add_child(row)


func _short(comp: String) -> String:
	return str(comp).trim_prefix(_cab + "_")


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	return label


func _node_button(comp: String, port: String, is_source: bool) -> Button:
	var key := "%s:%s" % [comp, port]
	var button := Button.new()
	button.text = ("▸ " if is_source else "◦ ") + port
	button.add_theme_font_size_override("font_size", 12)
	button.custom_minimum_size = Vector2(64, 24)
	button.pressed.connect(func() -> void: _clicked(comp, port, is_source))
	_buttons[key] = button
	return button


func _clicked(comp: String, port: String, is_source: bool) -> void:
	var key := "%s:%s" % [comp, port]
	if is_source:
		_selected = key
		_status.text = "source %s.%s — now click a destination" % [_short(comp), port]
		return
	if _selected == "":
		_status.text = "pick a SOURCE first (▸ nodes)"
		return
	var src := _selected.split(":")
	var error := _plant.connect_equipment(src[0], src[1], comp, port, [], false)
	_status.text = ("wired %s.%s → %s.%s" % [_short(src[0]), src[1], _short(comp), port]) \
		if error == "" else error
	_selected = ""
	_rebuild()


## ---- live schematic lines -------------------------------------------------

func _internal_wires() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _plant == null:
		return out
	for visual: Dictionary in _plant._wire_visuals:
		if _members.has(str(visual["a"])) and _members.has(str(visual["b"])):
			out.append(visual)
	return out


func _process(_delta: float) -> void:
	if visible and _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_redraw()


func _draw_wires() -> void:
	if _plant == null:
		return
	var origin := _canvas.get_global_rect().position
	for visual: Dictionary in _internal_wires():
		var a: Button = _buttons.get("%s:%s" % [visual["a"], visual["a_port"]])
		var b: Button = _buttons.get("%s:%s" % [visual["b"], visual["b_port"]])
		if a == null or b == null:
			continue
		var from := a.get_global_rect().get_center() - origin
		var to := b.get_global_rect().get_center() - origin
		var src := _plant.sim.get_component(str(visual["a"]))
		var port: SimOutputPort = src.outputs.get(str(visual["a_port"])) if src != null else null
		var live := port != null and port.value > 0.5
		var mid_a := Vector2(from.x + 30, from.y)
		var mid_b := Vector2(to.x - 30, to.y)
		var color := Color(0.25, 0.95, 0.45) if live else Color(0.45, 0.48, 0.50)
		_canvas.draw_line(from, mid_a, color, 2.0)
		_canvas.draw_line(mid_a, mid_b, color, 2.0)
		_canvas.draw_line(mid_b, to, color, 2.0)
