class_name SettingsPanel
extends Control
## On-screen options (director, 2026-09-05): a time-of-day slider that
## moves the sun, and a background music toggle, off by default. Opens
## over a dimmed backdrop with the mouse freed; the world applies the
## values and remembers them between sessions.

var on_time_changed: Callable = Callable()
var on_music_changed: Callable = Callable()
var _slider: HSlider
var _clock: Label
var _music: CheckButton


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(PRESET_CENTER)
	card.custom_minimum_size = Vector2(420, 0)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
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

	var hint := Label.new()
	hint.text = "O closes"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	column.add_child(hint)
	_refresh_clock()


func set_values(hours: float, music_on: bool) -> void:
	_slider.set_value_no_signal(hours)
	_music.set_pressed_no_signal(music_on)
	_refresh_clock()


func toggle() -> void:
	visible = not visible


func _on_time(value: float) -> void:
	_refresh_clock()
	if on_time_changed.is_valid():
		on_time_changed.call(value)


func _refresh_clock() -> void:
	var h := int(_slider.value)
	var m := int(round((_slider.value - h) * 60.0))
	_clock.text = "%02d:%02d" % [h % 24, m]
