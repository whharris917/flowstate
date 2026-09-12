class_name SimBlockValve
extends SimComponent
## On/off block valve with a stroking actuator: one discrete command, a
## fixed travel time from seat to full open, and a trim that follows the
## valve equation the whole way. Mirrors sim/components.py BlockValve.
##
##     Q = Cv * (x/100) * sqrt(dP / dP_ref)
##
## This is the valve a sequence uses — open it, wait for it to travel,
## move to the next step — rather than one a controller throttles. For
## stroke_s after the command changes it is neither open nor shut, and
## a sequence that does not wait for that has a leak in it.

var cv_lps: float
var stroke_s: float
var position: float = 0.0   # percent of travel: 0 shut, 100 open

var open_cmd: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort
# Limit switches on the actuator: dry contacts that make at the ends
# of travel, so a sequence can wait for the valve to report open
# rather than trusting the stroke time.
var zso: SimOutputPort
var zsc: SimOutputPort

const LIMIT_BAND := 2.0   # percent of travel within which a limit contact makes

var _branch: SimControlResistance = null


func _init(name_: String, cv_lps_: float = 20.0, stroke_s_: float = 4.0) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	assert(stroke_s_ > 0.0, "stroke_s must be positive")
	cv_lps = cv_lps_
	stroke_s = stroke_s_
	open_cmd = add_input("open", SimTypes.PortKind.SIGNAL_DISCRETE)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	zso = add_output("zso", SimTypes.PortKind.SIGNAL_DISCRETE)
	zsc = add_output("zsc", SimTypes.PortKind.SIGNAL_DISCRETE)
	zsc.value = 1.0
	add_observable("position", &"position")
	add_observable("flow_lps", &"flow_lps")


var limit_open: bool:
	get:
		return position >= 100.0 - LIMIT_BAND


var limit_closed: bool:
	get:
		return position <= LIMIT_BAND


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


var commanded_open: bool:
	get:
		return open_cmd.value > 0.5


func state() -> String:
	if position >= 99.5:
		return "OPEN"
	if position <= 0.5:
		return "CLOSED"
	return "OPENING" if commanded_open else "CLOSING"


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimControlResistance.new(
		node["inlet"], node["outlet"], cv_lps, comp_name)) as SimControlResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _branch != null:
		_branch.cv_lps = cv_lps
		_branch.opening = position / 100.0


func tick(dt: float) -> void:
	var target := 100.0 if commanded_open else 0.0
	position = move_toward(position, target, 100.0 * dt / stroke_s)
	zso.value = 1.0 if limit_open else 0.0
	zsc.value = 1.0 if limit_closed else 0.0


func state_dict() -> Dictionary:
	return {"position": position}


func apply_state(state_: Dictionary) -> void:
	position = state_.get("position", position)
	zso.value = 1.0 if limit_open else 0.0
	zsc.value = 1.0 if limit_closed else 0.0
