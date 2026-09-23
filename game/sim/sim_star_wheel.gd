class_name SimStarWheel
extends SimVialCarrier
## An indexing rotary transfer: pockets round a wheel, turned one pocket
## per pulse on its index input. A vial arriving at the infeed station
## (0) drops into the pocket there; a pocket arriving at the outfeed
## station offers its vial on. Stations between are where a needle or a
## capper can stand, and they see the pocket only while the wheel is at
## rest. With nothing wired to index, E indexes it by hand. Mirrors
## sim/vials.py StarWheel.
##
##     station = (pocket + offset) mod N

var pockets: int
var pitch_radius_m: float
var index_s: float
var out_station: int
var offset: int = 0          # indexes completed, mod pockets
var progress: float = 0.0    # 0..1 through the current index, 0 at rest
var moving: bool = false
var indexes: int = 0
var _pocket: Array = []      # SimVial or null, by pocket number
var _was_index: bool = false
var _hand_pulse: bool = false

var infeed: SimInputPort
var outfeed: SimOutputPort
var index: SimInputPort
var power: SimInputPort
var home: SimOutputPort


func _init(name_: String, pockets_: int = 6, pitch_radius_m_: float = 0.12,
		index_s_: float = 0.4, out_station_: int = 3) -> void:
	super(name_)
	assert(pockets_ >= 2, "a star wheel needs at least two pockets")
	pockets = pockets_
	pitch_radius_m = pitch_radius_m_
	index_s = index_s_
	out_station = posmod(out_station_, pockets_)
	_pocket.resize(pockets)
	infeed = add_input("infeed", SimTypes.PortKind.ITEM)
	outfeed = add_output("outfeed", SimTypes.PortKind.ITEM)
	index = add_input("index", SimTypes.PortKind.SIGNAL_DISCRETE)
	power = add_input("power", SimTypes.PortKind.POWER, "24VDC")
	home = add_output("home", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("indexes", &"indexes")


var is_hand_operated: bool:
	get:
		return index.wire_count == 0


func pocket_at(station: int) -> int:
	return posmod(station - offset, pockets)


## Each vial with its station, fractional while the wheel turns.
func vials() -> Array:
	var out: Array = []
	for p in pockets:
		if _pocket[p] != null:
			out.append([_pocket[p], float(posmod(p + offset, pockets)) + progress])
	return out


func vial_near(s: float, tol: float) -> SimVial:
	if moving:
		return null
	var station := roundi(s)
	if absf(s - station) > tol:
		return null
	return _pocket[pocket_at(posmod(station, pockets))]


## E: one index by hand, when nothing is wired to index.
func hand_index() -> void:
	_hand_pulse = true


func item_accepts(_port_name: String, _vial: SimVial) -> bool:
	return not moving and _pocket[pocket_at(0)] == null


func item_put(_port_name: String, vial: SimVial) -> void:
	_pocket[pocket_at(0)] = vial


func item_offer(_port_name: String) -> SimVial:
	if moving:
		return null
	return _pocket[pocket_at(out_station)]


func item_take(port_name: String) -> SimVial:
	var vial := item_offer(port_name)
	if vial != null:
		_pocket[pocket_at(out_station)] = null
	return vial


func tick(dt: float) -> void:
	var pulse := _hand_pulse if is_hand_operated else index.value > 0.5
	_hand_pulse = false
	var edge := pulse and not _was_index
	_was_index = pulse
	if moving:
		progress += dt / index_s
		if progress >= 1.0:
			progress = 0.0
			moving = false
			offset = posmod(offset + 1, pockets)
	elif edge and power.value > 0.5:
		moving = true
		progress = 0.0
		indexes += 1
	home.value = 0.0 if moving else 1.0
	_sense_mounts()


func state_dict() -> Dictionary:
	var saved: Array = []
	for p in pockets:
		saved.append((_pocket[p] as SimVial).to_dict() if _pocket[p] != null else null)
	return {"offset": offset, "progress": progress, "moving": moving, "indexes": indexes,
		"pockets": saved}


func apply_state(state: Dictionary) -> void:
	offset = posmod(int(state.get("offset", 0)), pockets)
	progress = float(state.get("progress", 0.0))
	moving = bool(state.get("moving", false))
	indexes = int(state.get("indexes", indexes))
	var saved: Array = state.get("pockets", [])
	for p in pockets:
		_pocket[p] = SimVial.from_dict(saved[p]) if p < saved.size() and saved[p] != null else null
