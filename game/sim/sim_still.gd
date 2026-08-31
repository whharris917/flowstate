class_name SimStill
extends SimComponent
## Continuous solvent recovery still: takes mother liquor, sends the
## light ends overhead and the heavy ends out the bottom. Mirrors
## sim/separation.py Still.
##
## The cut is never perfect: some solvent leaves in the bottoms and some
## heavy ends carry over, which is why recycled solvent is never quite
## as clean as fresh. The reboiler duty is the throttle: no duty, no
## boilup, no separation, and everything the still is fed leaves through
## the bottoms nozzle. Crystals never distill.
##
## This is the unit that closes the loop. Pipe the distillate back to a
## feed header and the solvent goes round again.

const LATENT_KJ_PER_KG := 900.0

var rate_lps: float
var cut_c: float
var sharpness: float
var condenser_c: float
var is_on: bool = false
var running: bool = false
var boilup_lps: float = 0.0
var distillate_lps: float = 0.0
var recovered_l: float = 0.0

var inlet: SimInputPort
var heat_duty: SimInputPort
var power: SimInputPort
var distillate: SimOutputPort
var bottoms: SimOutputPort
var draw: SimOutputPort


func _init(name_: String, rate_lps_ := 3.0, cut_c_ := 150.0,
		sharpness_ := 0.95, condenser_c_ := 40.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	cut_c = cut_c_
	sharpness = clampf(sharpness_, 0.5, 1.0)
	condenser_c = condenser_c_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	distillate = add_output("distillate", SimTypes.PortKind.PROCESS_STREAM)
	bottoms = add_output("bottoms", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("boilup_lps", &"boilup_lps")
	add_observable("distillate_lps", &"distillate_lps")
	add_observable("recovered_l", &"recovered_l")


func tick(dt: float) -> void:
	var feed := inlet.stream.clamped_solids()
	running = is_on and power.value > 0.5
	var rate := minf(rate_lps, feed.flow_lps) if running else 0.0
	draw.value = rate
	boilup_lps = maxf(heat_duty.value, 0.0) / LATENT_KJ_PER_KG if running else 0.0
	if rate <= 0.0:
		distillate_lps = 0.0
		distillate.stream = SimStream.empty()
		bottoms.stream = SimStream.empty()
		return

	var solid_lps := rate * feed.solids_frac
	var wanted := SimStream.zero_amounts()
	var wanted_total := 0.0
	for i in SimSpecies.COUNT:
		var available := rate * feed.comp[i] - (solid_lps if i == SimSpecies.SOLID else 0.0)
		if available <= 0.0:
			continue
		var light := SimSpecies.boil_of(i) < cut_c
		wanted[i] = available * (sharpness if light else 1.0 - sharpness)
		wanted_total += wanted[i]

	# The reboiler sets the ceiling: you cannot take more overhead than
	# you can boil.
	var scale := 1.0
	if wanted_total > boilup_lps:
		scale = boilup_lps / wanted_total if wanted_total > 0.0 else 0.0
	var top_amounts := SimStream.zero_amounts()
	var bottom_amounts := SimStream.zero_amounts()
	var top_total := 0.0
	for i in SimSpecies.COUNT:
		top_amounts[i] = wanted[i] * scale
		bottom_amounts[i] = rate * feed.comp[i] - top_amounts[i]
		top_total += top_amounts[i]
	var bottom_total := rate - top_total

	distillate_lps = top_total
	recovered_l += top_total * dt
	distillate.stream = SimStream.make(top_total, condenser_c,
		SimStream.normalized(top_amounts))
	bottoms.stream = SimStream.make(bottom_total, feed.temp_c,
		SimStream.normalized(bottom_amounts),
		solid_lps / bottom_total if bottom_total > 0.0 else 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "recovered_l": recovered_l}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	recovered_l = state.get("recovered_l", recovered_l)
