class_name SimDryer
extends SimComponent
## Drives the last of the liquid off a wet filter cake. Mirrors
## sim/separation.py Dryer.
##
## It has its own feed, so what it takes depends on what the hopper
## above it can give. What evaporates is the most volatile liquid
## present, so the solvent goes first and the crystals stay — which
## means anything dissolved in the retained mother liquor is still
## there when the solvent leaves. A dryer concentrates impurity as
## surely as it concentrates product. The vapour goes out of the vent
## rather than a nozzle; dried_l keeps a running total of it. Needs
## 480 V for the tumbler.

const LATENT_KJ_PER_KG := 900.0
const FEED_HEAD_M := 12.0

var rate_lps: float
var is_on: bool = false
var running: bool = false
var evap_lps: float = 0.0
var dried_l: float = 0.0
var product_lps: float = 0.0
## What is inside it between scans: its discharges are
## imposed at the next solve from what it drew at this one, so one scan
## of feed is always in the machine. The material balance counts it as
## held.
var in_flight_l: float = 0.0

var inlet: SimInputPort
var heat_duty: SimInputPort
var power: SimInputPort
var product: SimOutputPort

var _cake: SimStream = SimStream.empty()
var _feed: SimPumpCurve = null
var _out: SimFixedFlow = null


func _init(name_: String, rate_lps_: float = 2.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	heat_duty = add_input("heat_duty", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	product = add_output("product", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("evap_lps", &"evap_lps")
	add_observable("dried_l", &"dried_l")
	add_observable("draw_lps", &"draw_lps")
	add_observable("in_flight_l", &"in_flight_l")


var draw_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# A boundary, not a free node -- see the note on the centrifuge
	# bowl. The cake discharge is imposed at last scan's rate, so a free
	# drum could never start.
	var drum := net.add_node(0.0, true)
	_feed = net.add_branch(SimPumpCurve.new(node["inlet"], drum,
		SimHydraulics.static_head_pa(FEED_HEAD_M), rate_lps, comp_name + ".feed")) as SimPumpCurve
	_out = net.add_branch(SimFixedFlow.new(drum, node["product"], 0.0,
		comp_name + ".cake")) as SimFixedFlow


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	running = is_on and power.value > 0.5
	if _feed != null:
		_feed.running = running
	if _out != null:
		_out.lps = product_lps


func supplied_stream(port_name: String) -> SimStream:
	return _cake if port_name == "product" else null


func tick(dt: float) -> void:
	var feed := inlet.stream.clamped_solids()
	var rate := draw_lps
	if rate <= 1e-9:
		evap_lps = 0.0
		product_lps = 0.0
		in_flight_l = 0.0
		return

	var amounts := SimStream.zero_amounts()
	for i in SimSpecies.COUNT:
		amounts[i] = rate * feed.comp[i]
	var solid_lps := rate * feed.solids_frac
	var liquid_lps := rate - solid_lps
	var capacity := maxf(heat_duty.value, 0.0) / LATENT_KJ_PER_KG
	var to_evaporate := minf(capacity, liquid_lps)

	# Take it off the most volatile liquid species first, never touching
	# what is already crystal. Species are ordered by index, not
	# volatility, so walk them by boiling point.
	var remaining := to_evaporate
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
			remaining -= take
	var evaporated := to_evaporate - remaining

	evap_lps = evaporated
	dried_l += evaporated * dt
	product_lps = rate - evaporated
	in_flight_l = product_lps * dt
	_cake = SimStream.make(maxf(product_lps, 1e-9), feed.temp_c,
		SimStream.normalized(amounts),
		solid_lps / product_lps if product_lps > 0.0 else 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "dried_l": dried_l}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	dried_l = state.get("dried_l", dried_l)
