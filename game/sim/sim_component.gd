class_name SimComponent
## Base class for everything in the sim graph. Pure data plus tick(dt);
## never a Node. Nodes only render what these classes compute.
##
## Observables are named internal state (wear counters, totals) exposed
## read-only so the historian can record them.

var comp_name: String
var inputs: Dictionary = {}       # String -> SimInputPort
var outputs: Dictionary = {}      # String -> SimOutputPort
var observables: Dictionary = {}  # String -> Callable () -> float


func _init(name_: String) -> void:
	comp_name = name_


func add_input(name_: String, kind: SimTypes.PortKind) -> SimInputPort:
	var port := SimInputPort.new(self, name_, kind)
	inputs[name_] = port
	return port


func add_output(name_: String, kind: SimTypes.PortKind) -> SimOutputPort:
	var port := SimOutputPort.new(self, name_, kind)
	outputs[name_] = port
	return port


func add_observable(name_: String, read: Callable) -> void:
	observables[name_] = read


func tick(_dt: float) -> void:
	push_error("SimComponent.tick is abstract")


## Serializable internal state for save/load. Ports are not saved;
## one scan re-derives them from state.
func state_dict() -> Dictionary:
	return {}


func apply_state(_state: Dictionary) -> void:
	pass
