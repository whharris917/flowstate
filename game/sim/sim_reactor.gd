class_name SimReactor
extends SimComponent
## Jacketed stirred reactor: two reactant feed nozzles, analog heat
## duty in (a heat exchanger's duty output), a 480 V agitator without
## which the contents barely react, first-order conversion above the
## reaction temperature, live purity as an analog output, and the
## standard facade outlet pair. Mirrors sim/process.py Reactor.

const AMBIENT_C := 20.0
const REACT_MIN_C := 60.0
const REACT_FULL_C := 100.0
const CP_KJ_PER_KG_K := 4.0
const LOSS_PER_S := 0.0008
const UNMIXED_FACTOR := 0.05

var capacity_l: float
var rate_lps: float
var volume_l: float = 0.0
var product_l: float = 0.0
var temp_c: float = AMBIENT_C
var overflowed_l: float = 0.0
var agitating: bool = false

var inlet_a: SimInputPort
var inlet_b: SimInputPort
var heat_duty: SimInputPort
var power: SimInputPort
var draw: SimInputPort
var level: SimOutputPort
var purity: SimOutputPort


func _init(name_: String, capacity_l_ := 4000.0, rate_lps_ := 6.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0 and rate_lps_ > 0.0, "capacity and rate must be positive")
	capacity_l = capacity_l_
	rate_lps = rate_lps_
	inlet_a = add_input("inlet_a", SimTypes.PortKind.PROCESS_FLOW)
	inlet_b = add_input("inlet_b", SimTypes.PortKind.PROCESS_FLOW)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	purity = add_output("purity", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("temp_c", &"temp_c")
	add_observable("volume_l", &"volume_l")
	add_observable("purity_frac", &"purity_frac")
	add_observable("overflowed_l", &"overflowed_l")


var purity_frac: float:
	get:
		return product_l / volume_l if volume_l > 1e-6 else 0.0


func tick(dt: float) -> void:
	var inflow := (inlet_a.value + inlet_b.value) * dt
	var outflow := minf(draw.value * dt, volume_l + inflow)
	if volume_l > 1e-6:
		product_l -= outflow * purity_frac
	var new_volume := volume_l + inflow - outflow
	if new_volume > capacity_l:
		var spilled := new_volume - capacity_l
		overflowed_l += spilled
		product_l -= spilled * purity_frac
		new_volume = capacity_l
	volume_l = maxf(new_volume, 0.0)
	product_l = maxf(minf(product_l, volume_l), 0.0)

	agitating = power.value > 0.5
	var mass := maxf(volume_l, 50.0)
	temp_c += heat_duty.value / (mass * CP_KJ_PER_KG_K) * dt
	temp_c -= (temp_c - AMBIENT_C) * LOSS_PER_S * dt

	var reactant := volume_l - product_l
	var temp_factor := clampf((temp_c - REACT_MIN_C) / (REACT_FULL_C - REACT_MIN_C), 0.0, 1.0)
	var mix_factor := 1.0 if agitating else UNMIXED_FACTOR
	product_l += minf(reactant, rate_lps * temp_factor * mix_factor * dt)

	level.value = volume_l
	purity.value = purity_frac


func state_dict() -> Dictionary:
	return {"volume_l": volume_l, "product_l": product_l, "temp_c": temp_c,
		"overflowed_l": overflowed_l}


func apply_state(state: Dictionary) -> void:
	volume_l = state.get("volume_l", volume_l)
	product_l = state.get("product_l", product_l)
	temp_c = state.get("temp_c", temp_c)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	level.value = volume_l
	purity.value = purity_frac
