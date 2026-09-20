class_name SimRotameter
extends SimComponent
## A variable-area flow indicator: a float in a tapered glass tube,
## riding at the height where the drag balances its weight. A local
## indication and nothing else, no signal out. The tube is a small
## resistance the line pays for the reading. Mirrors
## sim/small_bore.py Rotameter.
##
##     float_frac = Q / Q_range        (clamped 0..1)
##     dP = k * Q^2, k sized so Q_range costs 5 kPa

const RANGE_DROP_PA := 5000.0

var range_lps: float

var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimResistance = null


func _init(name_: String, range_lps_: float = 0.01) -> void:
	super(name_)
	assert(range_lps_ > 0.0, "range_lps must be positive")
	range_lps = range_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("flow_lps", &"flow_lps")
	add_observable("float_frac", &"float_frac")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


var float_frac: float:
	get:
		return clampf(flow_lps / range_lps, 0.0, 1.0)


func k_now() -> float:
	return RANGE_DROP_PA / pow(maxf(range_lps, 1e-12), 2.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimResistance.new(node["inlet"], node["outlet"],
		k_now(), comp_name)) as SimResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _branch != null:
		_branch.set_k(k_now())


func tick(_dt: float) -> void:
	pass
