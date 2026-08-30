class_name SimComponent
## Base class for everything in the sim graph. Pure data plus tick(dt);
## never a Node. Nodes only render what these classes compute.
##
## Observables are named internal state (wear counters, totals) exposed
## read-only so the historian can record them. They are property names,
## not closures: a lambda here would capture self and leak the component
## through a RefCounted cycle.

var comp_name: String
var inputs: Dictionary = {}       # String -> SimInputPort
var outputs: Dictionary = {}      # String -> SimOutputPort
var observables: Dictionary = {}  # String tag -> StringName property


func _init(name_: String) -> void:
	comp_name = name_


func add_input(name_: String, kind: SimTypes.PortKind, spec: String = "") -> SimInputPort:
	var port := SimInputPort.new(comp_name, name_, kind, spec)
	inputs[name_] = port
	return port


func add_output(name_: String, kind: SimTypes.PortKind, spec: String = "") -> SimOutputPort:
	var port := SimOutputPort.new(comp_name, name_, kind, spec)
	outputs[name_] = port
	return port


func add_observable(name_: String, property: StringName) -> void:
	observables[name_] = property


func tick(_dt: float) -> void:
	push_error("SimComponent.tick is abstract")


## Serializable internal state for save/load. Ports are not saved;
## one scan re-derives them from state.
func state_dict() -> Dictionary:
	return {}


func apply_state(_state: Dictionary) -> void:
	pass
