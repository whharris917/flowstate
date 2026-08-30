class_name SimRelay
extends SimComponent
## Electromechanical relay: coil in, normally-open contact out.
## cycles counts energizations — the wear metric that makes chatter
## visible as a number instead of a feeling.

var energized: bool = false
var cycles: int = 0

var coil: SimInputPort
var contact: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	coil = add_input("coil", SimTypes.PortKind.SIGNAL_DISCRETE)
	contact = add_output("contact", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("cycles", func() -> float: return float(cycles))


func tick(_dt: float) -> void:
	var coil_hot := coil.value > 0.5
	if coil_hot and not energized:
		cycles += 1
	energized = coil_hot
	contact.value = 1.0 if energized else 0.0


func state_dict() -> Dictionary:
	return {"energized": energized, "cycles": cycles}


func apply_state(state: Dictionary) -> void:
	energized = state.get("energized", energized)
	cycles = int(state.get("cycles", cycles))
	contact.value = 1.0 if energized else 0.0
