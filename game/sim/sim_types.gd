class_name SimTypes
## Shared kinds and combine rules for the signal/process port system.
##
## Kernel divergence from the Python reference: scalar port values are
## all floats; discrete signals carry 0.0 / 1.0. One value type keeps
## GDScript static typing simple, and the historian stores floats anyway.
##
## Material is the exception. A stream is rate, temperature, composition
## and phase together, so stream ports carry a SimStream alongside the
## float rather than squeezing it into one. Two kinds keep the type
## safety the old flow/level split had:
##   PROCESS_STREAM — material actually being pushed. Its rate is what
##       is really moving: a pump discharge, a separator's product.
##   PROCESS_SUPPLY — material offered at a nozzle for someone to pull.
##       Its rate is the *most* that could be taken this instant: a tank
##       outlet, a supply header. The consumer decides its own rate and
##       reports it back on a PROCESS_FLOW draw wire.


enum PortKind {
	SIGNAL_DISCRETE,
	SIGNAL_ANALOG,
	PROCESS_STREAM,
	PROCESS_SUPPLY,
	PROCESS_FLOW,
	PROCESS_LEVEL,
	PROCESS_PRESSURE,
	POWER,
}


static func is_stream(kind: PortKind) -> bool:
	return kind == PortKind.PROCESS_STREAM or kind == PortKind.PROCESS_SUPPLY


static func is_summing(kind: PortKind) -> bool:
	return kind == PortKind.PROCESS_FLOW  # draw demands on one header add up


static func is_oring(kind: PortKind) -> bool:
	return kind == PortKind.SIGNAL_DISCRETE  # parallel contacts OR


## Pushed material blends at a tee. Offered material does not: a
## consumer's draw wire goes back to one supplier, so a second supply
## landing on one inlet would have nowhere to report its draw.
static func is_mixing(kind: PortKind) -> bool:
	return kind == PortKind.PROCESS_STREAM


static func allows_multiple_sources(kind: PortKind) -> bool:
	return is_summing(kind) or is_oring(kind) or is_mixing(kind)


static func kind_name(kind: PortKind) -> String:
	return PortKind.keys()[kind].to_lower()


## How a port kind reads to a person rather than to the kernel.
static func kind_label(kind: PortKind) -> String:
	match kind:
		PortKind.SIGNAL_DISCRETE: return "24 V discrete"
		PortKind.SIGNAL_ANALOG: return "4-20 mA analog"
		PortKind.PROCESS_STREAM: return "material (delivered)"
		PortKind.PROCESS_SUPPLY: return "material (offered)"
		PortKind.PROCESS_FLOW: return "draw demand, L/s"
		PortKind.PROCESS_LEVEL: return "level tap, L"
		PortKind.PROCESS_PRESSURE: return "pressure tap, Pa"
		PortKind.POWER: return "electrical supply"
	return kind_name(kind)
