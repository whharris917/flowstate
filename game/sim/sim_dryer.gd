class_name SimDryer
extends SimComponent
## Drives the last of the liquid off a wet filter cake. Mirrors
## sim/separation.py Dryer.
##
## What evaporates is the most volatile liquid present, so the solvent
## goes first and the crystals stay. Note what that means: anything that
## was dissolved in the retained mother liquor is left behind in the
## cake as the solvent leaves. A dryer concentrates impurity as surely
## as it concentrates product, which is why the wash matters upstream.
## Needs 480 V for the tumbler.

const LATENT_KJ_PER_KG := 900.0

var rate_lps: float
var is_on: bool = false
var running: bool = false
var evap_lps: float = 0.0
var dried_l: float = 0.0

var inlet: SimInputPort
var heat_duty: SimInputPort
var power: SimInputPort
var product: SimOutputPort
var vapor: SimOutputPort
var draw: SimOutputPort


func _init(name_: String, rate_lps_ := 2.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	product = add_output("product", SimTypes.PortKind.PROCESS_STREAM)
	vapor = add_output("vapor", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("evap_lps", &"evap_lps")
	add_observable("dried_l", &"dried_l")


func tick(dt: float) -> void:
	var feed := inlet.stream.clamped_solids()
	running = is_on and power.value > 0.5
	var rate := minf(rate_lps, feed.flow_lps) if running else 0.0
	draw.value = rate
	if rate <= 0.0:
		evap_lps = 0.0
		product.stream = SimStream.empty()
		vapor.stream = SimStream.empty()
		return

	var amounts := SimStream.zero_amounts()
	for i in SimSpecies.COUNT:
		amounts[i] = rate * feed.comp[i]
	var solid_lps := rate * feed.solids_frac
	var liquid_lps := rate - solid_lps
	var capacity := maxf(heat_duty.value, 0.0) / LATENT_KJ_PER_KG
	var to_evaporate := minf(capacity, liquid_lps)

	# Take it off the most volatile liquid species first, never touching
	# what is already crystal.
	var vapor_amounts := SimStream.zero_amounts()
	var remaining := to_evaporate
	# Species are ordered by index, not volatility, so walk them by
	# boiling point.
	var order: Array[int] = []
	for i in SimSpecies.COUNT:
		if amounts[i] > 0.0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return SimSpecies.boil_of(a) < SimSpecies.boil_of(b))
	for index in order:
		if remaining <= 0.0:
			break
		var liquid_here := amounts[index] - (solid_lps if index == SimSpecies.SOLID else 0.0)
		var take := minf(remaining, maxf(liquid_here, 0.0))
		if take > 0.0:
			amounts[index] -= take
			vapor_amounts[index] += take
			remaining -= take
	var evaporated := to_evaporate - remaining

	evap_lps = evaporated
	dried_l += evaporated * dt
	var product_lps := rate - evaporated
	product.stream = SimStream.make(product_lps, feed.temp_c,
		SimStream.normalized(amounts),
		solid_lps / product_lps if product_lps > 0.0 else 0.0)
	vapor.stream = SimStream.make(evaporated, feed.temp_c,
		SimStream.normalized(vapor_amounts))


func state_dict() -> Dictionary:
	return {"is_on": is_on, "dried_l": dried_l}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	dried_l = state.get("dried_l", dried_l)
