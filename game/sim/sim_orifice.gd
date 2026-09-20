class_name SimOrifice
extends SimComponent
## A restriction orifice: a plate with a hole, the plant's flow
## limiter. One number, the flow it passes at the reference drop, and
## the square law does the rest. It limits by resistance alone, so
## what gets through still rises with the pressure behind it: a
## limiter, not a regulator. Mirrors sim/small_bore.py Orifice.
##
##     Q = Cv * sqrt(dP / 1 bar)

var cv_lps: float

var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimResistance = null


func _init(name_: String, cv_lps_: float = 0.001) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	cv_lps = cv_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("flow_lps", &"flow_lps")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


static func k_for(cv: float) -> float:
	return SimControlResistance.REF_DROP_PA / pow(maxf(cv, 1e-12), 2.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimResistance.new(node["inlet"], node["outlet"],
		k_for(cv_lps), comp_name)) as SimResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _branch != null:
		_branch.set_k(k_for(cv_lps))


func tick(_dt: float) -> void:
	pass
