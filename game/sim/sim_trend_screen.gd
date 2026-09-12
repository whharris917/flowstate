class_name SimTrendScreen
extends SimComponent
## A trend screen's record: which historian tags it shows and over
## what window. It has no ports and moves nothing; it is a record so it
## places, saves and loads like everything else in the plant, and so
## the right-click CONFIGURE tab can set its pens. GD-only, like the
## other displays: the Python kernel's GUI is the browser.

const MAX_PENS := 4

var tags: Array[String] = ["", "", "", ""]
var window_s: float = 600.0


func _init(name_: String, tags_: Array = [], window_s_: float = 600.0) -> void:
	super(name_)
	for i in MAX_PENS:
		tags[i] = str(tags_[i]) if i < tags_.size() else ""
	window_s = clampf(window_s_, 60.0, 3600.0)


func tick(_dt: float) -> void:
	pass  # a display moves nothing


func pens() -> PackedStringArray:
	var out := PackedStringArray()
	for tag in tags:
		if tag != "":
			out.append(tag)
	return out


func state_dict() -> Dictionary:
	return {"tags": tags.duplicate(), "window_s": window_s}


func apply_state(state: Dictionary) -> void:
	var saved: Array = state.get("tags", [])
	for i in MAX_PENS:
		tags[i] = str(saved[i]) if i < saved.size() else ""
	window_s = clampf(float(state.get("window_s", window_s)), 60.0, 3600.0)
