class_name CabinetEditor
extends Control
## The Control Cabinet Editor: a straight-on, gamified view of the
## enclosure. LEFT — the rack: three DIN rails of slot cells; pick a
## module from the palette and click a cell to mount it, click a
## mounted module to select it (Remove / Ladder editor for the CPU).
## RIGHT — the wiring panel: every mounted module's ports as nodes;
## click a source (▸) then a destination (◦) to land an internal wire,
## live-lit by the real signal, removable from the list below. I/O
## cards gate which PLC channels exist to wire. The 3D interior
## renders whatever is built here when the editor closes.

const CELL := Vector2(46, 40)

var _plant: Plant = null
var _cab := ""
var _palette_pick := ""
var _selected_module := ""
var _wire_pick := ""

var _title: Label
var _status: Label
var _rack_box: VBoxContainer
var _palette_box: HBoxContainer
var _module_panel: HBoxContainer
var _nodes_box: VBoxContainer
var _wires_box: VBoxContainer
var _canvas: Control
var _buttons: Dictionary = {}   # "comp:port" -> Button


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
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

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_header("RACK — pick a module, click a slot"))
	_palette_box = HBoxContainer.new()
	_palette_box.add_theme_constant_override("separation", 4)
	left.add_child(_palette_box)
	for type_id: String in CabinetSpec.MODULES:
		var pick := Button.new()
		pick.text = str((CabinetSpec.MODULES[type_id] as Dictionary)["label"])
		pick.add_theme_font_size_override("font_size", 11)
		pick.toggle_mode = true
		pick.pressed.connect(func() -> void: _pick_palette(type_id))
		_palette_box.add_child(pick)
	_rack_box = VBoxContainer.new()
	_rack_box.add_theme_constant_override("separation", 10)
	left.add_child(_rack_box)
	_module_panel = HBoxContainer.new()
	_module_panel.add_theme_constant_override("separation", 8)
	left.add_child(_module_panel)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_header("WIRING — click ▸ source, then ◦ destination"))
	var mid := HBoxContainer.new()
	right.add_child(mid)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 330)
	mid.add_child(scroll)
	_nodes_box = VBoxContainer.new()
	_nodes_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_nodes_box)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(30, 0)
	mid.add_child(_canvas)
	right.add_child(_header("Internal wires"))
	var wire_scroll := ScrollContainer.new()
	wire_scroll.custom_minimum_size = Vector2(330, 110)
	right.add_child(wire_scroll)
	_wires_box = VBoxContainer.new()
	_wires_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wire_scroll.add_child(_wires_box)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	var close := Button.new()
	close.text = "  Done (Esc)  "
	close.pressed.connect(close_panel)
	foot.add_child(close)
	column.add_child(foot)


func open(plant: Plant, cab_name: String) -> void:
	_plant = plant
	_cab = cab_name
	_palette_pick = ""
	_selected_module = ""
	_wire_pick = ""
	_title.text = "%s — Control Cabinet Editor" % cab_name
	_status.text = "an empty enclosure: mount a PSU, a PLC CPU, I/O cards, terminal strips…"
	_rebuild()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	visible = false
	_plant = null
	MouseMode.capture()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	return label


func _pick_palette(type_id: String) -> void:
	_palette_pick = type_id
	_selected_module = ""
	for pick: Button in _palette_box.get_children():
		pick.button_pressed = pick.text == str((CabinetSpec.MODULES[type_id] as Dictionary)["label"])
	_status.text = "click a rail slot to mount the %s" \
		% str((CabinetSpec.MODULES[type_id] as Dictionary)["label"])
	_rebuild()


## ---- rack -----------------------------------------------------------------

func _rebuild() -> void:
	for old in _rack_box.get_children():
		old.queue_free()
	for old in _module_panel.get_children():
		old.queue_free()
	for old in _nodes_box.get_children():
		old.queue_free()
	for old in _wires_box.get_children():
		old.queue_free()
	_buttons.clear()
	if _plant == null or not _plant.cabinets.has(_cab):
		return
	var modules: Array = (_plant.cabinets[_cab] as Dictionary)["modules"]
	for rail in range(CabinetSpec.RAILS):
		_rack_box.add_child(_rail_row(rail, modules))
	_build_module_panel(modules)
	_build_wiring(modules)


