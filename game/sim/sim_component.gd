class_name SimComponent
## Base class for everything in the sim graph. Pure data plus tick(dt);
## never a Node. Nodes only render what these classes compute.
##
## Observables are named internal state (wear counters, totals) exposed
## read-only so the historian can record them. They are property names,
## not closures: a lambda here would capture self and leak the component
## through a RefCounted cycle.
##
## Hydraulics: every material port is a node in the network. A
## component takes part in the solve in one or both of two ways.
##   * It SETS A PRESSURE at a nozzle. A supply header holds its rated
##     pressure; a vessel holds headspace plus static head. Such a node
##     is a boundary: it absorbs whatever flow arrives and its inventory
##     changes to match.
##   * It CARRIES FLOW between its own nozzles — a pump adding head, a
##     valve resisting. Those become branches.
## A component that does neither has no nozzles and never appears.

var comp_name: String
var inputs: Dictionary = {}       # String -> SimInputPort
var outputs: Dictionary = {}      # String -> SimOutputPort
var observables: Dictionary = {}  # String tag -> StringName property
var material: Dictionary = {}     # String -> SimPort, every PROCESS_MATERIAL port
var node_map: Dictionary = {}     # String -> int, laid out by the simulation


func _init(name_: String) -> void:
	comp_name = name_


func add_input(name_: String, kind: SimTypes.PortKind, spec: String = "") -> SimInputPort:
	var port := SimInputPort.new(comp_name, name_, kind, spec)
	inputs[name_] = port
	if SimTypes.is_material(kind):
		material[name_] = port
	return port


func add_output(name_: String, kind: SimTypes.PortKind, spec: String = "") -> SimOutputPort:
	var port := SimOutputPort.new(comp_name, name_, kind, spec)
	outputs[name_] = port
	if SimTypes.is_material(kind):
		material[name_] = port
	return port


func add_observable(name_: String, property: StringName) -> void:
	observables[name_] = property


## Every material nozzle, by name.
func material_ports() -> Dictionary:
	return material


## Ports the kernel needs that are not something the player pipes: a
## vessel's internal level tap, which an instrument mounted on the
## shell reads through a wire the plant lands for it. Hidden from the
## port menu and given no fitting.
func hidden_ports() -> Array[String]:
	return []


## Groups of nozzles that are one hydraulic node: a tee's (director,
## 2026-09-12: a nozzle takes one line, so joining and splitting is a
## fitting with its own separated nozzles). The layout gives every
## port in a group the same node.
func shared_node_ports() -> Array:
	return []


## Declare internal branches. Called when topology changes, not every
## scan; keep references to what you add so you can adjust it in
## update_hydraulics.
func build_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	pass


## Refresh boundary pressures and branch settings before each solve —
## a vessel's head as it fills, a valve's opening, whether a pump is
## turning.
func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	pass


## Nozzles that observe without carrying anything: a thermowell, an
## analyser tapping. A run to a tap creates no branch, so the
## instrument reads the line without being a hole in it.
func tap_ports() -> Array[String]:
	return []


## Ports whose node carries this component's own supplied stream even
## when nothing moves through it: a vessel's contents tap, which a
## probe on the shell reads. Nothing flows there, so the composition
## pass would otherwise leave it holding whatever it held at start.
func standing_ports() -> Array[String]:
	return []


## What this component pushes out of that nozzle, when it is a source
## of material rather than a pass-through. A vessel supplies its
## contents; a header supplies what it carries. Returning null means
## "whatever the network brings me", which is right for a pump, a
## valve, or a length of pipe.
func supplied_stream(_port_name: String) -> SimStream:
	return null


## ---- items (vials) ------------------------------------------------------
## A carrier of countable items answers four questions about its item
## ports; the simulation moves a vial across an item wire once a scan
## when the source offers one and the destination has room for it.

## The item ready to leave through this output, or null.
func item_offer(_port_name: String) -> SimVial:
	return null


## Whether this input has room for that item now.
func item_accepts(_port_name: String, _vial: SimVial) -> bool:
	return false


## Hand over the offered item; it is no longer this carrier's.
func item_take(_port_name: String) -> SimVial:
	return null


## Receive an item through this input.
func item_put(_port_name: String, _vial: SimVial) -> void:
	pass


func tick(_dt: float) -> void:
	push_error("SimComponent.tick is abstract")


## Serializable internal state for save/load. Ports are not saved;
## one scan re-derives them from state.
func state_dict() -> Dictionary:
	return {}


func apply_state(_state: Dictionary) -> void:
	pass
