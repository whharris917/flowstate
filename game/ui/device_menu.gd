class_name DeviceMenu
extends Control
## Right-click a device: everything you can do to it, in two tabs
## (director, 2026-09-05: every modification to equipment goes through
## this menu; M moves it, X removes it).
## I/O lists its declared ports straight from the sim record — outputs
## with live values, inputs with their wired state. Picking an output
## starts a routed connection from that port; picking an input (with a
## source pending) completes one. Cabinets list their whole terminal
## strip.
## CONFIGURE edits the sizing the record was placed with — the same
## keys the save file carries — from PlantFactory.CONFIG. Apply hands
## the values to the plant, which owns what a change means (a resized
## tank re-renders and re-anchors its runs; a re-rated pump changes
## its curve).

var _plant: Plant = null
var _pick: Callable = Callable()
var _configure: Callable = Callable()   # (record_name, values) -> String
var _record_name := ""
var _tabs: TabContainer
var _io_list: VBoxContainer
var _config_form: VBoxContainer
var _title: Label
var _note: Label
var _fields: Dictionary = {}   # key -> SpinBox or OptionButton


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close())
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	panel.grow_horizontal = GROW_DIRECTION_BOTH
	panel.grow_vertical = GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 0.97)
	style.border_color = Color(0.40, 0.42, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 15)
	column.add_child(_title)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(420, 0)
	column.add_child(_tabs)
	var io_page := MarginContainer.new()
	io_page.name = "I/O"
	io_page.add_theme_constant_override("margin_top", 8)
	_tabs.add_child(io_page)
	_io_list = VBoxContainer.new()
	_io_list.add_theme_constant_override("separation", 3)
	io_page.add_child(_io_list)
	var config_page := MarginContainer.new()
	config_page.name = "CONFIGURE"
	config_page.add_theme_constant_override("margin_top", 8)
	_tabs.add_child(config_page)
	_config_form = VBoxContainer.new()
	_config_form.add_theme_constant_override("separation", 8)
	config_page.add_child(_config_form)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	column.add_child(_note)


## records: the component names to list (one for equipment, many for a
## cabinet). type_id sizes the CONFIGURE tab. pick(record, port,
## is_input) fires on an I/O selection; configure(record, values)
## applies sizing and returns "" or why not.
func open(plant: Plant, title: String, records: Array, type_id: String,
		pick: Callable, configure: Callable) -> void:
	_plant = plant
	_pick = pick
	_configure = configure
	_record_name = str(records[0]) if records.size() == 1 else ""
	_title.text = title
	_note.text = "M moves it · X removes it"
	_fill_io(records)
	_fill_config(type_id)
	_tabs.current_tab = 0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _fill_io(records: Array) -> void:
	for old in _io_list.get_children():
		old.queue_free()
	for record_name: String in records:
		var record := _plant.sim.get_component(record_name)
		if record == null:
			continue
		var hidden := record.hidden_ports()
		for port_name: String in record.outputs:
			if hidden.has(port_name):
				continue
			var port: SimOutputPort = record.outputs[port_name]
			# An outlet takes one line (director, 2026-09-12): a wired one
			# shows its reading and is not offered again.
			var taken := _plant.visible_wire_count(record_name, port_name) > 0
			_io_list.add_child(_row(record_name, port_name, port.kind, port.spec, false,
				("wired · " if taken else "") + port.reading(), not taken))
		for port_name: String in record.inputs:
			if hidden.has(port_name):
				continue
			var port: SimInputPort = record.inputs[port_name]
			var free := _plant.visible_wire_count(record_name, port_name) == 0
			var state := "wired" if port.wire_count > 0 else "open"
			if SimTypes.is_material(port.kind) and port.wire_count > 0:
				state = port.reading()
			_io_list.add_child(_row(record_name, port_name, port.kind, port.spec, true,
				state, free))


