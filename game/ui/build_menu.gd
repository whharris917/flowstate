class_name BuildMenu
extends VBoxContainer
## The build hotbar: one card per catalog entry — rendered thumbnail,
## number-key badge, name — with the selected card highlighted, and a
## page title above (Tab flips equipment/structure). Pure display; the
## BuildController owns all input.

var _title: Label
var _cards: HBoxContainer
var pick_cb: Callable = Callable()   # (index) — a card clicked
var hovered: int = -1                # the card under the mouse, for a number key to assign


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BEGIN
	position.y -= 48.0
	mouse_filter = MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(0.93, 0.93, 0.90))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_font_size_override("font_size", 15)
	add_child(_title)

	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 8)
	_cards.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_cards)


## `slots` maps a type to its hotbar slot, shown on the card instead
## of the old page number (2026-09-19: the number keys are the hotbar).
func show_page(page_name: String, entries: Array, icons: AssetIcons, selected: int,
		slots: Dictionary = {}) -> void:
	visible = true
	_title.text = page_name
	hovered = -1
	for old in _cards.get_children():
		old.queue_free()
	for i in range(entries.size()):
		_cards.add_child(_card(i, entries[i], icons, i == selected, slots))


func _card(index: int, entry: Dictionary, icons: AssetIcons, selected: bool,
		slots: Dictionary = {}) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and pick_cb.is_valid():
			pick_cb.call(index))
	panel.mouse_entered.connect(func() -> void: hovered = index)
	panel.mouse_exited.connect(func() -> void:
		if hovered == index:
			hovered = -1)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 0.94) if not selected \
		else Color(0.13, 0.22, 0.15, 0.96)
	style.border_color = Color(0.40, 0.42, 0.45) if not selected else Color(0.35, 0.90, 0.50)
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(7)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(84, 84)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = icons.icon(entry["type"])
	thumb.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(thumb)

	var name_label := Label.new()
	var type_id := str(entry["type"])
	name_label.text = ("%d · %s" % [int(slots[type_id]) + 1, entry["label"]]) if slots.has(type_id) \
		else str(entry["label"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(96, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color",
		Color(0.95, 0.97, 0.94) if selected else Color(0.80, 0.81, 0.79))
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	return panel
