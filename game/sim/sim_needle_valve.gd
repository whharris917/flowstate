class_name SimNeedleValve
extends SimComponent
## A hand valve with a fine tapered stem: many turns from shut to
## open, so a fraction of a turn is a real adjustment. Linear in the
## turns, the valve equation across it. No actuator and no command:
## the operator turns it, and that is the whole control system.
## Mirrors sim/small_bore.py NeedleValve.
##
##     Q = Cv * (turns_open / turns) * sqrt(dP / 1 bar)

var cv_lps: float
var turns: float
var turns_open: float = 0.0
## Nozzle height above grade, re-derived by the plant from where it
## stands; the static pressure at the valve, not the drop across it.
var elevation_m: float = 0.0
var inlet_pa: float = 0.0
var outlet_pa: float = 0.0

var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimControlResistance = null


func _init(name_: String, cv_lps_: float = 0.005, turns_: float = 10.0) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	assert(turns_ > 0.0, "turns must be positive")
	cv_lps = cv_lps_
	turns = turns_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("position", &"position")
	add_observable("flow_lps", &"flow_lps")


## Percent open.
var position: float:
	get:
		return 100.0 * turns_open / turns


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


## Turn the stem: positive opens, negative shuts, clamped to the
## stem's travel.
func turn(by: float) -> void:
	turns_open = clampf(turns_open + by, 0.0, turns)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimControlResistance.new(
		node["inlet"], node["outlet"], cv_lps, comp_name)) as SimControlResistance


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	if _branch != null:
		_branch.cv_lps = cv_lps
		_branch.opening = turns_open / turns
	var datum := SimHydraulics.static_head_pa(elevation_m)
	inlet_pa = net.pressures[node["inlet"]] - datum
	outlet_pa = net.pressures[node["outlet"]] - datum


func tick(_dt: float) -> void:
	pass


func state_dict() -> Dictionary:
	return {"turns_open": turns_open}


func apply_state(state: Dictionary) -> void:
	turns_open = clampf(float(state.get("turns_open", turns_open)), 0.0, turns)
