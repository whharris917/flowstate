class_name SimReactor
extends SimComponent
## Jacketed stirred reactor: A + B -> product, plus an impurity.
## Mirrors sim/process.py Reactor.
##
## Two feed nozzles blend into the inventory; heat arrives as an analog
## duty in kW; the agitator is a 480 V load without which the contents
## barely react. Conversion rate climbs with temperature and so does the
## impurity yield, so there is no single right setpoint — running hot
## fills the vessel faster and dirtier. That trade is the whole reason
## to instrument the thing.

const REACT_MIN_C := 60.0
const REACT_FULL_C := 100.0
const LOSS_PER_S := 0.0008
const UNMIXED_FACTOR := 0.05
const MIN_THERMAL_MASS_KG := 50.0
const OUTLET_MAX_LPS := 250.0
const VAPOR_LATENT_KJ_PER_KG := 900.0
## Selectivity: clean at the low end of the window, dirty when pushed.
const IMPURITY_REF_C := 70.0
const IMPURITY_BASE := 0.02
const IMPURITY_SLOPE_PER_K := 0.004

var capacity_l: float
var rate_lps: float
var volume_l: float = 0.0
var temp_c: float = SimStream.AMBIENT_C
var overflowed_l: float = 0.0
var boiled_off_l: float = 0.0
var boiling: bool = false
var agitating: bool = false
var contents: SimStream

var inlet_a: SimInputPort
var inlet_b: SimInputPort
var heat_duty: SimInputPort
var power: SimInputPort
var draw: SimInputPort
var level: SimOutputPort
var outlet: SimOutputPort
var vapor: SimOutputPort
var purity: SimOutputPort
var temp: SimOutputPort


