class_name SimTypes
## Shared kinds and combine rules for the signal/process port system.
##
## Kernel divergence from the Python reference: scalar port values are
## all floats; discrete signals carry 0.0 / 1.0. One value type keeps
## GDScript static typing simple, and the historian stores floats anyway.
##
## Material is the exception. A nozzle carries a SimStream (rate,
## temperature, composition, phase) alongside a signed flow, and there
## is exactly ONE material kind, because with pressure driving flow
## there is nothing left for a second one to protect against: any
## nozzle may legitimately be piped to any other, and which way
## material goes is solved, not declared. Each material port is a node
## in the hydraulic network; each wire between two of them is a pipe
## run with a resistance.


enum PortKind {
	SIGNAL_DISCRETE,
	SIGNAL_ANALOG,
	PROCESS_MATERIAL,
	PROCESS_LEVEL,
	PROCESS_PRESSURE,
	POWER,
}


static func is_material(kind: PortKind) -> bool:
	return kind == PortKind.PROCESS_MATERIAL


static func is_oring(kind: PortKind) -> bool:
	return kind == PortKind.SIGNAL_DISCRETE  # parallel contacts OR


## Discrete signals OR together (parallel contacts). Material does not
## combine on the port at all: several runs landing on one nozzle is a
## tee, and the network resolves it by solving the node.
static func allows_multiple_sources(kind: PortKind) -> bool:
	return is_oring(kind) or is_material(kind)


static func kind_name(kind: PortKind) -> String:
	return PortKind.keys()[kind].to_lower()


## How a port kind reads to a person rather than to the kernel.
static func kind_label(kind: PortKind) -> String:
	match kind:
		PortKind.SIGNAL_DISCRETE: return "24 V discrete"
		PortKind.SIGNAL_ANALOG: return "4-20 mA analog"
		PortKind.PROCESS_MATERIAL: return "material nozzle"
		PortKind.PROCESS_LEVEL: return "level tap, L"
		PortKind.PROCESS_PRESSURE: return "pressure tap, Pa"
		PortKind.POWER: return "electrical supply"
	return kind_name(kind)
