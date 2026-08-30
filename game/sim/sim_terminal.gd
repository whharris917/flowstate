class_name SimTerminal
extends SimComponent
## One terminal block of a strip: in to out, one scan late — the
## honest cost of landing a wire. kind "discrete" or "analog".
## Mirrors sim/components.py Terminal.

var kind: String

var t_in: SimInputPort
var t_out: SimOutputPort


func _init(name_: String, kind_ := "discrete") -> void:
	super(name_)
	assert(kind_ in ["discrete", "analog"], "kind must be discrete or analog")
	kind = kind_
	var port_kind := SimTypes.PortKind.SIGNAL_DISCRETE if kind == "discrete" \
		else SimTypes.PortKind.SIGNAL_ANALOG
	t_in = add_input("in", port_kind)
	t_out = add_output("out", port_kind)


func tick(_dt: float) -> void:
	t_out.value = t_in.value
