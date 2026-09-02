class_name SimDrain
extends SimComponent
## Where material leaves the plant: a nozzle, a valve, and a pipe to
## sewer. Mirrors sim/components.py Drain.
##
## It has no magic rate. Its valve has a Cv like any other, and what
## goes down it is whatever the head above it pushes through — so a
## nearly empty vessel drains slowly, as one does. Shut it and it
## passes nothing. It meters everything it swallows, and separately
## the product it swallowed, which is the number that hurts.

var rate_lps: float
var elevation_m: float = 0.0
var is_open: bool = true
var total_l: float = 0.0
var lost_product_l: float = 0.0

var inlet: SimInputPort

var _branch: SimControlResistance = null


func _init(name_: String, rate_lps_: float = 1.0, elevation_m_: float = 0.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	elevation_m = elevation_m_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("total_l", &"total_l")
	add_observable("lost_product_l", &"lost_product_l")
	add_observable("flow_lps", &"flow_lps")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# The far side of the drain valve is the sewer: atmospheric, and it
	# will take whatever it is given.
	var sewer := net.add_node(SimHydraulics.static_head_pa(elevation_m), true)
	_branch = net.add_branch(SimControlResistance.new(
		node["inlet"], sewer, rate_lps, comp_name)) as SimControlResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _branch != null:
		_branch.cv_lps = rate_lps
		_branch.opening = 1.0 if is_open else 0.0


func tick(dt: float) -> void:
	var taken := flow_lps
	total_l += taken * dt
	# The product it swallows is the number that hurts: yield lost to
	# sewer, on a trend, where nothing else will tell you.
	lost_product_l += taken * inlet.stream.frac(SimSpecies.PRODUCT) * dt


func state_dict() -> Dictionary:
	return {"is_open": is_open, "total_l": total_l, "lost_product_l": lost_product_l}


func apply_state(state: Dictionary) -> void:
	is_open = state.get("is_open", is_open)
	total_l = state.get("total_l", total_l)
	lost_product_l = state.get("lost_product_l", lost_product_l)
