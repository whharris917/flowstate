class_name SimGauge
extends SimComponent
## Local indicator plus analog transmitter output. Six kinds, all
## honest derivations of existing process state:
##   "level_kpa" — hydrostatic head at a vessel bottom: liters become
##                 height via liters_per_meter, P = rho*g*h in kPa
##   "flow"      — an inline meter the line runs through: inlet and
##                 outlet nozzles, a little resistance, and the flow
##                 that actually passes as the reading
##   "temp_c"    — a thermowell tapped into a line, reading its temperature
##   "conc_pct"  — an analyser tapped into a line: the percentage of one
##                 species in it. Until one of these is on the line,
##                 nobody can say anything true about quality.
##   "dp_pa"     — differential pressure across two taps, Pa
##   "press_kpa" — a single pressure tap; ports carry Pa, dial in kPa
## The reading is mirrored on an analog signal output so it can later
## feed controllers — a gauge today, a transmitter when wired.
##
## The tapped kinds observe a node without carrying anything: a
## thermowell in a header must not be a hole in it. The flow kind is
## the exception, because a flow element has to sit in the line.

const KINDS: Array[String] = ["level_kpa", "flow", "temp_c", "conc_pct", "dp_pa", "press_kpa"]
const TAP_KINDS: Array[String] = ["temp_c", "conc_pct"]
const WATER_KPA_PER_M := 9.81
## What an inline meter costs the line, Pa per (L/s)^2: a short spool
## with an element in it.
const METER_K := 1000.0

var kind: String
var liters_per_meter: float
var species_index: int = SimSpecies.PRODUCT
var reading: float = 0.0

var process: SimInputPort        # every kind but dp_pa and flow
var process_a: SimInputPort      # dp_pa kind
var process_b: SimInputPort
var inlet: SimInputPort          # flow kind
var outlet: SimOutputPort
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
	elif kind == "flow":
		inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
		outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	else:
		var port_kind := SimTypes.PortKind.PROCESS_LEVEL
		if TAP_KINDS.has(kind):
			port_kind = SimTypes.PortKind.PROCESS_MATERIAL
		elif kind == "press_kpa":
			port_kind = SimTypes.PortKind.PROCESS_PRESSURE
		process = add_input("process", port_kind)
	signal_out = add_output("signal", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("reading", &"reading")


func tap_ports() -> Array[String]:
	if TAP_KINDS.has(kind):
		return ["process"]
	return []


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	if kind == "flow":
		net.add_branch(SimResistance.new(node["inlet"], node["outlet"], METER_K, comp_name))


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
	if kind == "flow":
		return inlet.wire_count > 0
	return process.wire_count > 0


func tick(_dt: float) -> void:
	if kind == "dp_pa":
		reading = process_a.value - process_b.value
	elif kind == "level_kpa":
		reading = process.value / liters_per_meter * WATER_KPA_PER_M
	elif kind == "press_kpa":
		reading = process.value / 1000.0
	elif kind == "flow":
		# Signed: positive is forward through the meter, inlet to outlet.
		reading = inlet.flow_lps
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
	return {"species": species_key(), "liters_per_meter": liters_per_meter}


func apply_state(state: Dictionary) -> void:
	if state.has("species"):
		var index := SimSpecies.index_of(state["species"])
		if index >= 0:
			species_index = index
	liters_per_meter = maxf(float(state.get("liters_per_meter", liters_per_meter)), 1e-6)
