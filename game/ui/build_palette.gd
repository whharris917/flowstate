class_name BuildPalette
extends Control
## The build palette round the card menu, so building does not mean
## tabbing through pages: a rail of page icons down the left, and a hotbar of
## nine slots along the bottom that the number keys pick. Pure display
## with callbacks; the BuildController owns the state and the input.

const PAGE_NAMES: Array[String] = ["EQUIPMENT", "SEPARATION", "INSTRUMENTS", "STRUCTURE",
	"ROUTING", "CONTROL", "UTILITIES", "SMALL BORE", "FILLING LINE"]
const SLOTS := 9

var on_page: Callable = Callable()   # (page: int)
var on_slot: Callable = Callable()   # (slot: int)

var _rail: VBoxContainer
var _rail_buttons: Array[PanelContainer] = []
var _rail_icons: Array[TextureRect] = []
var _hotbar: HBoxContainer
var _slot_panels: Array[PanelContainer] = []
var _slot_icons: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _page_active := -1
var _open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE

	_rail = VBoxContainer.new()
	_rail.set_anchors_and_offsets_preset(PRESET_CENTER_LEFT)
	_rail.grow_vertical = GROW_DIRECTION_BOTH
	_rail.position.x += 10.0
	_rail.mouse_filter = MOUSE_FILTER_IGNORE
	_rail.add_theme_constant_override("separation", 6)
	add_child(_rail)
	for i in PAGE_NAMES.size():
		var panel := PanelContainer.new()
		panel.mouse_filter = MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var column := VBoxContainer.new()
		column.mouse_filter = MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 2)
		panel.add_child(column)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(52, 52)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		column.add_child(icon)
		var label := Label.new()
		label.text = PAGE_NAMES[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.85, 0.86, 0.84))
		label.mouse_filter = MOUSE_FILTER_IGNORE
		column.add_child(label)
		var index := i
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
					and on_page.is_valid():
				on_page.call(index))
		_rail.add_child(panel)
		_rail_buttons.append(panel)
		_rail_icons.append(icon)

	_hotbar = HBoxContainer.new()
	_hotbar.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	_hotbar.grow_horizontal = GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = GROW_DIRECTION_BEGIN
	_hotbar.position.y -= 34.0   # clear of the mode text at the bottom left
	_hotbar.mouse_filter = MOUSE_FILTER_IGNORE
	_hotbar.add_theme_constant_override("separation", 4)
	add_child(_hotbar)
	for i in SLOTS:
		var panel := PanelContainer.new()
		panel.mouse_filter = MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var column := VBoxContainer.new()
		column.mouse_filter = MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 1)
		panel.add_child(column)
		# Small: the number and the icon, no name.
		var badge := Label.new()
		badge.text = str(i + 1)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color(0.95, 0.80, 0.30))
		badge.mouse_filter = MOUSE_FILTER_IGNORE
		column.add_child(badge)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		column.add_child(icon)
		var label := Label.new()
		label.visible = false   # the name lives on the card in the palette
		column.add_child(label)
		var slot := i
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
					and on_slot.is_valid():
				on_slot.call(slot))
		_hotbar.add_child(panel)
		_slot_panels.append(panel)
		_slot_icons.append(icon)
		_slot_labels.append(label)
	_restyle()


## The page the rail highlights, and whether the palette is open (the
## rail brightens; closed, it is a reminder of what Tab opens).
func set_state(page: int, open: bool) -> void:
	_page_active = page
	_open = open
	_rail.visible = open   # the rail shows only with the palette
	_restyle()


## An icon per page: the first entry of each page, rendered.
func set_page_icons(textures: Array) -> void:
	for i in mini(textures.size(), _rail_icons.size()):
		_rail_icons[i].texture = textures[i] as Texture2D


## The hotbar: a type per slot ("" for none), its icon and label, and
## the type the build is set to now.
func set_slots(types: Array, icons: AssetIcons, labels: Dictionary, active_type: String) -> void:
	for i in SLOTS:
		var type_id := str(types[i]) if i < types.size() else ""
		_slot_icons[i].texture = icons.icon(type_id) if type_id != "" else null
		_slot_labels[i].text = str(labels.get(type_id, type_id)) if type_id != "" else "empty"
		_slot_panels[i].tooltip_text = _slot_labels[i].text
		var style := StyleBoxFlat.new()
		var active := type_id != "" and type_id == active_type
		style.bg_color = Color(0.13, 0.22, 0.15, 0.96) if active else Color(0.09, 0.10, 0.12, 0.90)
		style.border_color = Color(0.35, 0.90, 0.50) if active else Color(0.40, 0.42, 0.45)
		style.set_border_width_all(3 if active else 1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(4)
		_slot_panels[i].add_theme_stylebox_override("panel", style)


func _restyle() -> void:
	for i in _rail_buttons.size():
		var style := StyleBoxFlat.new()
		var active := i == _page_active
		var alpha := 0.94 if _open else 0.55
		style.bg_color = Color(0.13, 0.22, 0.15, alpha) if active else Color(0.09, 0.10, 0.12, alpha)
		style.border_color = Color(0.35, 0.90, 0.50) if active else Color(0.40, 0.42, 0.45)
		style.set_border_width_all(3 if active else 1)
		style.set_corner_radius_all(7)
		style.set_content_margin_all(5)
		_rail_buttons[i].add_theme_stylebox_override("panel", style)
		_rail_buttons[i].modulate = Color(1, 1, 1, 1.0 if _open else 0.75)
