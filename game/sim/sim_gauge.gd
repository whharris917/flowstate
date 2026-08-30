class_name SimGauge
extends SimComponent
## Local indicator plus analog transmitter output. Two kinds, both
## honest derivations of existing process state:
##   "level_kpa" — hydrostatic head at a vessel bottom: liters become
##                 height via liters_per_meter, P = rho*g*h in kPa
##   "flow"      — inline flow indication, L/s, read directly
## The reading is mirrored on an analog signal output so it can later
## feed controllers — a gauge today, a transmitter when wired.

const KINDS: Array[String] = ["level_kpa", "flow"]
const WATER_KPA_PER_M := 9.81

var kind: String
var liters_per_meter: float
var reading: float = 0.0

var process: SimInputPort
var signal_out: SimOutputPort


func _init(name_: String, kind_: String, liters_per_meter_: float = 45.45) -> void:
	super(name_)
	assert(KINDS.has(kind_), "kind must be level_kpa or flow")
	assert(liters_per_meter_ > 0.0, "liters_per_meter must be positive")
	kind = kind_
	liters_per_meter = liters_per_meter_
	var port_kind := SimTypes.PortKind.PROCESS_LEVEL if kind == "level_kpa" \
		else SimTypes.PortKind.PROCESS_FLOW
	process = add_input("process", port_kind)
	signal_out = add_output("signal", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("reading", &"reading")


func units() -> String:
	return "kPa" if kind == "level_kpa" else "L/s"


func full_scale() -> float:
	return 30.0 if kind == "level_kpa" else 6.0


func tick(_dt: float) -> void:
	if kind == "level_kpa":
		reading = process.value / liters_per_meter * WATER_KPA_PER_M
	else:
		reading = process.value
	signal_out.value = reading


func state_dict() -> Dictionary:
	return {}


func apply_state(_state: Dictionary) -> void:
	pass
