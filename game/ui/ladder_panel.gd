class_name LadderPanel
extends Control
## The PLC's ladder editor. Each rung is drawn between power rails:
## series contacts (with NC toggles) in parallel branches on the left,
## one coil on the right (DO channel, memory bit, or TON timer with a
## preset). Every edit applies immediately through the kernel's
## program validator, and the whole ladder lights with live power
## flow from the scanning PLC — a contact glows when it passes, a
## coil when it is driven.

const GREEN := Color(0.30, 0.95, 0.45)
const IDLE := Color(0.80, 0.82, 0.80)

var _plant: Plant = null
var _cab := ""
var _plc: SimPLC = null
var _model: Array = []          # same schema the kernel validates
var _rungs_box: VBoxContainer
var _status: Label
var _title: Label
var _contact_widgets: Array[Dictionary] = []   # {node, ref, nc}
var _coil_widgets: Array[Dictionary] = []      # {node, coil}
var _acc_labels: Array[Dictionary] = []        # {node, index}
var _pulse := 0.0


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
	style.bg_color = Color(0.08, 0.09, 0.11, 0.98)
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

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 380)
	column.add_child(scroll)
	_rungs_box = VBoxContainer.new()
	_rungs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rungs_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rungs_box)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	column.add_child(foot)
	var add_rung := Button.new()
	add_rung.text = "  + rung  "
	add_rung.pressed.connect(func() -> void:
		_model.append({"coil": "m_0", "logic": [[{"ref": "m_0", "nc": false}]]})
		_apply()
		_rebuild())
	foot.add_child(add_rung)
	var back := Button.new()
	back.text = "  Back to cabinet (Esc)  "
	back.pressed.connect(close_panel)
	foot.add_child(back)


func open(plant: Plant, cab_name: String) -> void:
	_plant = plant
	_cab = cab_name
	var plc_name := plant.cabinet_plc(cab_name)
	if plc_name == "":
		return
	_plc = plant.sim.get_component(plc_name) as SimPLC
	_model = _plc.program.duplicate(true)
	_title.text = "%s — ladder logic" % plc_name
	_status.text = "contacts: pick a reference, NC for normally-closed · rungs scan top to bottom"
	_rebuild()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	visible = false
	var plant := _plant
	var cab := _cab
	_plant = null
	_plc = null
	if plant != null and plant.cabinet_editor != null:
		plant.cabinet_editor.open(plant, cab)
	else:
		MouseMode.capture()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


## ---- ladder construction --------------------------------------------------

## Only channels backed by mounted I/O cards are offered (memories and
## timers are always in the CPU).
func _refs() -> Array[String]:
	var backed: Dictionary = _plant.cabinet_backed_channels(_cab)
	var out: Array[String] = []
	for i: int in backed["di"]:
		out.append("di_%d" % i)
	for i: int in backed["do"]:
		out.append("do_%d" % i)
	for i in range(_plc.mem.size()):
		out.append("m_%d" % i)
	for i in range(_plc.timer_acc.size()):
		out.append("t_%d" % i)
	return out


func _coils() -> Array[String]:
	var backed: Dictionary = _plant.cabinet_backed_channels(_cab)
	var out: Array[String] = []
	for i: int in backed["do"]:
		out.append("do_%d" % i)
	for i in range(_plc.mem.size()):
		out.append("m_%d" % i)
	for i in range(_plc.timer_acc.size()):
		out.append("t_%d" % i)
	return out


func _rebuild() -> void:
	for old in _rungs_box.get_children():
		old.queue_free()
	_contact_widgets.clear()
	_coil_widgets.clear()
	_acc_labels.clear()
	for rung_index in range(_model.size()):
		_rungs_box.add_child(_rung_row(rung_index))
	if _model.is_empty():
		var hint := Label.new()
		hint.text = "no rungs yet — add one below"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rungs_box.add_child(hint)


func _rung_row(rung_index: int) -> Control:
	var rung: Dictionary = _model[rung_index]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.15)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	row.add_child(_rail())

	var branches_box := VBoxContainer.new()
	branches_box.add_theme_constant_override("separation", 4)
	branches_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(branches_box)
	var branches: Array = rung["logic"]
	for branch_index in range(branches.size()):
		branches_box.add_child(_branch_row(rung_index, branch_index))
	var add_branch := Button.new()
	add_branch.text = "+ parallel branch"
	add_branch.add_theme_font_size_override("font_size", 11)
	add_branch.pressed.connect(func() -> void:
		(_model[rung_index]["logic"] as Array).append([{"ref": "m_0", "nc": false}])
		_apply()
		_rebuild())
	branches_box.add_child(add_branch)

	row.add_child(_coil_section(rung_index))
	row.add_child(_rail())

	var del := Button.new()
	del.text = "✕"
	del.tooltip_text = "delete rung"
	del.pressed.connect(func() -> void:
		_model.remove_at(rung_index)
		_apply()
		_rebuild())
	row.add_child(del)
	return panel


