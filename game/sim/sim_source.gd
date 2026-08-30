class_name SimSource
extends SimComponent
## Battery-limit utility connection: the honest root of every flow
## path, the way the mains feeder is for power. Availability is
## unlimited — the wider utility system is off-plot — but everything
## drawn through it is metered. Mirrors sim/components.py Source.

const AVAILABLE_L := 1.0e9

var total_l: float = 0.0

var draw: SimInputPort
var level: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	level.value = AVAILABLE_L
	add_observable("total_l", &"total_l")


func tick(dt: float) -> void:
	total_l += draw.value * dt
	level.value = AVAILABLE_L


func state_dict() -> Dictionary:
	return {"total_l": total_l}


func apply_state(state: Dictionary) -> void:
	total_l = state.get("total_l", total_l)
