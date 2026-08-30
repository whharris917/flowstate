class_name SimAirCascade
extends SimComponent
## Room-pressure cascade for a cleanroom suite. Rooms hold gauge
## pressure (Pa) fed by constant HVAC supply; air leaks between rooms
## (and to ambient) through doors — a little when closed, a lot when
## open. Open both doors of an airlock and the cascade collapses,
## which the DP gauges will show. One pressure output port per room.
## Semi-implicit integration (own room implicit, neighbors explicit)
## so the huge open-door leak stays numerically stable.
##
## rooms: [{"id", "volume_m3", "supply_lps"}]
## doors: [{"id", "a", "b", "leak_closed", "leak_open"}], a/b room ids
##        or "ambient" (0 Pa).

const PRESSURE_RATE := 10.0  # Pa per (L/s imbalance) per m3, per second

var rooms: Dictionary = {}       # id -> room config
var doors: Dictionary = {}       # id -> door config
var pressures: Dictionary = {}   # id -> Pa
var door_open: Dictionary = {}   # id -> bool

var _ports: Dictionary = {}      # room id -> SimOutputPort


func _init(name_: String, rooms_: Array, doors_: Array) -> void:
	super(name_)
	assert(not rooms_.is_empty(), "cascade needs at least one room")
	for room: Dictionary in rooms_:
		rooms[room["id"]] = room
		pressures[room["id"]] = 0.0
		_ports[room["id"]] = add_output("p_%s" % room["id"], SimTypes.PortKind.PROCESS_PRESSURE)
	for door: Dictionary in doors_:
		doors[door["id"]] = door
		door_open[door["id"]] = false
		for end: String in [door["a"], door["b"]]:
			assert(end == "ambient" or rooms.has(end), "door references unknown room")


func set_door(door_id: String, is_open: bool) -> void:
	if not door_open.has(door_id):
		push_error("unknown door '%s'" % door_id)
		return
	door_open[door_id] = is_open


func is_door_open(door_id: String) -> bool:
	return bool(door_open.get(door_id, false))


func _pressure_of(end: String) -> float:
	return 0.0 if end == "ambient" else float(pressures[end])


func tick(dt: float) -> void:
	var sum_c := {}
	var sum_cp := {}
	for rid: String in rooms:
		sum_c[rid] = 0.0
		sum_cp[rid] = 0.0
	for did: String in doors:
		var door: Dictionary = doors[did]
		var coeff := float(door.get("leak_open", 80.0)) if door_open[did] \
			else float(door.get("leak_closed", 3.0))
		var a: String = door["a"]
		var b: String = door["b"]
		if a != "ambient":
			sum_c[a] += coeff
			sum_cp[a] += coeff * _pressure_of(b)
		if b != "ambient":
			sum_c[b] += coeff
			sum_cp[b] += coeff * _pressure_of(a)
	var new_pressures := {}
	for rid: String in rooms:
		var room: Dictionary = rooms[rid]
		var gain := PRESSURE_RATE / float(room["volume_m3"]) * dt
		new_pressures[rid] = (float(pressures[rid]) + gain * (float(room["supply_lps"]) + float(sum_cp[rid]))) \
			/ (1.0 + gain * float(sum_c[rid]))
	for rid: String in rooms:
		pressures[rid] = new_pressures[rid]
		(_ports[rid] as SimOutputPort).value = new_pressures[rid]


func state_dict() -> Dictionary:
	return {"pressures": pressures.duplicate(), "doors": door_open.duplicate()}


func apply_state(state: Dictionary) -> void:
	var saved_p: Dictionary = state.get("pressures", {})
	for rid: String in saved_p:
		if pressures.has(rid):
			pressures[rid] = float(saved_p[rid])
			(_ports[rid] as SimOutputPort).value = pressures[rid]
	var saved_d: Dictionary = state.get("doors", {})
	for did: String in saved_d:
		if door_open.has(did):
			door_open[did] = bool(saved_d[did])