func _rail() -> Control:
	var rail := ColorRect.new()
	rail.color = Color(0.55, 0.57, 0.60)
	rail.custom_minimum_size = Vector2(4, 0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return rail


func _branch_row(rung_index: int, branch_index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var branch: Array = (_model[rung_index]["logic"] as Array)[branch_index]
	for element_index in range(branch.size()):
		row.add_child(_contact(rung_index, branch_index, element_index))
	var add := Button.new()
	add.text = "+⊣⊢"
	add.tooltip_text = "add a series contact"
	add.add_theme_font_size_override("font_size", 11)
	add.pressed.connect(func() -> void:
		((_model[rung_index]["logic"] as Array)[branch_index] as Array).append(
			{"ref": "m_0", "nc": false})
		_apply()
		_rebuild())
	row.add_child(add)
	return row


func _contact(rung_index: int, branch_index: int, element_index: int) -> Control:
	var element: Dictionary = ((_model[rung_index]["logic"] as Array)[branch_index] as Array)[element_index]
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var refs := _refs()
	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", 12)
	for i in range(refs.size()):
		picker.add_item(("[/] " if bool(element["nc"]) else "[ ] ") + refs[i], i)
		if refs[i] == str(element["ref"]):
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		element["ref"] = refs[index]
		_apply()
		_rebuild())
	box.add_child(picker)
	_contact_widgets.append({"node": picker, "ref": str(element["ref"]), "nc": bool(element["nc"])})
	var nc := CheckBox.new()
	nc.text = "NC"
	nc.add_theme_font_size_override("font_size", 11)
	nc.button_pressed = bool(element["nc"])
	nc.toggled.connect(func(on: bool) -> void:
		element["nc"] = on
		_apply()
		_rebuild())
	box.add_child(nc)
	var del := Button.new()
	del.text = "✕"
	del.add_theme_font_size_override("font_size", 10)
	del.pressed.connect(func() -> void:
		var branch: Array = (_model[rung_index]["logic"] as Array)[branch_index]
		branch.remove_at(element_index)
		if branch.is_empty():
			var branches: Array = _model[rung_index]["logic"]
			if branches.size() > 1:
				branches.remove_at(branch_index)
			else:
				_model.remove_at(rung_index)  # last contact of last branch: rung goes
		_apply()
		_rebuild())
	box.add_child(del)
	return box


func _coil_section(rung_index: int) -> Control:
	var rung: Dictionary = _model[rung_index]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var coils := _coils()
	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", 12)
	for i in range(coils.size()):
		picker.add_item("( ) " + coils[i], i)
		if coils[i] == str(rung["coil"]):
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void:
		rung["coil"] = coils[index]
		_apply()
		_rebuild())
	box.add_child(picker)
	_coil_widgets.append({"node": picker, "coil": str(rung["coil"])})
	var coil := str(rung["coil"])
	if coil.begins_with("t_"):
		var t_index := int(coil.split("_")[1])
		var preset := SpinBox.new()
		preset.min_value = 0.1
		preset.max_value = 3600.0
		preset.step = 0.1
		preset.value = _plc.timer_presets[t_index]
		preset.suffix = " s"
		preset.value_changed.connect(func(value: float) -> void:
			_plc.set_timer_preset(t_index, value))
		box.add_child(preset)
		var acc := Label.new()
		acc.add_theme_font_size_override("font_size", 11)
		box.add_child(acc)
		_acc_labels.append({"node": acc, "index": t_index})
	return box


## Apply the model through the kernel's validator, every edit.
func _apply() -> void:
	if _plc == null:
		return
	var error := _plc.set_program(_model)
	_status.text = "program OK — %d rung(s), applied live" % _model.size() if error == "" \
		else "REFUSED: %s" % error


## ---- live power flow ------------------------------------------------------

func _process(delta: float) -> void:
	if not visible or _plc == null:
		return
	_pulse += delta
	if _pulse < 0.1:
		return
	_pulse = 0.0
	for widget in _contact_widgets:
		var passes: bool = _plc._read(str(widget["ref"])) != bool(widget["nc"])
		(widget["node"] as Control).modulate = GREEN if passes else IDLE
	for widget in _coil_widgets:
		var coil := str(widget["coil"])
		var index := int(coil.split("_")[1])
		var driven := false
		if coil.begins_with("do_"):
			driven = _plc.do_ports[index].value > 0.5
		elif coil.begins_with("m_"):
			driven = _plc.mem[index]
		else:
			driven = _plc.timer_run[index]
		(widget["node"] as Control).modulate = GREEN if driven else IDLE
	for widget in _acc_labels:
		var index: int = widget["index"]
		(widget["node"] as Label).text = "acc %.1f / %.1f s%s" % [
			_plc.timer_acc[index], _plc.timer_presets[index],
			"  DONE" if _plc.timer_done[index] else ""]