func _init(name_: String, capacity_l_ := 4000.0, rate_lps_ := 6.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0 and rate_lps_ > 0.0, "capacity and rate must be positive")
	capacity_l = capacity_l_
	rate_lps = rate_lps_
	contents = SimStream.pure(SimSpecies.WATER, 0.0, temp_c)
	inlet_a = add_input("inlet_a", SimTypes.PortKind.PROCESS_STREAM)
	inlet_b = add_input("inlet_b", SimTypes.PortKind.PROCESS_STREAM)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_SUPPLY)
	vapor = add_output("vapor", SimTypes.PortKind.PROCESS_STREAM)
	purity = add_output("purity", SimTypes.PortKind.SIGNAL_ANALOG)
	temp = add_output("temp", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("temp_c", &"temp_c")
	add_observable("volume_l", &"volume_l")
	add_observable("purity_frac", &"purity_frac")
	add_observable("impurity_frac", &"impurity_frac")
	add_observable("overflowed_l", &"overflowed_l")
	add_observable("boiled_off_l", &"boiled_off_l")


var purity_frac: float:
	get:
		return contents.frac(SimSpecies.PRODUCT)

var impurity_frac: float:
	get:
		return contents.frac(SimSpecies.IMPURITY)

var product_l: float:
	get:
		return volume_l * purity_frac


## Put a batch in the vessel directly — a commissioning charge, or a
## save being restored.
func charge(volume_l_: float, comp: PackedFloat32Array, temp_c_: float) -> void:
	volume_l = clampf(volume_l_, 0.0, capacity_l)
	temp_c = temp_c_
	contents = SimStream.make(volume_l, temp_c_, comp)
	level.value = volume_l
	purity.value = purity_frac


func impurity_yield() -> float:
	return clampf(IMPURITY_BASE + IMPURITY_SLOPE_PER_K * (temp_c - IMPURITY_REF_C), 0.0, 1.0)


func tick(dt: float) -> void:
	var feed := SimStream.mix(inlet_a.stream, inlet_b.stream)
	var added_l := feed.flow_lps * dt
	var outflow_l := minf(draw.value * dt, volume_l + added_l)

	# Blend the feed in (volume-weighted, same rule as a tank).
	if added_l > 0.0:
		contents = SimStream.mix(contents.with_flow(volume_l), feed.with_flow(added_l))
	var new_volume := volume_l + added_l - outflow_l
	if new_volume > capacity_l:
		overflowed_l += new_volume - capacity_l
		new_volume = capacity_l
	volume_l = maxf(new_volume, 0.0)
	temp_c = contents.temp_c

	# Energy: jacket duty in, first-order ambient loss.
	agitating = power.value > 0.5
	var mass := maxf(volume_l, MIN_THERMAL_MASS_KG)
	var cp := contents.cp_kj_per_kg_k()
	temp_c += heat_duty.value / (mass * cp) * dt
	temp_c -= (temp_c - SimStream.AMBIENT_C) * LOSS_PER_S * dt

	# Reaction, in absolute litres so the volume balance is exact.
	var amounts := SimStream.zero_amounts()
	for i in SimSpecies.COUNT:
		amounts[i] = volume_l * contents.comp[i]

	# An atmospheric vessel cannot go past its bubble point: surplus
	# duty boils the most volatile thing in it instead of raising the
	# temperature. What leaves does so on the vapor nozzle, so the
	# volume balance still closes.
	var boil_c := contents.bubble_point_c()
	var boiled_l := 0.0
	boiling = temp_c > boil_c
	if boiling and volume_l > 0.0:
		var surplus_kj := (temp_c - boil_c) * mass * cp
		temp_c = boil_c
		var lightest := contents.lightest_present()
		if lightest >= 0:
			boiled_l = minf(surplus_kj / VAPOR_LATENT_KJ_PER_KG, amounts[lightest])
			amounts[lightest] -= boiled_l
			volume_l -= boiled_l
			boiled_off_l += boiled_l
			vapor.stream = SimStream.pure(
				lightest, boiled_l / dt if dt > 0.0 else 0.0, boil_c)
	if boiled_l <= 0.0:
		vapor.stream = SimStream.empty()

	# Conversion: gated by temperature and agitation, limited by
	# whichever reagent runs out first. A litre of A and a litre of B
	# make two litres of products, so volume is conserved exactly.
	var temp_factor := clampf(
		(temp_c - REACT_MIN_C) / (REACT_FULL_C - REACT_MIN_C), 0.0, 1.0)
	var mix_factor := 1.0 if agitating else UNMIXED_FACTOR
	var consumed := minf(rate_lps * temp_factor * mix_factor * dt,
		minf(amounts[SimSpecies.REAGENT_A], amounts[SimSpecies.REAGENT_B]))
	if consumed > 0.0:
		var produced := 2.0 * consumed
		var bad := impurity_yield()
		amounts[SimSpecies.REAGENT_A] -= consumed
		amounts[SimSpecies.REAGENT_B] -= consumed
		amounts[SimSpecies.PRODUCT] += produced * (1.0 - bad)
		amounts[SimSpecies.IMPURITY] += produced * bad

	contents = SimStream.make(volume_l, temp_c, SimStream.normalized(amounts))
	level.value = volume_l
	var offered := minf(volume_l / dt, OUTLET_MAX_LPS) if dt > 0.0 else 0.0
	outlet.stream = contents.with_flow(offered)
	purity.value = purity_frac
	temp.value = temp_c


func state_dict() -> Dictionary:
	return {"volume_l": volume_l, "temp_c": temp_c, "overflowed_l": overflowed_l,
		"boiled_off_l": boiled_off_l, "contents": contents.to_dict()}


func apply_state(state: Dictionary) -> void:
	volume_l = state.get("volume_l", volume_l)
	temp_c = state.get("temp_c", temp_c)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	boiled_off_l = state.get("boiled_off_l", boiled_off_l)
	if state.has("contents"):
		contents = SimStream.from_dict(state["contents"]).with_flow(volume_l)
	level.value = volume_l
	purity.value = purity_frac
	temp.value = temp_c
