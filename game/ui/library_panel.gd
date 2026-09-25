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
	heading.text = ("[b][color=#6bb8fa]LIBRARY[/color][/b]  [color=#8c8e92]equipment, substances, reactions[/color]    "
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
	# After the equipment, the chemistry: every substance the hold packed
	# and every reaction the bench knows, read off the chemistry library.
	ChemLibrary.ensure()
	for key: String in ChemLibrary.keys:
		_types.append("species:" + key)
	for r: Dictionary in ChemLibrary.reactions:
		_types.append("reaction:" + str(r["key"]))


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
	var line := 0
	var selected_line := 0
	for i in _types.size():
		var type_id := _types[i]
		var tier := _tier(type_id)
		if tier != last_tier:
			text += "\n[color=#8c8e92]%s[/color]\n" % tier.to_upper()
			line += 2
			last_tier = tier
		if i == _selected:
			selected_line = line
			text += "[bgcolor=#1f3d5c][color=#ffffff]  %s[/color][/bgcolor]\n" % _label(type_id)
		else:
			text += "[color=#c9cbcd]  %s[/color]\n" % _label(type_id)
		line += 1
	_index.text = text
	_index.scroll_to_paragraph(maxi(selected_line - 8, 0))


func _tier(type_id: String) -> String:
	if type_id.begins_with("species:"):
		return "substances"
	if type_id.begins_with("reaction:"):
		return "reactions"
	return SimLibrary.tier_of(type_id)


func _label(type_id: String) -> String:
	if type_id.begins_with("species:"):
		return ChemLibrary.names[ChemLibrary.index_of(type_id.substr(8))]
	if type_id.begins_with("reaction:"):
		return str(_reaction(type_id.substr(9))["name"])
	return SimLibrary.label_of(type_id)


func _reaction(key: String) -> Dictionary:
	for r: Dictionary in ChemLibrary.reactions:
		if str(r["key"]) == key:
			return r
	return {}


## A substance's page: what the chemistry knows of it, read off the
## library, with its note.
func _draw_species(key: String) -> void:
	var i := ChemLibrary.index_of(key)
	var phase_names := {ChemLibrary.Phase.LIQUID: "liquid", ChemLibrary.Phase.SOLID: "solid",
		ChemLibrary.Phase.DISSOLVED: "only in solution", ChemLibrary.Phase.GAS: "gas"}
	var text := "[font_size=26][b]%s[/b][/font_size]   [color=#8c8e92]%s[/color]\n\n" % [
		ChemLibrary.names[i], ChemLibrary.formulas[i]]
	text += "%s\n\n" % ChemLibrary.notes[i]
	text += "[b][color=#6bb8fa]PROPERTIES[/color][/b]\n"
	text += "  molar mass [b]%.2f g/mol[/b] · density [b]%.3f g/mL[/b] · %s at room temperature\n" % [
		ChemLibrary.molar_mass[i], ChemLibrary.density[i], phase_names[ChemLibrary.phase[i]]]
	text += "  melts [b]%.1f °C[/b] · boils [b]%.1f °C[/b] · heat capacity [b]%.2f J/(g K)[/b]\n" % [
		ChemLibrary.mp[i], ChemLibrary.bp[i], ChemLibrary.cp[i]]
	if ChemLibrary.phase[i] == ChemLibrary.Phase.LIQUID:
		text += "  heat of vaporization [b]%.1f kJ/mol[/b]\n" % ChemLibrary.dh_vap[i]
	if ChemLibrary.phase[i] == ChemLibrary.Phase.SOLID:
		var sw := ChemLibrary.sol_water[i]
		var so := ChemLibrary.sol_organic[i]
		text += "  dissolves in water [b]%s[/b] g per 100 g at 20 °C, [b]%s[/b] at 80 °C; in organic solvent %s and %s\n" % [
			_amount(sw.x), _amount(sw.y), _amount(so.x), _amount(so.y)]
		if ChemLibrary.dh_solution[i] != 0.0:
			text += "  dissolving %s [b]%.1f kJ/mol[/b]\n" % [
				"releases" if ChemLibrary.dh_solution[i] < 0.0 else "takes up", absf(ChemLibrary.dh_solution[i])]
	var f := ChemLibrary.family[i]
	if f >= 0:
		var pkas := PackedStringArray()
		for pka: float in ChemLibrary.family_pka[f]:
			pkas.append("%.2f" % pka)
		text += "  acid-base: the %s family, pKa %s\n" % [ChemLibrary.family_keys[f], ", ".join(pkas)]
	if ChemLibrary.strong_cations[i] > 0.0 or ChemLibrary.strong_anions[i] > 0.0:
		text += "  in solution, fully dissociated: %d positive and %d negative charges per formula unit\n" % [
			int(ChemLibrary.strong_cations[i]), int(ChemLibrary.strong_anions[i])]
	if ChemLibrary.hazards[i] != "":
		text += "  [color=#eab347]hazard: %s[/color]\n" % ChemLibrary.hazards[i]
	text += "\n[b][color=#6bb8fa]TAKES PART IN[/color][/b]\n"
	var any := false
	for r: Dictionary in ChemLibrary.reactions:
		if (r["reactants"] as Dictionary).has(i) or (r["products"] as Dictionary).has(i) \
				or (r["catalysts"] as Dictionary).has(i):
			text += "  %s  [color=#8c8e92]%s[/color]\n" % [r["name"], r["equation"]]
			any = true
	if not any:
		text += "  [color=#8c8e92]nothing the bench knows[/color]\n"
	_page.text = text


static func _amount(g: float) -> String:
	if g >= 10.0:
		return "%d" % int(round(g))
	if g >= 0.1:
		return "%.1f" % g
	return "%.4f" % g


## A reaction's page: its equation, its rate law with its constants, and
## its heat.
func _draw_reaction(key: String) -> void:
	var r := _reaction(key)
	var text := "[font_size=26][b]%s[/b][/font_size]\n\n" % r["name"]
	text += "  [color=#e8d9a0]%s[/color]\n\n" % r["equation"]
	text += "[b][color=#6bb8fa]RATE[/color][/b]\n"
	if bool(r["fast"]):
		text += "  As fast as the two meet: complete within a second stirred, within a few unstirred.\n"
	else:
		var terms := PackedStringArray()
		var orders: Dictionary = r["orders"]
		for s: int in orders:
			terms.append("[%s]%s" % [ChemLibrary.formulas[s], "" if float(orders[s]) == 1.0 else "^%s" % orders[s]])
		var catalysts: Dictionary = r["catalysts"]
		for s: int in catalysts:
			terms.append("[%s]" % ChemLibrary.formulas[s])
		if float(r["h_order"]) != 0.0:
			terms.append("[H+]")
		text += "  r = k · %s\n" % " · ".join(terms)
		text += "  k = %s at 25 °C, activation energy %.0f kJ/mol (so %s at 80 °C)\n" % [
			_sci(float(r["k25"])), float(r["ea"]), _sci(ChemLibrary.rate_constant(r, 80.0))]
		if float(r["equilibrium"]) > 0.0:
			text += "  reversible: it stops where the products over the reactants make K = %.1f\n" % float(r["equilibrium"])
		if not catalysts.is_empty() or float(r["h_order"]) != 0.0:
			text += "  [color=#8c8e92]needs its catalyst: without it, nothing happens[/color]\n"
	text += "\n[b][color=#6bb8fa]HEAT[/color][/b]\n"
	var dh := float(r["dh"])
	text += "  %s [b]%.1f kJ[/b] per mole as written\n" % ["releases" if dh < 0.0 else "takes up", absf(dh)]
	_page.text = text


static func _sci(value: float) -> String:
	if value >= 0.01 and value < 1000.0:
		return "%.3f" % value
	var exponent := int(floor(log(value) / log(10.0)))
	return "%.2f×10^%d" % [value / pow(10.0, exponent), exponent]


func _draw_page(type_id: String) -> void:
	if type_id.begins_with("species:"):
		_draw_species(type_id.substr(8))
		return
	if type_id.begins_with("reaction:"):
		_draw_reaction(type_id.substr(9))
		return
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
