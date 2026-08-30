class_name SimSource
extends SimComponent
## Supply header: a utility tie-in at the edge of the modeled plant —
## the honest root of every flow path, the way the mains feeder is
## for power. Availability is unlimited (the wider utility system is
## off-plot), but everything drawn through it is metered. Suctions
## wire to "supply" (always wet); pumps and valves return their
## "draw" here for the meter. Mirrors sim/components.py Source.

const AVAILABLE_L := 1.0e9

var total_l: float = 0.0

var draw: SimInputPort
var supply: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	supply = add_output("supply", SimTypes.PortKind.PROCESS_LEVEL)
	supply.value = AVAILABLE_L
	add_observable("total_l", &"total_l")


func tick(dt: float) -> void:
	total_l += draw.value * dt
	supply.value = AVAILABLE_L


func state_dict() -> Dictionary:
	return {"total_l": total_l}


func apply_state(state: Dictionary) -> void:
	total_l = state.get("total_l", total_l)
