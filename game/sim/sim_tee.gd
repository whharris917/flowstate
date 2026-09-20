class_name SimTee
extends SimComponent
## A pipe fitting whose nozzles are one hydraulic node: pressures
## equal, flows summing to zero, composition the flow-weighted blend
## of what arrives. A splitter has one inlet and three outlets, a
## mixer three inlets and one outlet, on four separated nozzles; an
## unused nozzle is capped. It exists because a nozzle takes one line
## (director, 2026-09-12): joining and splitting is a fitting's job,
## with its own connection points. Mirrors sim/components.py Tee.

var mode: String
## The tee's nominal bore, DN (director, 2026-09-20: "a tee splitter/mixer
## should not change size unless I explicitly reconfigure it"): the view
## is built at it, and a line of another size meets it through a reducer.
var dn: int = 50


func _init(name_: String, mode_: String = "split") -> void:
	super(name_)
	assert(mode_ in ["split", "mix"], "mode must be split or mix")
	mode = mode_
	if mode_ == "split":
		add_input("in", SimTypes.PortKind.PROCESS_MATERIAL)
		for leg in ["a", "b", "c"]:
			add_output(leg, SimTypes.PortKind.PROCESS_MATERIAL)
	else:
		for leg in ["a", "b", "c"]:
			add_input(leg, SimTypes.PortKind.PROCESS_MATERIAL)
		add_output("out", SimTypes.PortKind.PROCESS_MATERIAL)


func shared_node_ports() -> Array:
	return [material_ports().keys()]


func tick(_dt: float) -> void:
	pass


## The legs and what moves in each, for the hover.
func leg_flows() -> String:
	var parts := PackedStringArray()
	for port_name: String in material_ports():
		var port: SimPort = material_ports()[port_name]
		parts.append("%s %.2f" % [port_name, absf(port.flow_lps)])
	return " · ".join(parts)


func state_dict() -> Dictionary:
	return {"dn": dn}


func apply_state(state: Dictionary) -> void:
	dn = int(state.get("dn", dn))
