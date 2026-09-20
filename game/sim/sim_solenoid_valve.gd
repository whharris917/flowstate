class_name SimSolenoidValve
extends SimComponent
## A coil-operated valve: shut until its coil is energized, open while
## it is, and the plunger snaps in a few hundredths of a second.
## Normally closed, so a lost signal is a shut valve. No hand override.
## Mirrors sim/small_bore.py SolenoidValve.
##
##     x -> 100 in SNAP_S energized, -> 0 de-energized
##     Q = Cv * (x/100) * sqrt(dP / 1 bar)

const SNAP_S := 0.05

var cv_lps: float
var position: float = 0.0
var cycles: int = 0

var coil: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimControlResistance = null
var _was_energized: bool = false


func _init(name_: String, cv_lps_: float = 0.3) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	cv_lps = cv_lps_
	coil = add_input("coil", SimTypes.PortKind.SIGNAL_DISCRETE)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("position", &"position")
	add_observable("flow_lps", &"flow_lps")
	add_observable("cycles", &"cycles")


var energized: bool:
	get:
		return coil.value > 0.5


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimControlResistance.new(
		node["inlet"], node["outlet"], cv_lps, comp_name)) as SimControlResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _branch != null:
		_branch.cv_lps = cv_lps
		_branch.opening = position / 100.0


func tick(dt: float) -> void:
	var on := energized
	if on and not _was_energized:
		cycles += 1
	_was_energized = on
	position = move_toward(position, 100.0 if on else 0.0, 100.0 * dt / SNAP_S)


func state_dict() -> Dictionary:
	return {"position": position, "cycles": cycles}


func apply_state(state: Dictionary) -> void:
	position = float(state.get("position", position))
	cycles = int(state.get("cycles", cycles))
	_was_energized = position > 50.0
