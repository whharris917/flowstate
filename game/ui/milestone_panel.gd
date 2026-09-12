class_name MilestonePanel
extends Control
## The journal (J): the campaign's current milestone, each requirement
## with its live standing read off the plant, what completing it
## unlocks, and the ladder climbed so far. Nothing here is a flag —
## every number is the plant's own.

var _title: Label
var _tier: Label
var _brief: Label
var _rows: VBoxContainer
var _unlocks: Label
var _history: Label


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(PRESET_CENTER)
	card.grow_horizontal = GROW_DIRECTION_BOTH
	card.grow_vertical = GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.12, 0.97)
	style.border_color = Color(0.40, 0.42, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)

	_tier = Label.new()
	_tier.add_theme_font_size_override("font_size", 12)
	_tier.add_theme_color_override("font_color", Color(0.65, 0.85, 0.70))
	column.add_child(_tier)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	column.add_child(_title)
	_brief = Label.new()
	_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief.custom_minimum_size = Vector2(540, 0)
	_brief.add_theme_font_size_override("font_size", 13)
	_brief.add_theme_color_override("font_color", Color(0.82, 0.82, 0.78))
	column.add_child(_brief)
	column.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	column.add_child(HSeparator.new())
	_unlocks = Label.new()
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unlocks.custom_minimum_size = Vector2(540, 0)
	_unlocks.add_theme_font_size_override("font_size", 12)
	column.add_child(_unlocks)
	_history = Label.new()
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.custom_minimum_size = Vector2(540, 0)
	_history.add_theme_font_size_override("font_size", 12)
	_history.add_theme_color_override("font_color", Color(0.60, 0.62, 0.60))
	column.add_child(_history)
	var hint := Label.new()
	hint.text = "J / Esc close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.52, 0.5))
	column.add_child(hint)


func toggle() -> void:
	visible = not visible


func refresh(tracker: Milestones, plant: Plant) -> void:
	for old in _rows.get_children():
		old.queue_free()
	var milestone := tracker.current()
	var climbed: Array[String] = []
	for entry: Dictionary in Milestones.LADDER:
		if tracker.done.has(str(entry["id"])):
			climbed.append(str(entry["title"]))
	if milestone.is_empty():
		_tier.text = "LADDER COMPLETE"
		_title.text = "The plant runs unattended"
		_brief.text = "Every tier is climbed. Everything in the build menu is yours."
		_unlocks.text = ""
	else:
		_tier.text = str(milestone["tier"])
		_title.text = str(milestone["title"])
		_brief.text = str(milestone["brief"])
		for req: Dictionary in milestone["requires"]:
			_rows.add_child(_row(tracker.progress(plant, req)))
		var names: PackedStringArray = PackedStringArray()
		for type_id: String in milestone["unlocks"]:
			names.append(PlantFactory.label_for(type_id))
		_unlocks.text = "Unlocks: " + ", ".join(names) if not names.is_empty() else "The last rung."
	_history.text = ("Climbed: " + ", ".join(PackedStringArray(climbed))) if not climbed.is_empty() \
		else "Nothing climbed yet. %d milestones ahead." % Milestones.LADDER.size()


func _row(p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var done := bool(p["done"])
	var tag := Label.new()
	tag.text = ("✓  " if done else "·  ") + str(p["label"])
	tag.custom_minimum_size = Vector2(300, 0)
	tag.add_theme_font_size_override("font_size", 13)
	if done:
		tag.add_theme_color_override("font_color", Color(0.55, 0.90, 0.60))
	row.add_child(tag)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(140, 14)
	bar.max_value = 100.0
	bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.20, 0.22, 0.24)
	track.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.80, 0.52) if done else Color(0.35, 0.60, 0.85)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var target := float(p["target"])
	bar.value = 100.0 if target <= 0.0 else clampf(100.0 * float(p["value"]) / target, 0.0, 100.0)
	row.add_child(bar)
	var reading := Label.new()
	var unit := str(p["unit"])
	reading.text = "%s / %s %s" % [_fmt(float(p["value"])), _fmt(target), unit]
	reading.add_theme_font_size_override("font_size", 12)
	reading.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	row.add_child(reading)
	return row


func _fmt(v: float) -> String:
	return "%.0f" % v if absf(v - roundf(v)) < 0.05 or absf(v) >= 100.0 else "%.1f" % v


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()
