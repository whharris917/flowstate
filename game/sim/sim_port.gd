class_name SimPort
## One typed terminal on a component. Ports know their owner's *name*
## for tag paths, never the owner object — a back-reference would make
## a component<->port RefCounted cycle and leak the whole graph.
##
## Scalar kinds use `value`. Material kinds (PROCESS_STREAM and
## PROCESS_SUPPLY) use `stream`, which carries rate, temperature,
## composition and phase together. Keeping them in separate typed fields
## rather than one Variant is what lets the whole kernel stay statically
## typed.

var owner_name: String
var port_name: String
var kind: SimTypes.PortKind
var spec: String = ""   # voltage class for POWER ports ("480VAC", "24VDC")
var value: float = 0.0
var stream: SimStream = null


func _init(owner_name_: String, name_: String, kind_: SimTypes.PortKind,
		spec_: String = "") -> void:
	owner_name = owner_name_
	port_name = name_
	kind = kind_
	spec = spec_
	if SimTypes.is_stream(kind_):
		stream = SimStream.empty()


func path() -> String:
	return owner_name + "." + port_name


## What this port is carrying, for a describe() panel or an I/O menu.
func reading() -> String:
	if SimTypes.is_stream(kind):
		return stream.describe()
	if kind == SimTypes.PortKind.SIGNAL_DISCRETE:
		return "ON" if value > 0.5 else "OFF"
	if kind == SimTypes.PortKind.POWER:
		return ("live " + spec) if value > 0.5 else ("dead " + spec)
	return "%.2f" % value
