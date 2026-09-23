class_name SimVialTrack
extends SimVialCarrier
## A motor-driven belt between guide rails. Every vial rides the belt at
## its speed until something holds it: the vial ahead (they queue nose to
## tail), a stop gate's pin, or the end of the track while nothing
## downstream takes it. Held vials stand while the belt slides under
## them, as on a real accumulation conveyor. Mirrors sim/vials.py
## VialTrack.
##
##     s' = min(s + v dt, limit)
##     limit = s_ahead - (d_ahead + d)/2, a gate at g: g - d/2

var length_m: float
var speed_mps: float
var hand_on: bool = false
var running: bool = false
## [vial, s] pairs, front (largest s) first. Plain Arrays, so a pair
## can be changed in place.
var _vials: Array = []

var infeed: SimInputPort
var outfeed: SimOutputPort
var run: SimInputPort
var power: SimInputPort


func _init(name_: String, length_m_: float = 2.0, speed_mps_: float = 0.1) -> void:
	super(name_)
	assert(length_m_ > 0.0 and speed_mps_ > 0.0, "length_m and speed_mps must be positive")
	length_m = length_m_
	speed_mps = speed_mps_
	infeed = add_input("infeed", SimTypes.PortKind.ITEM)
	outfeed = add_output("outfeed", SimTypes.PortKind.ITEM)
	run = add_input("run", SimTypes.PortKind.SIGNAL_DISCRETE)
	power = add_input("power", SimTypes.PortKind.POWER, "24VDC")
	add_observable("running", &"running")


var is_hand_operated: bool:
	get:
		return run.wire_count == 0


func vials() -> Array:
	return _vials


func vial_near(s: float, tol: float) -> SimVial:
	var best: SimVial = null
	var best_d := INF
	for pair: Array in _vials:
		var d := absf(float(pair[1]) - s)
		if d <= tol and d < best_d:
			best = pair[0]
			best_d = d
	return best


func item_offer(_port_name: String) -> SimVial:
	if _vials.is_empty():
		return null
	var front: Array = _vials[0]
	var vial: SimVial = front[0]
	return vial if float(front[1]) >= length_m - vial.diameter_m / 2.0 - 1e-6 else null


func item_take(port_name: String) -> SimVial:
	var vial := item_offer(port_name)
	if vial != null:
		_vials.pop_front()
	return vial


func item_accepts(_port_name: String, vial: SimVial) -> bool:
	if _vials.is_empty():
		return true
	var rear: Array = _vials[_vials.size() - 1]
	return float(rear[1]) - (rear[0] as SimVial).diameter_m / 2.0 >= vial.diameter_m - 1e-9


func item_put(_port_name: String, vial: SimVial) -> void:
	_vials.append([vial, vial.diameter_m / 2.0])


func tick(dt: float) -> void:
	var commanded := hand_on if is_hand_operated else run.value > 0.5
	running = power.value > 0.5 and commanded
	var step := speed_mps * dt if running else 0.0
	var gates: Array[float] = []
	for device in mounts:
		if device is SimStopGate and (device as SimStopGate).blocking:
			gates.append(device.s_m)
	var ahead: Array = []
	for pair: Array in _vials:
		var vial: SimVial = pair[0]
		var s: float = pair[1]
		var half := vial.diameter_m / 2.0
		var limit := length_m - half
		if not ahead.is_empty():
			limit = float(ahead[1]) - (ahead[0] as SimVial).diameter_m / 2.0 - half
		for g in gates:
			if s + half <= g + 1e-6:
				limit = minf(limit, g - half)
		pair[1] = maxf(s, minf(s + step, limit))
		ahead = pair
	_sense_mounts()


func state_dict() -> Dictionary:
	var saved: Array = []
	for pair: Array in _vials:
		saved.append([(pair[0] as SimVial).to_dict(), pair[1]])
	return {"hand_on": hand_on, "vials": saved}


func apply_state(state: Dictionary) -> void:
	hand_on = bool(state.get("hand_on", hand_on))
	_vials = []
	for pair: Array in state.get("vials", []):
		_vials.append([SimVial.from_dict(pair[0]), float(pair[1])])
