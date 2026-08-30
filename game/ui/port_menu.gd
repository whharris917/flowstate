class_name PortMenu
extends Control
## Right-click a device: its declared I/O, straight from the sim
## record — outputs with live values, inputs with their wired state.
## Picking an output starts a routed connection from that port;
## picking an input (with a source pending) completes one. Cabinets
## list their whole terminal strip.

var _plant: Plant = null
var _pick: Callable = Callable()
var _list: VBoxContainer
var _title: Label


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
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	column.add_child(_list)


## records: the component names to list (one for equipment, many for a
## cabinet). pick(record, port, is_input) fires on selection.
func open(plant: Plant, title: String, records: Array, pick: Callable) -> void:
	_plant = plant
	_pick = pick
	_title.text = title
	for old in _list.get_children():
		old.queue_free()
	for record_name: String in records:
		var record := plant.sim.get_component(record_name)
		if record == null:
			continue
		var type_id := str(plant.equip_types.get(record_name, ""))
		for port_name: String in record.outputs:
			if port_name == "draw":
				continue  # the facade meters draw automatically
			var port: SimOutputPort = record.outputs[port_name]
			_list.add_child(_row(record_name, port_name, port.kind, port.spec, false,
				"%.2f" % port.value, true))
		for port_name: String in record.inputs:
			if port_name == "draw":
				continue
			var port: SimInputPort = record.inputs[port_name]
			var kind := port.kind
			if not PlantFactory.flow_inlet_spec(type_id, port_name).is_empty():
				kind = SimTypes.PortKind.PROCESS_FLOW  # it's a pipe stub
			var free := port.wire_count == 0 or SimTypes.allows_multiple_sources(port.kind)
			_list.add_child(_row(record_name, port_name, kind, port.spec, true,
				"wired" if port.wire_count > 0 else "open", free))
		# Facade outlets (tank/source) are pipe connections, not kernel
		# ports — list them with the availability value behind them.
		for ui_port: String in PlantFactory.FLOW_OUTLETS.get(type_id, {}):
			var spec: Dictionary = PlantFactory.FLOW_OUTLETS[type_id][ui_port]
			var avail: SimOutputPort = record.outputs.get(str(spec["avail"]))
			_list.add_child(_row(record_name, ui_port, SimTypes.PortKind.PROCESS_FLOW, "",
				false, "%.1f avail" % avail.value if avail != null else "", true))
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
