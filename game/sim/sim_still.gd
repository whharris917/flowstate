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
## the bottoms nozzle. Crystals never distill. It has its own feed pump,
## so what it draws is its curve against the suction it is given.
##
## This is the unit that closes the loop. Pipe the distillate back to a
## feed header and the solvent goes round again.

const LATENT_KJ_PER_KG := 900.0
const FEED_HEAD_M := 20.0

var rate_lps: float
var cut_c: float
var sharpness: float
var condenser_c: float
var is_on: bool = false
var running: bool = false
var boilup_lps: float = 0.0
var distillate_lps: float = 0.0
var bottoms_lps: float = 0.0
var recovered_l: float = 0.0

var inlet: SimInputPort
var heat_duty: SimInputPort
var power: SimInputPort
var distillate: SimOutputPort
var bottoms: SimOutputPort

var _top: SimStream = SimStream.empty()
var _bottom: SimStream = SimStream.empty()
var _feed: SimPumpCurve = null
var _to_top: SimFixedFlow = null
var _to_bottom: SimFixedFlow = null


func _init(name_: String, rate_lps_: float = 3.0, cut_c_: float = 150.0,
		sharpness_: float = 0.95, condenser_c_: float = 40.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	cut_c = cut_c_
	sharpness = clampf(sharpness_, 0.5, 1.0)
	condenser_c = condenser_c_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	distillate = add_output("distillate", SimTypes.PortKind.PROCESS_MATERIAL)
	bottoms = add_output("bottoms", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("boilup_lps", &"boilup_lps")
	add_observable("distillate_lps", &"distillate_lps")
	add_observable("recovered_l", &"recovered_l")
	add_observable("draw_lps", &"draw_lps")


var draw_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# A boundary, not a free node -- see the note on the centrifuge
	# bowl. Both products are imposed at last scan's split, so a free
	# sump could never start.
	var sump := net.add_node(0.0, true)
	_feed = net.add_branch(SimPumpCurve.new(node["inlet"], sump,
		SimHydraulics.static_head_pa(FEED_HEAD_M), rate_lps, comp_name + ".feed")) as SimPumpCurve
	_to_top = net.add_branch(SimFixedFlow.new(sump, node["distillate"], 0.0,
		comp_name + ".overhead")) as SimFixedFlow
	_to_bottom = net.add_branch(SimFixedFlow.new(sump, node["bottoms"], 0.0,
		comp_name + ".bottoms")) as SimFixedFlow


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	running = is_on and power.value > 0.5
	if _feed != null:
		_feed.running = running
	if _to_top != null:
		_to_top.lps = distillate_lps
		_to_bottom.lps = bottoms_lps


func supplied_stream(port_name: String) -> SimStream:
	if port_name == "distillate":
		return _top
	if port_name == "bottoms":
		return _bottom
	return null


func tick(dt: float) -> void:
	var feed := inlet.stream.clamped_solids()
	var rate := draw_lps
	boilup_lps = maxf(heat_duty.value, 0.0) / LATENT_KJ_PER_KG if running else 0.0
	if rate <= 1e-9:
		distillate_lps = 0.0
		bottoms_lps = 0.0
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
	bottoms_lps = bottom_total
	recovered_l += top_total * dt
	_top = SimStream.make(maxf(top_total, 1e-9), condenser_c,
		SimStream.normalized(top_amounts))
	_bottom = SimStream.make(maxf(bottom_total, 1e-9), feed.temp_c,
		SimStream.normalized(bottom_amounts),
		solid_lps / bottom_total if bottom_total > 0.0 else 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "recovered_l": recovered_l}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	recovered_l = state.get("recovered_l", recovered_l)
