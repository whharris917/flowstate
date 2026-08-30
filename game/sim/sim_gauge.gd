class_name SimGauge
extends SimComponent
## Local indicator plus analog transmitter output. Two kinds, both
## honest derivations of existing process state:
##   "level_kpa" — hydrostatic head at a vessel bottom: liters become
##                 height via liters_per_meter, P = rho*g*h in kPa
##   "flow"      — inline flow indication, L/s, read directly
## The reading is mirrored on an analog signal output so it can later
## feed controllers — a gauge today, a transmitter when wired.

const KINDS: Array[String] = ["level_kpa", "flow", "dp_pa"]
const WATER_KPA_PER_M := 9.81

var kind: String
var liters_per_meter: float
var reading: float = 0.0

var process: SimInputPort        # level_kpa / flow kinds
var process_a: SimInputPort      # dp_pa kind
var process_b: SimInputPort
var signal_out: SimOutputPort


func _init(name_: String, kind_: String, liters_per_meter_: float = 45.45) -> void:
	super(name_)
	assert(KINDS.has(kind_), "kind must be level_kpa, flow, or dp_pa")
	assert(liters_per_meter_ > 0.0, "liters_per_meter must be positive")
	kind = kind_
	liters_per_meter = liters_per_meter_
	if kind == "dp_pa":
		process_a = add_input("process_a", SimTypes.PortKind.PROCESS_PRESSURE)
		process_b = add_input("process_b", SimTypes.PortKind.PROCESS_PRESSURE)
	else:
		var port_kind := SimTypes.PortKind.PROCESS_LEVEL if kind == "level_kpa" \
			else SimTypes.PortKind.PROCESS_FLOW
		process = add_input("process", port_kind)
	signal_out = add_output("signal", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("reading", &"reading")


func units() -> String:
	match kind:
		"level_kpa": return "kPa"
		"dp_pa": return "Pa"
	return "L/s"


func full_scale() -> float:
	match kind:
		"level_kpa": return 30.0
		"dp_pa": return 60.0
	return 6.0


func is_wired() -> bool:
	if kind == "dp_pa":
		return process_a.wire_count > 0 and process_b.wire_count > 0
	return process.wire_count > 0


func tick(_dt: float) -> void:
	if kind == "dp_pa":
		reading = process_a.value - process_b.value
	elif kind == "level_kpa":
		reading = process.value / liters_per_meter * WATER_KPA_PER_M
	else:
		reading = process.value
	signal_out.value = reading


func state_dict() -> Dictionary:
	return {}


func apply_state(_state: Dictionary) -> void:
	pass
