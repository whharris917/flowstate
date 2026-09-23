class_name SimVialMagazine
extends SimComponent
## A tray of empty vials tilted toward the line: it lets one onto the
## track whenever the track has room, no faster than its escapement
## allows. Where vials enter the plant, as a header is where liquid
## does. No power: gravity and a spring escapement. E stops and starts
## it. Mirrors sim/vials.py VialMagazine.

var vial_ml: int = 10
var rate_per_min: float = 60.0
var is_on: bool = true
var supplied: int = 0
var _cooldown: float = 0.0

var outfeed: SimOutputPort


func _init(name_: String, vial_ml_: float = 10.0, rate_per_min_: float = 60.0) -> void:
	super(name_)
	assert(rate_per_min_ > 0.0, "rate_per_min must be positive")
	vial_ml = SimVial.size_of(vial_ml_)
	rate_per_min = rate_per_min_
	outfeed = add_output("outfeed", SimTypes.PortKind.ITEM)
	add_observable("supplied", &"supplied")


func item_offer(_port_name: String) -> SimVial:
	if not is_on or _cooldown > 0.0:
		return null
	return SimVial.new("%s#%d" % [comp_name, supplied + 1], vial_ml)


func item_take(port_name: String) -> SimVial:
	var vial := item_offer(port_name)
	if vial != null:
		supplied += 1
		_cooldown = 60.0 / rate_per_min
	return vial


func tick(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "supplied": supplied, "cooldown": _cooldown}


func apply_state(state: Dictionary) -> void:
	is_on = bool(state.get("is_on", is_on))
	supplied = int(state.get("supplied", supplied))
	_cooldown = float(state.get("cooldown", 0.0))
