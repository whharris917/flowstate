class_name SimWire
## A validated connection from an output port to an input port.
## Validation happens in Simulation.connect_ports, which is the only
## place wires are made.
##
## A material wire is a real pipe: it has a resistance, so a long or
## thin run genuinely costs pressure. The kernel stays geometry-free —
## whoever builds the run works out the number and hands it over.

## Pa per (L/s)^2 for a short, generously sized run: about 45 kPa at
## 3 L/s, which is what a sensibly sized line costs. Too small a number
## here and nothing in the plant limits anything.
const DEFAULT_K := 5000.0

var src: SimOutputPort
var dst: SimInputPort
var k_pa_per_lps2: float = DEFAULT_K
var branch: SimBranch = null  # the hydraulic branch, for material runs


func _init(src_: SimOutputPort, dst_: SimInputPort) -> void:
	src = src_
	dst = dst_
	dst.wire_count += 1


func is_material() -> bool:
	return SimTypes.is_material(src.kind)


func propagate() -> void:
	# Material does not propagate along a wire: the wire is a pipe, and
	# what moves through it is whatever the network solved.
	if not is_material():
		dst.accumulate_value(src.value)