func _rail_row(rail: int, modules: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var rail_tag := Label.new()
	rail_tag.text = "R%d" % (rail + 1)
	rail_tag.custom_minimum_size = Vector2(26, 0)
	row.add_child(rail_tag)
	var slot := 0
	while slot < CabinetSpec.SLOTS:
		var occupied: Dictionary = {}
		for module_v: Variant in modules:
			var module := module_v as Dictionary
			if int(module["rail"]) == rail and int(module["slot"]) == slot:
				occupied = module
				break
		if not occupied.is_empty():
			var type_id := str(occupied["type"])
			var spec: Dictionary = CabinetSpec.MODULES[type_id]
			var units := CabinetSpec.units_of(type_id)
			var module_btn := Button.new()
			module_btn.text = str(spec["label"])
			module_btn.add_theme_font_size_override("font_size", 11)
			module_btn.custom_minimum_size = Vector2(CELL.x * units + 2 * (units - 1), CELL.y)
			var bg := StyleBoxFlat.new()
			bg.bg_color = spec["color"]
			bg.set_corner_radius_all(4)
			bg.border_color = Color(0.9, 0.9, 0.9) if str(occupied["id"]) == _selected_module \
				else Color(0.2, 0.2, 0.22)
			bg.set_border_width_all(2 if str(occupied["id"]) == _selected_module else 1)
			module_btn.add_theme_stylebox_override("normal", bg)
			module_btn.add_theme_stylebox_override("hover", bg)
			module_btn.add_theme_stylebox_override("pressed", bg)
			var module_id := str(occupied["id"])
			module_btn.pressed.connect(func() -> void:
				_selected_module = module_id
				_palette_pick = ""
				for pick: Button in _palette_box.get_children():
					pick.button_pressed = false
				_rebuild())
			row.add_child(module_btn)
			slot += units
		else:
			var cell := Button.new()
			cell.text = ""
			cell.custom_minimum_size = CELL
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.13, 0.14, 0.17)
			bg.border_color = Color(0.24, 0.25, 0.28)
			bg.set_border_width_all(1)
			cell.add_theme_stylebox_override("normal", bg)
			var this_rail := rail
			var this_slot := slot
			cell.pressed.connect(func() -> void: _cell_clicked(this_rail, this_slot))
			row.add_child(cell)
			slot += 1
	return row


func _cell_clicked(rail: int, slot: int) -> void:
	if _palette_pick == "":
		_status.text = "pick a module from the palette first"
		return
	var error := _plant.cabinet_add_module(_cab, _palette_pick, rail, slot)
	_status.text = ("mounted %s on rail %d" % [_palette_pick, rail + 1]) if error == "" else error
	_rebuild()


func _build_module_panel(modules: Array) -> void:
	if _selected_module == "":
		return
	for module_v: Variant in modules:
		var module := module_v as Dictionary
		if str(module["id"]) != _selected_module:
			continue
		var tag := Label.new()
		tag.text = "%s %s" % [str(module["id"]).to_upper(),
			str((CabinetSpec.MODULES[str(module["type"])] as Dictionary)["label"])]
		_module_panel.add_child(tag)
		if str(module["type"]) == "plc":
			var ladder := Button.new()
			ladder.text = "Ladder editor →"
			ladder.pressed.connect(func() -> void:
				var plant := _plant
				var cab := _cab
				visible = false
				if plant.ladder_panel != null:
					plant.ladder_panel.open(plant, cab))
			_module_panel.add_child(ladder)
		var remove := Button.new()
		remove.text = "Remove module"
		var module_id := str(module["id"])
		remove.pressed.connect(func() -> void:
			_plant.cabinet_remove_module(_cab, module_id)
			_selected_module = ""
			_status.text = "removed %s (its wires went with it)" % module_id
			_rebuild())
		_module_panel.add_child(remove)
		return


## ---- wiring ---------------------------------------------------------------

