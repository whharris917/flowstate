class_name MainMenu
extends Control
## The title screen (2026-09-11): pick a world. Campaign is the game;
## the blank map is the director's stress test; the sandbox is the
## showcase; the hall is parked but bootable. Worlds are still scenes
## the editor can Play directly, so nothing here is required.

const WORLDS: Array[Dictionary] = [
	{"title": "CAMPAIGN", "note": "Bare ground and a ladder of milestones the plant proves itself. The game.",
		"scene": "res://world/campaign.tscn"},
	{"title": "BLANK MAP", "note": "Bare ground, everything unlocked. Build whatever you like.",
		"scene": "res://world/blank.tscn"},
	{"title": "SHOWCASE", "note": "The commissioned plant: Unit 100 to Unit 500, running.",
		"scene": "res://world/sandbox.tscn"},
	{"title": "THE HALL", "note": "The manufacturing hall and aseptic annex, parked.",
		"scene": "res://world/hall.tscn"},
]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.05, 0.055, 0.065)
	back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(back)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(PRESET_CENTER)
	column.grow_horizontal = GROW_DIRECTION_BOTH
	column.grow_vertical = GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "FLOWSTATE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.88, 0.90, 0.86))
	column.add_child(title)
	var sub := Label.new()
	sub.text = "a process plant, one wire at a time"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	column.add_child(gap)

	var first: Button = null
	for world: Dictionary in WORLDS:
		var button := _world_button(world)
		column.add_child(button)
		if first == null:
			first = button
	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(420, 34)
	quit.add_theme_font_size_override("font_size", 14)
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)
	var hint := Label.new()
	hint.text = "WASD move · E use · B build · C connect · M modify · X remove · J journal · L library · O options · F5/F9 save/load"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.45))
	column.add_child(hint)
	if first != null:
		first.grab_focus()
	# Headless smoke runs boot the menu as the default scene: leave at
	# once, there is nothing to check here.
	if DisplayServer.get_name() == "headless":
		print("[flowstate] menu: %d worlds" % WORLDS.size())
		get_tree().quit()


func _world_button(world: Dictionary) -> Button:
	var button := Button.new()
	button.text = "%s\n%s" % [world["title"], world["note"]]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(420, 54)
	button.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.13)
	style.border_color = Color(0.35, 0.37, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.20, 0.15)
	hover.border_color = Color(0.35, 0.90, 0.50)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(str(world["scene"])))
	return button
