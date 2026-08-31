class_name SimCrystallizer
extends SimComponent
## Cooled, agitated vessel that drops product out of solution.
## Mirrors sim/separation.py Crystallizer.
##
## Cool the batch below saturation and crystals grow toward equilibrium
## with a time constant; warm it back up and they redissolve, because
## the same equation runs in both directions. Without a powered agitator
## the process crawls — nucleation needs the shear.
##
## The cooling duty is a positive number on cool_duty: kilowatts
## *removed*. Wire a chiller loop or a controller output to it.

const TAU_S := 60.0
const UNMIXED_FACTOR := 0.1
const LOSS_PER_S := 0.0004
const OUTLET_MAX_LPS := 250.0
const MIN_THERMAL_MASS_KG := 50.0
## A jacket cannot chill the batch below the coolant feeding it.
## Without this a duty left on drives the vessel to nonsense.
const COOLANT_C := 5.0

var capacity_l: float
var volume_l: float = 0.0
var temp_c: float = SimStream.AMBIENT_C
var agitating: bool = false
var overflowed_l: float = 0.0
var contents: SimStream

var inlet: SimInputPort
var cool_duty: SimInputPort
var power: SimInputPort
var draw: SimInputPort
var level: SimOutputPort
var outlet: SimOutputPort
var solids: SimOutputPort
var temp: SimOutputPort


func _init(name_: String, capacity_l_ := 3000.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0, "capacity_l must be positive")
	capacity_l = capacity_l_
	contents = SimStream.pure(SimSpecies.WATER, 0.0, temp_c)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_STREAM)
	cool_duty = add_input("cool_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_SUPPLY)
	solids = add_output("solids", SimTypes.PortKind.SIGNAL_ANALOG)
	temp = add_output("temp", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("temp_c", &"temp_c")
	add_observable("volume_l", &"volume_l")
	add_observable("solids_frac", &"solids_frac")
	add_observable("supersaturation", &"supersaturation")
	add_observable("overflowed_l", &"overflowed_l")


var solids_frac: float:
	get:
		return contents.solids_frac


## Equilibrium dissolved fraction of the crystallizing species at the
## current temperature. Grams per litre becomes a volume fraction
## directly on the kernel 1 L = 1 kg basis.
var saturation_frac: float:
	get:
		return SimSpecies.solubility_g_per_l(SimSpecies.SOLID, temp_c) / 1000.0


## How far past saturation the dissolved product is. Negative means
## there is room for more, and crystals will redissolve.
var supersaturation: float:
	get:
		return (contents.frac(SimSpecies.SOLID) - contents.solids_frac) - saturation_frac


func charge(volume_l_: float, comp: PackedFloat32Array, temp_c_: float,
		solids_frac_ := 0.0) -> void:
	volume_l = clampf(volume_l_, 0.0, capacity_l)
	temp_c = temp_c_
	contents = SimStream.make(volume_l, temp_c_, comp, solids_frac_)
	level.value = volume_l


func tick(dt: float) -> void:
	var incoming := inlet.stream
	var added_l := incoming.flow_lps * dt
	var outflow_l := minf(draw.value * dt, volume_l + added_l)

	if added_l > 0.0:
		contents = SimStream.mix(contents.with_flow(volume_l), incoming.with_flow(added_l))
	var new_volume := volume_l + added_l - outflow_l
	if new_volume > capacity_l:
		overflowed_l += new_volume - capacity_l
		new_volume = capacity_l
	volume_l = maxf(new_volume, 0.0)

	# Energy: duty is heat removed, so it subtracts.
	temp_c = contents.temp_c
	agitating = power.value > 0.5
	var mass := maxf(volume_l, MIN_THERMAL_MASS_KG)
	var cp := contents.cp_kj_per_kg_k()
	temp_c -= cool_duty.value / (mass * cp) * dt
	temp_c -= (temp_c - SimStream.AMBIENT_C) * LOSS_PER_S * dt
	# The jacket can only take the batch down to its coolant.
	if cool_duty.value > 0.0:
		temp_c = maxf(temp_c, COOLANT_C)

	# Crystallize toward equilibrium, in both directions.
	var mix_factor := 1.0 if agitating else UNMIXED_FACTOR
	var total_product := contents.frac(SimSpecies.SOLID)
	var solid := contents.solids_frac
	var excess := (total_product - solid) - saturation_frac
	# Never more solid than there is product, never less than none.
	solid = clampf(solid + excess * mix_factor * dt / TAU_S, 0.0, total_product)

	contents = SimStream.make(volume_l, temp_c, contents.comp, solid)
	level.value = volume_l
	var offered := minf(volume_l / dt, OUTLET_MAX_LPS) if dt > 0.0 else 0.0
	outlet.stream = contents.with_flow(offered)
	solids.value = contents.solids_frac
	temp.value = temp_c


func state_dict() -> Dictionary:
	return {"volume_l": volume_l, "temp_c": temp_c, "overflowed_l": overflowed_l,
		"contents": contents.to_dict()}


func apply_state(state: Dictionary) -> void:
	volume_l = state.get("volume_l", volume_l)
	temp_c = state.get("temp_c", temp_c)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	if state.has("contents"):
		contents = SimStream.from_dict(state["contents"]).with_flow(volume_l)
	level.value = volume_l
	solids.value = contents.solids_frac
	temp.value = temp_c
