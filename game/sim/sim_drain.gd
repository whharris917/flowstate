class_name SimDrain
extends SimComponent
## Gravity drain to sewer or recovery: pulls up to rate_lps whenever
## the connected vessel holds liquid and the drain is open, metering
## everything it swallows. Wire vessel level in and draw back to the
## vessel's out_flow. Mirrors sim/components.py Drain.

var rate_lps: float
var is_open: bool = true
var total_l: float = 0.0

var inlet: SimInputPort
var flow_in: SimInputPort
var draw: SimOutputPort


func _init(name_: String, rate_lps_ := 1.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_LEVEL)
	flow_in = add_input("flow_in", SimTypes.PortKind.PROCESS_FLOW)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("total_l", &"total_l")


func tick(dt: float) -> void:
	var rate := rate_lps if (is_open and inlet.value > 0.0) else 0.0
	if dt > 0.0:
		rate = minf(rate, inlet.value / dt)
	draw.value = rate
	# flow_in is a discharge line dumped straight into the sewer.
	total_l += (rate + flow_in.value) * dt


func state_dict() -> Dictionary:
	return {"is_open": is_open, "total_l": total_l}


func apply_state(state: Dictionary) -> void:
	is_open = state.get("is_open", is_open)
	total_l = state.get("total_l", total_l)
