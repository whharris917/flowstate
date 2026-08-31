class_name SimGauge
extends SimComponent
## Local indicator plus analog transmitter output. Six kinds, all
## honest derivations of existing process state:
##   "level_kpa" — hydrostatic head at a vessel bottom: liters become
##                 height via liters_per_meter, P = rho*g*h in kPa
##   "flow"      — inline flow indication, L/s, off the stream in the pipe
##   "temp_c"    — inline temperature, read off the same stream
##   "conc_pct"  — inline composition: the percentage of one species in
##                 the line. The analyser the AI needs before it can say
##                 anything true about quality.
##   "dp_pa"     — differential pressure across two taps, Pa
##   "press_kpa" — a single pressure tap; ports carry Pa, dial in kPa
## The reading is mirrored on an analog signal output so it can later
## feed controllers — a gauge today, a transmitter when wired.

const KINDS: Array[String] = ["level_kpa", "flow", "temp_c", "conc_pct", "dp_pa", "press_kpa"]
const WATER_KPA_PER_M := 9.81

var kind: String
var liters_per_meter: float
var species_index: int = SimSpecies.PRODUCT
var reading: float = 0.0

var process: SimInputPort        # level_kpa / flow kinds
var process_a: SimInputPort      # dp_pa kind
var process_b: SimInputPort
var signal_out: SimOutputPort


func _init(name_: String, kind_: String, liters_per_meter_: float = 45.45,
		species_: String = "product") -> void:
	super(name_)
	assert(KINDS.has(kind_), "kind must be one of " + str(KINDS))
	assert(liters_per_meter_ > 0.0, "liters_per_meter must be positive")
	kind = kind_
	liters_per_meter = liters_per_meter_
	var index := SimSpecies.index_of(species_)
	species_index = index if index >= 0 else SimSpecies.PRODUCT
	if kind == "dp_pa":
		process_a = add_input("process_a", SimTypes.PortKind.PROCESS_PRESSURE)
		process_b = add_input("process_b", SimTypes.PortKind.PROCESS_PRESSURE)
	else:
		var port_kind := SimTypes.PortKind.PROCESS_LEVEL
		if kind == "flow" or kind == "temp_c" or kind == "conc_pct":
			port_kind = SimTypes.PortKind.PROCESS_STREAM
		elif kind == "press_kpa":
			port_kind = SimTypes.PortKind.PROCESS_PRESSURE
		process = add_input("process", port_kind)
	signal_out = add_output("signal", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("reading", &"reading")


func units() -> String:
	match kind:
		"level_kpa": return "kPa"
		"dp_pa": return "Pa"
		"press_kpa": return "kPa"
		"temp_c": return "C"
		"conc_pct": return "%"
	return "L/s"


func full_scale() -> float:
	match kind:
		"level_kpa": return 30.0
		"dp_pa": return 60.0
		"press_kpa": return 60.0
		"temp_c": return 200.0
		"conc_pct": return 100.0
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
	elif kind == "press_kpa":
		reading = process.value / 1000.0
	elif kind == "flow":
		reading = process.stream.flow_lps
	elif kind == "temp_c":
		reading = process.stream.temp_c
	elif kind == "conc_pct":
		reading = process.stream.frac(species_index) * 100.0
	else:
		reading = process.value
	signal_out.value = reading


func species_key() -> String:
	return SimSpecies.key_of(species_index)


func state_dict() -> Dictionary:
	return {"species": species_key()}


func apply_state(state: Dictionary) -> void:
	if state.has("species"):
		var index := SimSpecies.index_of(state["species"])
		if index >= 0:
			species_index = index
