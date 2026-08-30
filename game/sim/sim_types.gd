class_name SimTypes
## Shared kinds and combine rules for the signal/process port system.
##
## Kernel divergence from the Python reference: all port values are
## floats; discrete signals carry 0.0 / 1.0. One value type keeps
## GDScript static typing simple, and the historian stores floats anyway.


enum PortKind { SIGNAL_DISCRETE, SIGNAL_ANALOG, PROCESS_FLOW, PROCESS_LEVEL, PROCESS_PRESSURE }


static func is_summing(kind: PortKind) -> bool:
	return kind == PortKind.PROCESS_FLOW  # flows into one header add up


static func is_oring(kind: PortKind) -> bool:
	return kind == PortKind.SIGNAL_DISCRETE  # parallel contacts OR


static func allows_multiple_sources(kind: PortKind) -> bool:
	return is_summing(kind) or is_oring(kind)


static func kind_name(kind: PortKind) -> String:
	return PortKind.keys()[kind].to_lower()
