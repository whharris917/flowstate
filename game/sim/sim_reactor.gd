class_name SimReactor
extends SimComponent
## Jacketed stirred reactor: A + B -> product, plus an impurity.
## Mirrors sim/process.py Reactor.
##
## A vessel, so its nozzles behave like one: the feeds enter at the
## top against headspace pressure, and the outlet at the bottom
## carries the static head of the batch standing above it. Heat
## arrives as an analog duty in kW; the agitator is a 480 V load
## without which the contents barely react. Conversion rate climbs
## with temperature and so does the impurity yield, so there is no
## single right setpoint — running hot fills the vessel faster and
## dirtier. That trade is the whole reason to instrument the thing.

const REACT_MIN_C := 60.0
const REACT_FULL_C := 100.0
const LOSS_PER_S := 0.0008
const UNMIXED_FACTOR := 0.05
const MIN_THERMAL_MASS_KG := 50.0
const VAPOR_LATENT_KJ_PER_KG := 900.0
## Selectivity: clean at the low end of the window, dirty when pushed.
const IMPURITY_REF_C := 70.0
const IMPURITY_BASE := 0.02
const IMPURITY_SLOPE_PER_K := 0.004
## The nozzle and its stub, Pa per (L/s)^2.
const NOZZLE_K := 800.0
## Flow the bottom nozzle passes at the reference drop.
const OUTLET_CV_LPS := 20.0
## Depth over which the bottom nozzle uncovers as the level falls past
## it.
const UNCOVER_M := 0.03

var capacity_l: float
var rate_lps: float
var height_m: float = 2.4
var elevation_m: float = 0.0
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
var outlet: SimOutputPort
var level: SimOutputPort
var purity: SimOutputPort
var temp: SimOutputPort

var _roof: int = -1
var _floor: int = -1
var _outlet_branch: SimControlResistance = null


func _init(name_: String, capacity_l_: float = 4000.0, rate_lps_: float = 6.0,
		height_m_: float = 2.4, elevation_m_: float = 0.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0 and rate_lps_ > 0.0, "capacity and rate must be positive")
	capacity_l = capacity_l_
	rate_lps = rate_lps_
	height_m = height_m_
	elevation_m = elevation_m_
	contents = SimStream.pure(SimSpecies.WATER, 0.0, temp_c)
	inlet_a = add_input("inlet_a", SimTypes.PortKind.PROCESS_MATERIAL)
	inlet_b = add_input("inlet_b", SimTypes.PortKind.PROCESS_MATERIAL)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
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

var cross_section_m2: float:
	get:
		return (capacity_l / 1000.0) / maxf(height_m, 1e-9)

var depth_m: float:
	get:
		return (volume_l / 1000.0) / maxf(cross_section_m2, 1e-9)


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


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_roof = net.add_node(0.0, true)
	_floor = net.add_node(0.0, true)
	for feed: String in ["inlet_a", "inlet_b"]:
		net.add_branch(SimCheckResistance.new(node[feed], _roof, NOZZLE_K,
			comp_name + "." + feed))
	_outlet_branch = net.add_branch(SimControlResistance.new(
		_floor, node["outlet"], OUTLET_CV_LPS, comp_name + ".outlet")) as SimControlResistance


func update_hydraulics(net: SimNetwork, _node: Dictionary) -> void:
	# The headspace holds no pressure: the vessel is atmospheric.
	net.set_pressure(_roof, SimHydraulics.static_head_pa(elevation_m + height_m), true)
	net.set_pressure(_floor, SimHydraulics.static_head_pa(elevation_m + depth_m), true)
	var filling := _outlet_branch.flow_lps < -1e-9
	_outlet_branch.opening = 1.0 if filling else minf(depth_m / UNCOVER_M, 1.0)


func supplied_stream(_port_name: String) -> SimStream:
	return contents  # the caller sets the rate


func tick(dt: float) -> void:
	var arriving := SimStream.empty()
	var leaving_lps := 0.0
	for port: SimPort in [inlet_a, inlet_b, outlet]:
		if port.flow_lps > 0.0:
			arriving = SimStream.mix(arriving, port.stream.with_flow(port.flow_lps))
		elif port.flow_lps < 0.0:
			leaving_lps -= port.flow_lps
	var added_l := arriving.flow_lps * dt
	var removed_l := minf(leaving_lps * dt, volume_l + added_l)

	# Blend the feed in (volume-weighted, same rule as a tank).
	if added_l > 0.0:
		contents = SimStream.mix(contents.with_flow(volume_l), arriving.with_flow(added_l))
	var new_volume := volume_l + added_l - removed_l
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

	# An atmospheric vessel cannot be driven past its bubble point:
	# surplus duty boils the most volatile thing in it and that vapour
	# leaves through the vent, which is why it comes off the inventory
	# rather than out of a nozzle.
	var boil_c := contents.bubble_point_c()
	boiling = temp_c > boil_c
	if boiling and volume_l > 0.0:
		var surplus_kj := (temp_c - boil_c) * mass * cp
		temp_c = boil_c
		var lightest := contents.lightest_present()
		if lightest >= 0:
			var boiled_l := minf(surplus_kj / VAPOR_LATENT_KJ_PER_KG, amounts[lightest])
			amounts[lightest] -= boiled_l
			volume_l -= boiled_l
			boiled_off_l += boiled_l

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
