class_name LibraryPanel
extends Control
## The in-game equipment library. Open with L.
##
## One page per piece of equipment: what it is, what goes in and out of
## it, the equations relating them, what you size when you place it, and
## what the model deliberately does not do.
##
## The port table is not written down anywhere. SimLibrary reads it off
## a real constructed record, so a page always shows the I/O the game
## actually has and cannot drift into describing a machine that is not
## the machine. Everything else is hand-authored prose in SimLibraryData.

const COL_BG := Color(0.07, 0.075, 0.08, 0.96)
const COL_PANEL := Color(0.115, 0.12, 0.13)
const COL_INK := Color(0.90, 0.91, 0.90)
const COL_MUTED := Color(0.55, 0.56, 0.58)
const COL_ACCENT := Color(0.42, 0.72, 0.98)
const COL_WARN := Color(0.92, 0.70, 0.28)
const COL_IN := Color(0.38, 0.78, 0.55)
const COL_OUT := Color(0.95, 0.62, 0.32)

var _index: RichTextLabel
var _page: RichTextLabel
var _types: Array[String] = []
var _selected: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	visible = false
	mouse_filter = MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = COL_BG
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var heading := RichTextLabel.new()
	heading.bbcode_enabled = true
	heading.fit_content = true
	heading.custom_minimum_size.y = 46
	heading.text = ("[b][color=#6bb8fa]EQUIPMENT LIBRARY[/color][/b]    "
		+ "[color=#8c8e92]up/down select · page up/down scroll · "
		+ "L or Esc to close[/color]")
	rows.add_child(heading)

	var split := HSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.split_offset = 260
	rows.add_child(split)

	_index = RichTextLabel.new()
	_index.bbcode_enabled = true
	_index.scroll_following = false
	_index.custom_minimum_size.x = 250
	split.add_child(_index)

	_page = RichTextLabel.new()
	_page.bbcode_enabled = true
	_page.selection_enabled = true
	_page.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(_page)

	_types = SimLibrary.type_ids()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


## Close from inside the panel (Esc), handing control back to the world.
func close() -> void:
	visible = false
	var world := get_tree().current_scene as WorldBase
	if world != null and world.player != null:
		world.player.input_locked = false
		MouseMode.capture()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_step(-1)
		get_viewport().set_input_as_handled()


func _step(delta: int) -> void:
	if _types.is_empty():
		return
	_selected = wrapi(_selected + delta, 0, _types.size())
	_refresh()


func _refresh() -> void:
	_draw_index()
	_draw_page(_types[_selected])
	_page.scroll_to_line(0)


func _draw_index() -> void:
	var text := ""
	var last_tier := ""
	for i in _types.size():
		var type_id := _types[i]
		var tier := SimLibrary.tier_of(type_id)
		if tier != last_tier:
			text += "\n[color=#8c8e92]%s[/color]\n" % tier.to_upper()
			last_tier = tier
		if i == _selected:
			text += "[bgcolor=#1f3d5c][color=#ffffff]  %s[/color][/bgcolor]\n" % \
				SimLibrary.label_of(type_id)
		else:
			text += "[color=#c9cbcd]  %s[/color]\n" % SimLibrary.label_of(type_id)
	_index.text = text


func _draw_page(type_id: String) -> void:
	var label := SimLibrary.label_of(type_id)
	var model := SimLibrary.title_of(type_id)
	var text := "[font_size=26][b]%s[/b][/font_size]   [color=#8c8e92]%s[/color]\n" % [
		label, SimLibrary.tier_of(type_id)]
	# Several configurations can share one model, and one page.
	if model != label:
		text += "[color=#8c8e92]%s[/color]\n" % model
	text += "\n"
	text += "%s\n\n" % SimLibrary.summary_of(type_id)

	# --- ports: read off a real record, never written down ----------
	text += "[b][color=#6bb8fa]CONNECTIONS[/color][/b]\n"
	var rows := SimLibrary.port_rows(type_id)
	if rows.is_empty():
		text += "[color=#8c8e92]none[/color]\n"
	for row: Dictionary in rows:
		var arrow := "[color=#61c78c]in [/color]" if row["direction"] == "in" \
			else "[color=#f29e52]out[/color]"
		var spec := str(row["spec"])
		var kind := str(row["kind_label"]) + (" " + spec if spec != "" else "")
		text += "  %s  [b]%s[/b]  [color=#8c8e92]%s[/color]\n" % [
			arrow, row["name"], kind]
		if str(row["meaning"]) != "":
			text += "        [color=#c9cbcd]%s[/color]\n" % row["meaning"]
	text += "\n"

	# --- equations ---------------------------------------------------
	var equations := SimLibrary.equations_of(type_id)
	if not equations.is_empty():
		text += "[b][color=#6bb8fa]GOVERNING EQUATIONS[/color][/b]\n"
		for entry: Array in equations:
			# No [code] tag: its mono font clips the underscores that half
			# these variable names are built out of.
			text += "  [color=#e8d9a0]%s[/color]\n" % entry[0]
			text += "        [color=#c9cbcd]%s[/color]\n" % entry[1]
		text += "\n"

	# --- what you size when you place it -----------------------------
	var params := SimLibrary.params_of(type_id)
	if not params.is_empty():
		text += "[b][color=#6bb8fa]SIZING[/color][/b]\n"
		for entry: Array in params:
			text += "  [b]%s[/b] [color=#8c8e92]%s[/color]  " % [entry[0], entry[1]]
			text += "[color=#8c8e92](default %s)[/color]\n" % entry[2]
			text += "        [color=#c9cbcd]%s[/color]\n" % entry[3]
		text += "\n"

	# --- historian tags ----------------------------------------------
	var observables := SimLibrary.observable_names(type_id)
	if not observables.is_empty():
		text += "[b][color=#6bb8fa]RECORDED[/color][/b]\n"
		text += "  [color=#c9cbcd]%s[/color]\n" % ", ".join(observables)
		text += "  [color=#8c8e92]Every output is historized too. Material "
		text += "lines record rate, temperature, phase and the fraction of "
		text += "each species.[/color]\n\n"

	# --- the honest part ---------------------------------------------
	var assumptions := SimLibrary.assumptions_of(type_id)
	if not assumptions.is_empty():
		text += "[b][color=#eab347]WHAT THIS MODEL DOES NOT DO[/color][/b]\n"
		for note: String in assumptions:
			text += "  [color=#c9cbcd]· %s[/color]\n" % note
	_page.text = text
