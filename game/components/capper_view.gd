class_name CapperView
extends VialPartView
## Renders a SimCapper: a column beside the line at +z, a crosshead over
## the spot, and the capping head that comes down onto the vial while it
## crimps and goes back up when done, with a cap chute feeding the head.
## The origin is the head's point over the line. A servo as the head
## comes down, a clunk as the crimp closes.

const HEAD_Y := 1.08       # the head at rest
const COLUMN_Z := 0.24

var capper: SimCapper
var _head: Node3D
var _last_caps := 0
var _was_working := false


func _build() -> void:
	capper = record as SimCapper
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	var blue := ViewUtil.flat(Color(0.20, 0.34, 0.55))
	ViewUtil.box(self, Vector3(0.05, HEAD_Y + 0.15, 0.05), Vector3(0, (HEAD_Y + 0.15) / 2.0, COLUMN_Z), steel)
	ViewUtil.cylinder(self, 0.08, 0.012, Vector3(0, 0.006, COLUMN_Z), dark)
	ViewUtil.box(self, Vector3(0.06, 0.05, COLUMN_Z + 0.04), Vector3(0, HEAD_Y + 0.12, COLUMN_Z / 2.0), steel)
	ViewUtil.box(self, Vector3(0.08, 0.1, 0.06), Vector3(0, HEAD_Y + 0.2, 0), blue)
	ViewUtil.box(self, Vector3(0.12, 0.14, 0.02), Vector3(0, 0.57, COLUMN_Z + 0.01), dark)
	# The cap chute, from a hopper on the column down to the head.
	var chute := ViewUtil.box(self, Vector3(0.02, 0.02, 0.2), Vector3(0.05, HEAD_Y + 0.08, 0.11), steel)
	chute.rotation_degrees = Vector3(-25, 0, 0)
	ViewUtil.box(self, Vector3(0.09, 0.07, 0.09), Vector3(0.05, HEAD_Y + 0.14, COLUMN_Z - 0.02), steel)
	_head = Node3D.new()
	add_child(_head)
	ViewUtil.cylinder(_head, 0.004, 0.12, Vector3(0, 0.06, 0), steel)
	ViewUtil.cylinder(_head, 0.022, 0.035, Vector3(0, 0.0, 0), dark)
	_head.position.y = HEAD_Y
	var tag := ViewUtil.label(self, capper.comp_name, Vector3(0, HEAD_Y + 0.35, 0))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.1, 0.3, COLUMN_Z + 0.06), Vector3(0, HEAD_Y + 0.1, COLUMN_Z / 2.0))
	_last_caps = capper.caps_used


func _process(_delta: float) -> void:
	if capper == null:
		return
	# Down onto the vial while crimping: a quarter of the stroke to come
	# down, the rest pressing.
	var h: float = vial_row()[1]
	var low := DECK + BELT + h + 0.018
	var down := clampf(capper.progress * 4.0, 0.0, 1.0) if capper.working else 0.0
	_head.position.y = lerpf(HEAD_Y, low, down)
	if capper.working and not _was_working:
		EquipmentAudio.play_once(self, "res://audio/servo.wav", Vector3(0, HEAD_Y, 0), -14.0, 1.7)
	_was_working = capper.working
	if capper.caps_used != _last_caps:
		_last_caps = capper.caps_used
		EquipmentAudio.play_once(self, "res://audio/clunk.wav", Vector3(0, HEAD_Y, 0), -16.0, 2.0)


func describe() -> String:
	var where := " at %s" % capper.host if capper.host != "" else " · not over a line"
	var state := "CAPPING" if capper.working else ("vial under it capped" if capper.capped.value > 0.5 else "idle")
	if capper.power.value <= 0.5:
		state += " · NO 24 V"
	return "%s — capper%s\n%s · %d caps used" % [capper.comp_name, where, state, capper.caps_used]
