class_name SimFloatSwitch
extends SimComponent
## Level switch with mechanical hysteresis, wired to call for fill.
## Contact closes when the level falls to low_l, opens when it rises to
## high_l, holds in between. low_l == high_l is a valid single-setpoint
## switch — the one that chatters.

var low_l: float
var high_l: float
var closed: bool = false

var level_in: SimInputPort
var contact: SimOutputPort


func _init(name_: String, low_l_: float, high_l_: float) -> void:
	super(name_)
	set_band(low_l_, high_l_)
	level_in = add_input("level", SimTypes.PortKind.PROCESS_LEVEL)
	contact = add_output("contact", SimTypes.PortKind.SIGNAL_DISCRETE)


func set_band(low_l_: float, high_l_: float) -> void:
	if low_l_ > high_l_:
		push_error("low_l must be <= high_l")
		return
	low_l = low_l_
	high_l = high_l_


func tick(_dt: float) -> void:
	var level := level_in.value
	if level <= low_l:
		closed = true
	elif level >= high_l:
		closed = false
	contact.value = 1.0 if closed else 0.0


func state_dict() -> Dictionary:
	return {"low_l": low_l, "high_l": high_l, "closed": closed}


func apply_state(state: Dictionary) -> void:
	low_l = state.get("low_l", low_l)
	high_l = state.get("high_l", high_l)
	closed = state.get("closed", closed)
	contact.value = 1.0 if closed else 0.0
