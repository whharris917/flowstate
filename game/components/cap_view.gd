class_name CapView
extends Node3D
## Renders a SimCap: a short flanged spool at the line's own height
## with a blind flange on each nozzle that carries no line. The plant
## tells it which sides are wired (set_capped); a cut pipe shows its
## closed end, a rejoined one a plain coupling. Its anchors come from
## PlantFactory.cap_anchors(line_y).

var cap: SimCap
var line_y := 0.35
var _blinds: Dictionary = {}   # port -> MeshInstance3D
var _bores: Dictionary = {}    # port -> Node3D, the open bore shown on an open end
var _lined: Dictionary = {"a": false, "b": false}
var _plume: VaporPlume = null
var _was_open := false


var bore := 0.07   # the bore of the line on it


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_blinds = {}
	_bores = {}
	_plume = null
	setup(cap, line_y, r)


func setup(cap_: SimCap, line_y_: float, bore_r: float = 0.07) -> void:
	cap = cap_
	line_y = line_y_
	bore = bore_r
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var spool := ViewUtil.cylinder(self, bore_r, 0.36, Vector3(0, line_y, 0), steel)
	spool.rotation_degrees = Vector3(0, 0, 90)
	# Flanges the mates of the line's own, their faces at the anchors (0.18).
	for offset: float in [0.1575, -0.1575]:
		var flange := ViewUtil.cylinder(self, bore_r * 1.8, 0.045, Vector3(offset, line_y, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
	# Blind flanges: a thicker disc with a ring of bolt heads, one each
	# end, shown while that nozzle has no line.
	var dark := ViewUtil.flat(Color(0.30, 0.31, 0.34))
	for port: String in ["a", "b"]:
		var side := -1.0 if port == "a" else 1.0
		var blind := Node3D.new()
		add_child(blind)
		var disc := ViewUtil.cylinder(blind, bore_r * 1.8, 0.035, Vector3(side * 0.1975, line_y, 0), dark)
		disc.rotation_degrees = Vector3(0, 0, 90)
		for i in 8:
			var ang := TAU / 8.0 * i
			var bolt := ViewUtil.cylinder(blind, 0.01, 0.015,
				Vector3(side * 0.222, line_y + cos(ang) * bore_r * 1.4, sin(ang) * bore_r * 1.4), dark)
			bolt.rotation_degrees = Vector3(0, 0, 90)
		_blinds[port] = blind
		# The open bore: a dark disc inset in the flange, shown on an open
		# end instead of the blind.
		var bore := Node3D.new()
		add_child(bore)
		var hole := ViewUtil.cylinder(bore, bore_r * 0.85, 0.02, Vector3(side * 0.175, line_y, 0),
			ViewUtil.flat(Color(0.05, 0.05, 0.06)))
		hole.rotation_degrees = Vector3(0, 0, 90)
		bore.visible = false
		_bores[port] = bore
	_plume = VaporPlume.make(self, Vector3(0.28, line_y - 0.05, 0), 0.5)
	_plume.set_strength(0.0)
	var tag := ViewUtil.label(self, cap.comp_name, Vector3(0, line_y + 0.35, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(0.45, 0.35, 0.3), Vector3(0, line_y, 0))


## Show the blind flange on a nozzle that carries no line — or, while
## the cap is open, the open bore.
func set_capped(port: String, capped: bool) -> void:
	_lined[port] = not capped
	_refresh_ends()


func _refresh_ends() -> void:
	for port: String in ["a", "b"]:
		var free: bool = not _lined[port]
		(_blinds[port] as Node3D).visible = free and not cap.open
		(_bores[port] as Node3D).visible = free and cap.open


func _process(_delta: float) -> void:
	if cap == null:
		return
	if cap.open != _was_open:
		_was_open = cap.open
		_refresh_ends()
	# The spill: a stream off the open end, as strong as the flow.
	if _plume != null:
		_plume.set_strength(clampf(cap.spill_lps() / 4.0, 0.0, 1.0) if cap.open else 0.0)


func describe() -> String:
	var free: Array = []
	for port: String in ["a", "b"]:
		if not _lined[port]:
			free.append(port)
	if cap.open:
		return "%s — OPEN END: spilling %.2f L/s to atmosphere, %.0f L spilled · E caps it" % [
			cap.comp_name, cap.spill_lps(), cap.spilled_l]
	var state := "coupling, both sides lined" if free.is_empty() \
		else "capped on %s — click the blind to run a line from it · E opens it" % " and ".join(free)
	return "%s — pipe cap: %s\n%.2f L/s through" % [cap.comp_name, state, absf(cap.inputs["a"].flow_lps)]


## E: the blind on or off (director, 2026-09-20: "place a cap on the
## end if I choose to do so, otherwise it simply becomes an overflow
## point"). A real edge in the sim, so it sounds.
func use() -> void:
	cap.open = not cap.open
	EquipmentAudio.play_once(self, "res://audio/clunk.wav" if not cap.open else "res://audio/valve_air.wav",
		Vector3(0, line_y, 0))
	_refresh_ends()