func _fill_config(type_id: String) -> void:
	for old in _config_form.get_children():
		old.queue_free()
	_fields.clear()
	var fields: Array = PlantFactory.CONFIG.get(type_id, [])
	var record := _plant.sim.get_component(_record_name) if _record_name != "" else null
	if record == null or fields.is_empty():
		var blank := Label.new()
		blank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blank.text = "open the door and press EDIT to build the panel" if type_id == "cabinet" \
			else "nothing to size on this device"
		_config_form.add_child(blank)
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_config_form.add_child(grid)
	for field: Dictionary in fields:
		var key := str(field["key"])
		var tag := Label.new()
		tag.text = str(field["label"])
		tag.custom_minimum_size = Vector2(150, 0)
		grid.add_child(tag)
		if str(field.get("kind", "")) == "tag":
			# A historian tag: type part of it, pick from the matches.
			var index := int(key.substr(3)) - 1
			var current := ""
			if record is SimTrendScreen and index >= 0 and index < SimTrendScreen.MAX_PENS:
				current = (record as SimTrendScreen).tags[index]
			var all_tags := PackedStringArray(_plant.historian.active_tags())
			all_tags.sort()
			var picker := TagPicker.new(all_tags, current)
			grid.add_child(picker)
			_fields[key] = picker
		elif str(field.get("kind", "")) == "toggle":
			var check := CheckBox.new()
			check.button_pressed = bool(record.get(key))
			check.text = "yes"
			grid.add_child(check)
			_fields[key] = check
		elif field.has("options"):
			var choice := OptionButton.new()
			var current := str(record.call("species_key"))
			for i in SimSpecies.COUNT:
				choice.add_item(SimSpecies.label_of(i), i)
				if SimSpecies.key_of(i) == current:
					choice.select(i)
			choice.custom_minimum_size = Vector2(180, 0)
			grid.add_child(choice)
			_fields[key] = choice
		else:
			var spin := SpinBox.new()
			spin.min_value = float(field["min"])
			spin.max_value = float(field["max"])
			spin.step = float(field["step"])
			spin.suffix = " " + str(field.get("unit", ""))
			spin.custom_minimum_size = Vector2(180, 0)
			spin.value = float(record.get(key))
			grid.add_child(spin)
			_fields[key] = spin
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	_config_form.add_child(buttons)
	var apply := Button.new()
	apply.text = "  Apply  "
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "  Cancel  "
	cancel.pressed.connect(close)
	buttons.add_child(cancel)


func _apply() -> void:
	var values := {}
	for key: String in _fields:
		var control: Control = _fields[key]
		if control is OptionButton:
			values[key] = SimSpecies.key_of((control as OptionButton).get_selected_id())
		elif control is TagPicker:
			values[key] = (control as TagPicker).text
		elif control is CheckBox:
			values[key] = (control as CheckBox).button_pressed
		else:
			values[key] = (control as SpinBox).value
	var why := ""
	if _configure.is_valid():
		why = str(_configure.call(_record_name, values))
	if why == "":
		close()
	else:
		_note.text = why
		_note.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))


func _row(record_name: String, port_name: String, kind: SimTypes.PortKind,
		spec: String, is_input: bool, state: String, enabled: bool) -> Button:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(360, 0)
	var kind_text := SimTypes.kind_name(kind) + ((" " + spec) if spec != "" else "")
	button.text = "%s  %s.%s   [%s]   %s" % [
		"◦ IN " if is_input else "▸ OUT", record_name, port_name, kind_text, state]
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", PlantFactory.KIND_COLORS[kind].lightened(0.3))
	button.disabled = not enabled
	button.pressed.connect(func() -> void:
		var pick := _pick
		close()
		if pick.is_valid():
			pick.call(record_name, port_name, is_input))
	return button


func close() -> void:
	visible = false
	_plant = null
	_note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	MouseMode.capture()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## A historian tag field: a line to type part of a tag into and a
## short list of the tags that match, one click to take one.
class TagPicker:
	extends VBoxContainer
	var edit: LineEdit
	var list: ItemList
	var all_tags: PackedStringArray
	var text: String:
		get:
			return edit.text.strip_edges()

	func _init(tags: PackedStringArray, current: String) -> void:
		all_tags = tags
		edit = LineEdit.new()
		edit.text = current
		edit.placeholder_text = "type part of a tag, e.g. r_301.temp"
		edit.custom_minimum_size = Vector2(260, 0)
		add_child(edit)
		list = ItemList.new()
		list.custom_minimum_size = Vector2(260, 0)
		list.auto_height = true
		list.visible = false
		add_child(list)
		edit.text_changed.connect(_filter)
		list.item_selected.connect(func(i: int) -> void:
			edit.text = list.get_item_text(i)
			list.visible = false)

	func _filter(typed: String) -> void:
		list.clear()
		var needle := typed.strip_edges().to_lower()
		if needle == "":
			list.visible = false
			return
		var shown := 0
		for tag in all_tags:
			if tag.to_lower().contains(needle):
				list.add_item(tag)
				shown += 1
				if shown >= 8:
					break
		list.visible = shown > 0
