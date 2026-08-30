class_name SimPort
## One typed terminal on a component. Ports know their owner's *name*
## for tag paths, never the owner object — a back-reference would make
## a component<->port RefCounted cycle and leak the whole graph.

var owner_name: String
var port_name: String
var kind: SimTypes.PortKind
var spec: String = ""   # voltage class for POWER ports ("480VAC", "24VDC")
var value: float = 0.0


func _init(owner_name_: String, name_: String, kind_: SimTypes.PortKind,
		spec_: String = "") -> void:
	owner_name = owner_name_
	port_name = name_
	kind = kind_
	spec = spec_


func path() -> String:
	return owner_name + "." + port_name
