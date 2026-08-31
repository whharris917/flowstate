class_name SimDrain
extends SimComponent
## Gravity drain to sewer or recovery: pulls up to rate_lps whenever
## the connected vessel holds liquid and the drain is open, metering
## everything it swallows. Wire vessel level in and draw back to the
## vessel's out_flow. Mirrors sim/components.py Drain.

var rate_lps: float
var is_open: bool = true
var total_l: float = 0.0
var lost_product_l: float = 0.0

var inlet: SimInputPort
var flow_in: SimInputPort
var draw: SimOutputPort


func _init(name_: String, rate_lps_ := 1.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	flow_in = add_input("flow_in", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("total_l", &"total_l")
	add_observable("lost_product_l", &"lost_product_l")


func tick(dt: float) -> void:
	var offered := inlet.stream
	var rate := minf(rate_lps, offered.flow_lps) if is_open else 0.0
	draw.value = rate
	# flow_in is a discharge line dumped straight into the sewer.
	var discharge := flow_in.stream
	total_l += (rate + discharge.flow_lps) * dt
	# A drain meters what it swallows, and the product it swallows is
	# the number that hurts: yield lost to sewer, on a trend.
	lost_product_l += (rate * offered.frac(SimSpecies.PRODUCT)
		+ discharge.species_lps(SimSpecies.PRODUCT)) * dt


func state_dict() -> Dictionary:
	return {"is_open": is_open, "total_l": total_l, "lost_product_l": lost_product_l}


func apply_state(state: Dictionary) -> void:
	is_open = state.get("is_open", is_open)
	total_l = state.get("total_l", total_l)
	lost_product_l = state.get("lost_product_l", lost_product_l)
