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

var rate_lps: float
var capture_eff: float
var cake_wetness: float
var is_on: bool = false
var spinning: bool = false
var starts: int = 0
var cake_lps: float = 0.0
var liquor_lps: float = 0.0

var inlet: SimInputPort
var power: SimInputPort
var product: SimOutputPort
var waste: SimOutputPort

var _cake: SimStream = SimStream.empty()
var _liquor: SimStream = SimStream.empty()
var _feed: SimPumpCurve = null
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
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	product = add_output("product", SimTypes.PortKind.PROCESS_MATERIAL)
	waste = add_output("waste", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("starts", &"starts")
	add_observable("cake_lps", &"cake_lps")
	add_observable("liquor_lps", &"liquor_lps")
	add_observable("draw_lps", &"draw_lps")


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
	_to_cake = net.add_branch(SimFixedFlow.new(bowl, node["product"], 0.0,
		comp_name + ".cake")) as SimFixedFlow
	_to_liquor = net.add_branch(SimFixedFlow.new(bowl, node["waste"], 0.0,
		comp_name + ".liquor")) as SimFixedFlow


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	var now_spinning := is_on and power.value > 0.5
	if _feed != null:
		_feed.running = now_spinning
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


func tick(_dt: float) -> void:
	var now_spinning := is_on and power.value > 0.5
	if now_spinning and not spinning:
		starts += 1
	spinning = now_spinning
	var feed := inlet.stream.clamped_solids()
	var rate := draw_lps
	if rate <= 1e-9:
		cake_lps = 0.0
		liquor_lps = 0.0
		return

	var liquid_comp := feed.liquid_comp()
	var solids_lps := rate * feed.solids_frac
	var captured := solids_lps * capture_eff
	var cake_liquid := minf(captured * cake_wetness, rate - solids_lps)
	var cake_total := captured + cake_liquid
	var liquor_total := rate - cake_total

	# The cake is captured crystals plus the mother liquor clinging to
	# them; the liquor carries everything else, crystals the bowl failed
	# to catch included.
	var cake_amounts := SimStream.zero_amounts()
	var liquor_amounts := SimStream.zero_amounts()
	cake_amounts[SimSpecies.SOLID] = captured
	liquor_amounts[SimSpecies.SOLID] = solids_lps - captured
	var remaining_liquid := rate - solids_lps - cake_liquid
	for i in SimSpecies.COUNT:
		cake_amounts[i] += cake_liquid * liquid_comp[i]
		liquor_amounts[i] += remaining_liquid * liquid_comp[i]

	cake_lps = cake_total
	liquor_lps = liquor_total
	_cake = SimStream.make(maxf(cake_total, 1e-9), feed.temp_c,
		SimStream.normalized(cake_amounts),
		captured / cake_total if cake_total > 0.0 else 0.0)
	_liquor = SimStream.make(maxf(liquor_total, 1e-9), feed.temp_c,
		SimStream.normalized(liquor_amounts),
		(solids_lps - captured) / liquor_total if liquor_total > 0.0 else 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "starts": starts}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	starts = int(state.get("starts", starts))