func _build_wiring(modules: Array) -> void:
	var backed: Dictionary = _plant.cabinet_backed_channels(_cab)
	for module_v: Variant in modules:
		var module := module_v as Dictionary
		var type_id := str(module["type"])
		if CabinetSpec.CARD_FAMILY.has(type_id):
			continue  # cards surface as PLC channels below
		for record_name: String in module["records"]:
			var record := _plant.sim.get_component(record_name)
			if record == null:
				continue
			if record is SimPLC:
				_nodes_box.add_child(_header("  %s (CPU)" % str(module["id"]).to_upper()))
				var plc := record as SimPLC
				var grid := GridContainer.new()
				grid.columns = 4
				grid.add_theme_constant_override("h_separation", 3)
				_nodes_box.add_child(grid)
				for i: int in backed["di"]:
					grid.add_child(_node(record_name, "di_%d" % i, false))
				for i: int in backed["do"]:
					grid.add_child(_node(record_name, "do_%d" % i, true))
				for i: int in backed["ai"]:
					grid.add_child(_node(record_name, "ai_%d" % i, false))
				for i: int in backed["ao"]:
					grid.add_child(_node(record_name, "ao_%d" % i, true))
				grid.add_child(_node(record_name, "power", false))
				if backed["di"].is_empty() and backed["do"].is_empty():
					var hint := Label.new()
					hint.text = "   (mount I/O cards to expose channels)"
					hint.add_theme_font_size_override("font_size", 11)
					_nodes_box.add_child(hint)
			else:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 3)
				var tag := Label.new()
				tag.text = record_name.trim_prefix(_cab + "_")
				tag.custom_minimum_size = Vector2(70, 0)
				tag.add_theme_font_size_override("font_size", 12)
				row.add_child(tag)
				for port_name: String in record.outputs:
					row.add_child(_node(record_name, port_name, true))
				for port_name: String in record.inputs:
					row.add_child(_node(record_name, port_name, false))
				_nodes_box.add_child(row)
	for visual: Dictionary in _internal_wires():
		var row := HBoxContainer.new()
		var text := Label.new()
		text.text = "%s.%s → %s.%s" % [str(visual["a"]).trim_prefix(_cab + "_"),
			visual["a_port"], str(visual["b"]).trim_prefix(_cab + "_"), visual["b_port"]]
		text.add_theme_font_size_override("font_size", 12)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var remove := Button.new()
		remove.text = "✕"
		var target := visual
		remove.pressed.connect(func() -> void:
			_plant.remove_internal_wire(target)
			_plant._sync_cabinet(_cab)
			_status.text = "wire removed"
			_rebuild())
		row.add_child(remove)
		_wires_box.add_child(row)


func _node(comp: String, port: String, is_source: bool) -> Button:
	var button := Button.new()
	button.text = ("▸ " if is_source else "◦ ") + port
	button.add_theme_font_size_override("font_size", 11)
	button.custom_minimum_size = Vector2(62, 22)
	var key := "%s:%s" % [comp, port]
	button.pressed.connect(func() -> void: _node_clicked(comp, port, is_source))
	_buttons[key] = button
	return button


func _node_clicked(comp: String, port: String, is_source: bool) -> void:
	if is_source:
		_wire_pick = "%s:%s" % [comp, port]
		_status.text = "source %s.%s — click a ◦ destination" % [comp.trim_prefix(_cab + "_"), port]
		return
	if _wire_pick == "":
		_status.text = "click a ▸ source first"
		return
	var src := _wire_pick.split(":")
	var error := _plant.connect_equipment(src[0], src[1], comp, port, [], false)
	if error == "":
		_status.text = "wired %s.%s → %s.%s" % [str(src[0]).trim_prefix(_cab + "_"), src[1],
			comp.trim_prefix(_cab + "_"), port]
		_plant._sync_cabinet(_cab)
	else:
		_status.text = error
	_wire_pick = ""
	_rebuild()


func _internal_wires() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _plant == null:
		return out
	var members := {}
	for record_name in _plant.cabinet_all_records(_cab):
		members[record_name] = true
	for visual: Dictionary in _plant._wire_visuals:
		if members.has(str(visual["a"])) and members.has(str(visual["b"])):
			out.append(visual)
	return out


## Live node coloring: sources glow when their real value is high.
func _process(_delta: float) -> void:
	if not visible or _plant == null:
		return
	for key: String in _buttons:
		var parts := key.split(":")
		var record := _plant.sim.get_component(parts[0])
		if record == null:
			continue
		var live := false
		if record.outputs.has(parts[1]):
			live = (record.outputs[parts[1]] as SimOutputPort).value > 0.5
		elif record.inputs.has(parts[1]):
			live = (record.inputs[parts[1]] as SimInputPort).value > 0.5
		(_buttons[key] as Button).modulate = Color(0.35, 0.95, 0.5) if live \
			else Color(0.85, 0.86, 0.85)
