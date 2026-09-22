class_name SimWire
## A validated connection from an output port to an input port.
## Validation happens in Simulation.connect_ports, which is the only
## place wires are made.
##
## A material wire is a real pipe: it has a resistance, so a long or
## thin run genuinely costs pressure. The kernel stays geometry-free —
## whoever builds the run works out the number and hands it over.

## Pa per (L/s)^2 until whoever made the wire prices it. In the game every
## drawn line is priced by its length and size as soon as it is laid
## (Plant._sync_line_resistance, SimHydraulics.pipe_k); this default is
## what the kernel's own self-checks, built in code with no geometry, use.
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
