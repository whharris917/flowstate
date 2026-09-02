class_name SimPort
## One typed terminal on a component. Ports know their owner's *name*
## for tag paths, never the owner object — a back-reference would make
## a component<->port RefCounted cycle and leak the whole graph.
##
## Scalar kinds use `value`. A material nozzle uses `stream` and
## `flow_lps` together: the stream is what is present at the node
## (composition and temperature, with its rate set to |flow_lps|), and
## flow_lps is signed from the component's point of view — positive is
## material coming IN through this nozzle, negative is going out.
## Direction is an answer from the hydraulic solve, not something
## declared, so a nozzle that normally discharges can genuinely run
## backwards. Keeping these in separate typed fields rather than one
## Variant is what lets the whole kernel stay statically typed.

var owner_name: String
var port_name: String
var kind: SimTypes.PortKind
var spec: String = ""   # voltage class for POWER ports ("480VAC", "24VDC")
var value: float = 0.0
var stream: SimStream = null
var flow_lps: float = 0.0
var node: int = -1      # index into the hydraulic network


func _init(owner_name_: String, name_: String, kind_: SimTypes.PortKind,
		spec_: String = "") -> void:
	owner_name = owner_name_
	port_name = name_
	kind = kind_
	spec = spec_
	if SimTypes.is_material(kind_):
		stream = SimStream.empty()


func path() -> String:
	return owner_name + "." + port_name


## What this port is carrying, for a describe() panel or an I/O menu.
func reading() -> String:
	if SimTypes.is_material(kind):
		var text := stream.describe()
		if flow_lps > 1e-9:
			return text + " (in)"
		if flow_lps < -1e-9:
			return text + " (out)"
		return text
	if kind == SimTypes.PortKind.SIGNAL_DISCRETE:
		return "ON" if value > 0.5 else "OFF"
	if kind == SimTypes.PortKind.POWER:
		return ("live " + spec) if value > 0.5 else ("dead " + spec)
	return "%.2f" % value
