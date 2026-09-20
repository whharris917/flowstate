class_name SimBallValve
extends SimComponent
## A quarter-turn hand valve: a lever, open or shut, and half a second
## of travel between. The valve equation while it travels, as the
## block valve, but there is no actuator and no limit switch: the
## lever's own position is the only indication. Mirrors
## sim/small_bore.py BallValve.
##
##     dx/dt = +-100 / stroke_s
##     Q = Cv * (x/100) * sqrt(dP / 1 bar)

var cv_lps: float
var stroke_s: float
var open: bool = false
var position: float = 0.0   # percent of travel

var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimControlResistance = null


func _init(name_: String, cv_lps_: float = 0.5, stroke_s_: float = 0.5) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	assert(stroke_s_ > 0.0, "stroke_s must be positive")
	cv_lps = cv_lps_
	stroke_s = stroke_s_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("position", &"position")
	add_observable("flow_lps", &"flow_lps")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func state() -> String:
	if position >= 99.5:
		return "OPEN"
	if position <= 0.5:
		return "SHUT"
	return "OPENING" if open else "SHUTTING"


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimControlResistance.new(
		node["inlet"], node["outlet"], cv_lps, comp_name)) as SimControlResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _branch != null:
		_branch.cv_lps = cv_lps
		_branch.opening = position / 100.0


func tick(dt: float) -> void:
	position = move_toward(position, 100.0 if open else 0.0, 100.0 * dt / stroke_s)


func state_dict() -> Dictionary:
	return {"open": open, "position": position}


func apply_state(state_: Dictionary) -> void:
	open = bool(state_.get("open", open))
	position = float(state_.get("position", position))
