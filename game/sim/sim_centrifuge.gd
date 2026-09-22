class_name SimCentrifuge
extends SimComponent
## Disc-stack separator: crystals out of the liquor they formed in.
## Mirrors sim/process.py Centrifuge.
##
## It has its own feed pump, so what it draws is set by its curve
## against the suction it is given — starve it and the rate falls
## away rather than the machine inventing material. What it does with
## what it drew is its own business: the split is set by the phase
## actually present in the feed, and nothing tells it what that is.
## Feed it clear liquid and it honestly sends everything out the
## liquor nozzle. The cake comes off wet, which is why there is a
## dryer downstream. The bowl is a 480 V drive toggled with is_on.

const FEED_HEAD_M := 18.0
const WASH_CV_LPS := 1.5   # the wash spray nozzles, wide open, across 1 bar

var rate_lps: float
var capture_eff: float
var cake_wetness: float
var is_on: bool = false
var spinning: bool = false
var starts: int = 0
var cake_lps: float = 0.0
var liquor_lps: float = 0.0
var wash_lps: float = 0.0
## What is inside it between scans (2026-09-22): its discharges are
## imposed at the next solve from what it drew at this one, so one scan
## of feed is always in the machine. The material balance counts it as
## held.
var in_flight_l: float = 0.0

var inlet: SimInputPort
# Wash liquor: sprayed onto the cake while the bowl spins, it displaces
# the mother liquor the cake would otherwise keep.
var wash: SimInputPort
var power: SimInputPort
var product: SimOutputPort
var waste: SimOutputPort

var _cake: SimStream = SimStream.empty()
var _liquor: SimStream = SimStream.empty()
var _feed: SimPumpCurve = null
var _wash: SimControlResistance = null
var _to_cake: SimFixedFlow = null
var _to_liquor: SimFixedFlow = null


func _init(name_: String, rate_lps_: float = 4.0, capture_eff_: float = 0.95,
		cake_wetness_: float = 0.25) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	capture_eff = clampf(capture_eff_, 0.0, 1.0)
	cake_wetness = maxf(cake_wetness_, 0.0)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	wash = add_input("wash", SimTypes.PortKind.PROCESS_MATERIAL)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	product = add_output("product", SimTypes.PortKind.PROCESS_MATERIAL)
	waste = add_output("waste", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("starts", &"starts")
	add_observable("cake_lps", &"cake_lps")
	add_observable("liquor_lps", &"liquor_lps")
	add_observable("draw_lps", &"draw_lps")
	add_observable("wash_lps", &"wash_lps")
	add_observable("in_flight_l", &"in_flight_l")


var draw_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# The bowl is a boundary, not a free node. It has to be: the
	# discharges are imposed at the split worked out from last scan's
	# draw, so a free bowl would have to balance them against a draw
	# that does not exist yet -- and a machine that has never run has
	# never drawn anything, so it would never start.
	var bowl := net.add_node(0.0, true)
	_feed = net.add_branch(SimPumpCurve.new(node["inlet"], bowl,
		SimHydraulics.static_head_pa(FEED_HEAD_M), rate_lps, comp_name + ".feed")) as SimPumpCurve
	# The wash spray is a valve into the bowl, interlocked to the bowl:
	# shut unless it spins. What comes through is set by the pressure
	# behind it, like everything else.
	_wash = net.add_branch(SimControlResistance.new(node["wash"], bowl,
		WASH_CV_LPS, comp_name + ".wash")) as SimControlResistance
	_to_cake = net.add_branch(SimFixedFlow.new(bowl, node["product"], 0.0,
		comp_name + ".cake")) as SimFixedFlow
	_to_liquor = net.add_branch(SimFixedFlow.new(bowl, node["waste"], 0.0,
		comp_name + ".liquor")) as SimFixedFlow


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	var now_spinning := is_on and power.value > 0.5
	if _feed != null:
		_feed.running = now_spinning
	if _wash != null:
		_wash.opening = 1.0 if now_spinning else 0.0
	# The split is worked out from what actually came in, so the
	# discharges follow the draw by one scan.
	if _to_cake != null:
		_to_cake.lps = cake_lps
		_to_liquor.lps = liquor_lps


func supplied_stream(port_name: String) -> SimStream:
	if port_name == "product":
		return _cake
	if port_name == "waste":
		return _liquor
	return null


func tick(dt: float) -> void:
	var now_spinning := is_on and power.value > 0.5
	if now_spinning and not spinning:
		starts += 1
	spinning = now_spinning
	var feed := inlet.stream.clamped_solids()
	var rate := draw_lps
	var wash_in := wash.stream.clamped_solids()
	wash_lps = maxf(wash.flow_lps, 0.0)
	if rate <= 1e-9 and wash_lps <= 1e-9:
		cake_lps = 0.0
		liquor_lps = 0.0
		in_flight_l = 0.0
		return

	var liquid_comp := feed.liquid_comp()
	var wash_comp := wash_in.liquid_comp()
	var solids_lps := rate * feed.solids_frac
	var captured := solids_lps * capture_eff
	var cake_liquid := minf(captured * cake_wetness, rate - solids_lps)
	var cake_total := captured + cake_liquid
	# Displacement washing: each cake-liquid volume of wash pushes out
	# 63 % of the mother liquor still in the cake and takes its place.
	# What it displaces, and the rest of the wash, leave with the liquor.
	var kept := exp(-wash_lps / cake_liquid) if cake_liquid > 1e-12 else 1.0
	var liquor_total := rate - cake_total + wash_lps

	# The cake is captured crystals plus the liquid clinging to them;
	# the liquor carries everything else, crystals the bowl failed to
	# catch and spent wash included.
	var cake_amounts := SimStream.zero_amounts()
	var liquor_amounts := SimStream.zero_amounts()
	cake_amounts[SimSpecies.SOLID] = captured
	liquor_amounts[SimSpecies.SOLID] = solids_lps - captured
	var remaining_liquid := rate - solids_lps - cake_liquid * kept
	var wash_through := wash_lps - cake_liquid * (1.0 - kept)
	for i in SimSpecies.COUNT:
		cake_amounts[i] += cake_liquid * (kept * liquid_comp[i] + (1.0 - kept) * wash_comp[i])
		liquor_amounts[i] += remaining_liquid * liquid_comp[i] + wash_through * wash_comp[i]
	var cake_temp := feed.temp_c * kept + wash_in.temp_c * (1.0 - kept) \
		if cake_liquid > 1e-12 else feed.temp_c
	var liquor_temp := feed.temp_c
	if remaining_liquid + wash_through > 1e-12:
		liquor_temp = (remaining_liquid * feed.temp_c + wash_through * wash_in.temp_c) \
			/ (remaining_liquid + wash_through)

	cake_lps = cake_total
	liquor_lps = liquor_total
	in_flight_l = (cake_lps + liquor_lps) * dt
	_cake = SimStream.make(maxf(cake_total, 1e-9), cake_temp,
		SimStream.normalized(cake_amounts),
		captured / cake_total if cake_total > 0.0 else 0.0)
	_liquor = SimStream.make(maxf(liquor_total, 1e-9), liquor_temp,
		SimStream.normalized(liquor_amounts),
		(solids_lps - captured) / liquor_total if liquor_total > 0.0 else 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "starts": starts}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	starts = int(state.get("starts", starts))
