class_name SimWire
## A validated connection from an output port to an input port.
## Validation happens in Simulation.connect_ports, which is the only
## place wires are made.

var src: SimOutputPort
var dst: SimInputPort


func _init(src_: SimOutputPort, dst_: SimInputPort) -> void:
	src = src_
	dst = dst_
	dst.wire_count += 1


func propagate() -> void:
	if SimTypes.is_stream(dst.kind):
		dst.accumulate_stream(src.stream)
	else:
		dst.accumulate_value(src.value)
