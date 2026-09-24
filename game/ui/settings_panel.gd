class_name SettingsPanel
extends Control
## On-screen options: a time-of-day slider that moves the sun, a
## background music toggle, off by default, and the graphics: a preset
## and every knob under it, with the frame rate live beside them so the
## balance between speed and looks can be read while flipping switches.
## Opens over a dimmed backdrop with the mouse freed; the
## world applies the values and remembers them between sessions.

var on_time_changed: Callable = Callable()
var on_music_changed: Callable = Callable()
var on_graphics_changed: Callable = Callable()   # after any graphics value changes
var graphics: GraphicsSettings = null           # the world's, edited in place

var _slider: HSlider
var _clock: Label
var _music: CheckButton
var _preset: OptionButton
var _fps: Label
var _scale: HSlider
var _scale_label: Label
var _options: Dictionary = {}   # key -> OptionButton
var _checks: Dictionary = {}    # key -> CheckButton


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(PRESET_CENTER)
	# Grow about the centre as the card fills, or its top-left corner
	# sits on the screen's centre and the bottom runs off it.
	card.grow_horizontal = GROW_DIRECTION_BOTH
	card.grow_vertical = GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(560, 0)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var time_row := HBoxContainer.new()
	column.add_child(time_row)
	var time_label := Label.new()
	time_label.text = "Time of day"
	time_label.custom_minimum_size = Vector2(120, 0)
	time_row.add_child(time_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 24.0
	_slider.step = 0.25
	_slider.value = 10.0
	_slider.custom_minimum_size = Vector2(220, 0)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_time)
	time_row.add_child(_slider)
	_clock = Label.new()
	_clock.custom_minimum_size = Vector2(56, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_row.add_child(_clock)

	_music = CheckButton.new()
	_music.text = "Background music"
	_music.button_pressed = false
	_music.toggled.connect(func(on: bool) -> void:
		if on_music_changed.is_valid():
			on_music_changed.call(on))
	column.add_child(_music)

	column.add_child(HSeparator.new())
	_build_graphics(column)

	var hint := Label.new()
	hint.text = "O closes · F7 cycles the preset in play"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	column.add_child(hint)
	_refresh_clock()


## The graphics section: preset and frame rate on one line, the render
## scale, the choice lists in two columns, the switches in two columns.
func _build_graphics(column: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	column.add_child(head)
	var heading := Label.new()
	heading.text = "Graphics"
	heading.add_theme_font_size_override("font_size", 17)
	heading.custom_minimum_size = Vector2(120, 0)
	head.add_child(heading)
	_preset = OptionButton.new()
	for preset: String in GraphicsSettings.PRESET_NAMES:
		_preset.add_item(preset)
	_preset.add_item("Custom")
	_preset.set_item_disabled(GraphicsSettings.PRESET_NAMES.size(), true)
	_preset.custom_minimum_size = Vector2(130, 0)
	_preset.item_selected.connect(_on_preset)
	head.add_child(_preset)
	_fps = Label.new()
	_fps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	head.add_child(_fps)

	var scale_row := HBoxContainer.new()
	column.add_child(scale_row)
	var scale_name := Label.new()
	scale_name.text = "Render scale"
	scale_name.custom_minimum_size = Vector2(120, 0)
	scale_row.add_child(scale_name)
	_scale = HSlider.new()
	_scale.min_value = 0.5
	_scale.max_value = 1.0
	_scale.step = 0.01
	_scale.value = 1.0
	_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale.value_changed.connect(_on_scale)
	scale_row.add_child(_scale)
	_scale_label = Label.new()
	_scale_label.custom_minimum_size = Vector2(56, 0)
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_row.add_child(_scale_label)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for key: String in ["upscaler", "aa", "shadow_size", "shadow_filter", "shadow_distance", "shadow_splits", "vsync"]:
		var name_label := Label.new()
		name_label.text = str(GraphicsSettings.LABELS[key])
		grid.add_child(name_label)
		var option := OptionButton.new()
		for pair: Array in GraphicsSettings.CHOICES[key]:
			option.add_item(str(pair[1]))
		option.custom_minimum_size = Vector2(130, 0)
		option.item_selected.connect(func(idx: int) -> void: _on_option(key, idx))
		grid.add_child(option)
		_options[key] = option

	var switches := GridContainer.new()
	switches.columns = 2
	switches.add_theme_constant_override("h_separation", 10)
	column.add_child(switches)
	for pair: Array in GraphicsSettings.BOOLS:
		var key := str(pair[0])
		var check := CheckButton.new()
		check.text = str(pair[1])
		check.toggled.connect(func(on: bool) -> void: _on_check(key, on))
		switches.add_child(check)
		_checks[key] = check


func set_values(hours: float, music_on: bool) -> void:
	_slider.set_value_no_signal(hours)
	_music.set_pressed_no_signal(music_on)
	_refresh_clock()
	refresh()


## Every graphics control from the values, silently.
func refresh() -> void:
	if graphics == null:
		return
	var preset := graphics.preset_name()
	var idx := GraphicsSettings.PRESET_NAMES.find(preset)
	_preset.select(idx if idx >= 0 else GraphicsSettings.PRESET_NAMES.size())
	_scale.set_value_no_signal(float(graphics.values["scale"]))
	_scale_label.text = "%d%%" % roundi(float(graphics.values["scale"]) * 100.0)
	for key: String in _options:
		(_options[key] as OptionButton).select(graphics.choice_index(key))
	for key: String in _checks:
		(_checks[key] as CheckButton).set_pressed_no_signal(bool(graphics.values[key]))


func toggle() -> void:
	visible = not visible


func _process(_delta: float) -> void:
	if not visible or _fps == null:
		return
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	_fps.text = "%d fps · %.1f ms" % [fps, 1000.0 / maxf(fps, 1.0)]


func _on_preset(idx: int) -> void:
	if graphics == null or idx >= GraphicsSettings.PRESET_NAMES.size():
		return
	graphics.set_preset(GraphicsSettings.PRESET_NAMES[idx])
	_changed()


func _on_scale(value: float) -> void:
	if graphics == null:
		return
	graphics.values["scale"] = value
	_changed()


func _on_option(key: String, idx: int) -> void:
	if graphics == null:
		return
	graphics.values[key] = GraphicsSettings.CHOICES[key][idx][0]
	_changed()


func _on_check(key: String, on: bool) -> void:
	if graphics == null:
		return
	graphics.values[key] = on
	_changed()


func _changed() -> void:
	refresh()
	if on_graphics_changed.is_valid():
		on_graphics_changed.call()


func _on_time(value: float) -> void:
	_refresh_clock()
	if on_time_changed.is_valid():
		on_time_changed.call(value)


func _refresh_clock() -> void:
	var h := int(_slider.value)
	var m := int(round((_slider.value - h) * 60.0))
	_clock.text = "%02d:%02d" % [h % 24, m]
