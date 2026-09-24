class_name CapView
extends Node3D
## Renders a SimCap: a short flanged spool at the line's own height
## with a blind flange on each nozzle that carries no line. The plant
## tells it which sides are wired (set_capped); a cut pipe shows its
## closed end, a rejoined one a plain coupling. Its anchors come from
## PlantFactory.cap_anchors(line_y). An open end shows its bore and
## what leaves it (SpillJet): drops, or a stream leaving along the
## pipe's axis at its real exit speed and falling on a parabola to the
## open vessel the plant found it lands in, or to the floor.

var cap: SimCap
var line_y := 0.35
var _blinds: Dictionary = {}   # port -> MeshInstance3D
var _bores: Dictionary = {}    # port -> Node3D, the open bore shown on an open end
var _lined: Dictionary = {"a": false, "b": false}
var _drip: SpillJet = null
var _landing: SimTank = null
var _was_open := false


var bore := 0.07   # the bore of the line on it


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_blinds = {}
	_bores = {}
	_drip = null
	setup(cap, line_y, r)


func setup(cap_: SimCap, line_y_: float, bore_r: float = 0.07) -> void:
	cap = cap_
	line_y = line_y_
	bore = bore_r
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var spool := ViewUtil.cylinder(self, bore_r, 0.36, Vector3(0, line_y, 0), steel)
	spool.rotation_degrees = Vector3(0, 0, 90)
	# Flanges the mates of the line's own, their faces at the anchors
	# (0.18); on tubing, compression nuts.
	var tube := SmallBoreUtil.is_tube(bore_r)
	for offset: float in [0.1575, -0.1575]:
		if tube:
			var nut := ViewUtil.cylinder(self, maxf(bore_r * 2.2, 0.014), 0.045, Vector3(offset, line_y, 0), steel)
			(nut.mesh as CylinderMesh).radial_segments = 6
			nut.rotation_degrees = Vector3(0, 0, 90)
		else:
			var flange := ViewUtil.cylinder(self, bore_r * 1.8, 0.045, Vector3(offset, line_y, 0), steel)
			flange.rotation_degrees = Vector3(0, 0, 90)
	# Blind flanges: a thicker disc with a ring of bolt heads, one each
	# end, shown while that nozzle has no line. A tube end gets a plug
	# cap instead: a hex nut over the end.
	var dark := ViewUtil.flat(Color(0.30, 0.31, 0.34))
	var blind_r := maxf(bore_r * 2.2, 0.014) if tube else bore_r * 1.8
	for port: String in ["a", "b"]:
		var side := -1.0 if port == "a" else 1.0
		var blind := Node3D.new()
		add_child(blind)
		var disc := ViewUtil.cylinder(blind, blind_r, 0.035, Vector3(side * 0.1975, line_y, 0), dark)
		disc.rotation_degrees = Vector3(0, 0, 90)
		if tube:
			(disc.mesh as CylinderMesh).radial_segments = 6
		else:
			for i in 8:
				var ang := TAU / 8.0 * i
				var bolt := ViewUtil.cylinder(blind, 0.01, 0.015,
					Vector3(side * 0.222, line_y + cos(ang) * bore_r * 1.4, sin(ang) * bore_r * 1.4), dark)
				bolt.rotation_degrees = Vector3(0, 0, 90)
		_blinds[port] = blind
		# The open bore: a dark disc inset in the flange, shown on an open
		# end instead of the blind.
		var bore_node := Node3D.new()
		add_child(bore_node)
		var hole := ViewUtil.cylinder(bore_node, bore_r * 0.85, 0.02, Vector3(side * 0.175, line_y, 0),
			ViewUtil.flat(Color(0.05, 0.05, 0.06)))
		hole.rotation_degrees = Vector3(0, 0, 90)
		bore_node.visible = false
		_bores[port] = bore_node
	_drip = SpillJet.make(self)
	var tag := ViewUtil.label(self, cap.comp_name, Vector3(0, line_y + 0.35, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(0.45, 0.35, 0.3), Vector3(0, line_y, 0))


## Show the blind flange on a nozzle that carries no line — or, while
## the cap is open, the open bore.
func set_capped(port: String, capped: bool) -> void:
	_lined[port] = not capped
	_refresh_ends()


## Which nozzle is the open end: the one with no line (b when both are
## free), and where its face is, in this view's own space.
func open_port() -> String:
	if not _lined["b"]:
		return "b"
	return "a"


func open_end_local() -> Vector3:
	return Vector3(0.175 if open_port() == "b" else -0.175, line_y, 0)


## The plant found (or lost) an open vessel under the end.
func set_landing(tank: SimTank, _end_y: float) -> void:
	_landing = tank


func _refresh_ends() -> void:
	for port: String in ["a", "b"]:
		var free: bool = not _lined[port]
		(_blinds[port] as Node3D).visible = free and not cap.open
		(_bores[port] as Node3D).visible = free and cap.open


func _process(delta: float) -> void:
	if cap == null:
		return
	if cap.open != _was_open:
		_was_open = cap.open
		_refresh_ends()
	if _drip != null:
		# It leaves the open face along the pipe's axis and lands on the
		# liquid in the vessel it falls into, or on the floor the cap
		# stands on.
		var side := 1.0 if open_port() == "b" else -1.0
		var origin := to_global(Vector3(side * 0.19, line_y, 0))
		var axis := global_basis * Vector3(side, 0, 0)
		var landing_y := global_position.y
		if cap.lands():
			landing_y = origin.y - (cap.elevation_m - (cap.catch.elevation_m + cap.catch.depth_m))
		_drip.set_state(cap.spill_lps() if cap.open else 0.0, origin, axis, bore_diameter_m(),
			landing_y, cap.lands(), delta)


## The line's nominal bore in metres, from its drawn radius (0.07 is DN50).
func bore_diameter_m() -> float:
	return bore / 0.07 * 0.05


func describe() -> String:
	var free: Array = []
	for port: String in ["a", "b"]:
		if not _lined[port]:
			free.append(port)
	if cap.open:
		var q := cap.spill_lps()
		var drops := "" if q >= SpillJet.STREAM_LPS or q <= 0.0 else " (%.1f drops a second)" % (q * 1000.0 / SpillJet.DROP_ML)
		if cap.lands():
			return "%s — OPEN END over %s: %s%s falling in, %.2f L delivered · E caps it" % [
				cap.comp_name, cap.catch.comp_name, SimTypes.flow_text(q), drops, cap.delivered_l]
		return "%s — OPEN END: spilling %s%s to the ground, %.1f L spilled · E caps it" % [
			cap.comp_name, SimTypes.flow_text(q), drops, cap.spilled_l]
	var state := "coupling, both sides lined" if free.is_empty() \
		else "capped on %s — click the blind to run a line from it · E opens it" % " and ".join(free)
	return "%s — pipe cap: %s\n%s through" % [cap.comp_name, state, SimTypes.flow_text(absf(cap.inputs["a"].flow_lps))]


## E: the blind on or off; without it the end is an overflow point at
## atmospheric pressure. A real edge in the sim, so it sounds.
func use() -> void:
	cap.open = not cap.open
	EquipmentAudio.play_once(self, "res://audio/clunk.wav" if not cap.open else "res://audio/valve_air.wav",
		Vector3(0, line_y, 0))
	_refresh_ends()
