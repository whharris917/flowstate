class_name SimCentrifuge
extends SimComponent
## Disc-stack separator: pulls slurry through the inlet facade pair and
## splits it on the phase that is actually there. Mirrors
## sim/process.py Centrifuge.
##
## Nothing tells this machine the quality of its feed any more; it
## separates crystals from mother liquor, and if the feed carries no
## crystals it honestly sends everything out the liquor nozzle. The cake
## comes off wet, which is why there is a dryer downstream. The bowl is
## a 480 V drive toggled with is_on.

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
var draw: SimOutputPort


func _init(name_: String, rate_lps_ := 4.0, capture_eff_ := 0.95,
		cake_wetness_ := 0.25) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	capture_eff = clampf(capture_eff_, 0.0, 1.0)
	cake_wetness = maxf(cake_wetness_, 0.0)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	product = add_output("product", SimTypes.PortKind.PROCESS_STREAM)
	waste = add_output("waste", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("starts", &"starts")
	add_observable("cake_lps", &"cake_lps")
	add_observable("liquor_lps", &"liquor_lps")


func tick(_dt: float) -> void:
	var now_spinning := is_on and power.value > 0.5
	if now_spinning and not spinning:
		starts += 1
	spinning = now_spinning
	var feed := inlet.stream
	var rate := minf(rate_lps, feed.flow_lps) if spinning else 0.0
	draw.value = rate
	if rate <= 0.0:
		cake_lps = 0.0
		liquor_lps = 0.0
		product.stream = SimStream.empty()
		waste.stream = SimStream.empty()
		return

	feed = feed.clamped_solids()
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
	product.stream = SimStream.make(cake_total, feed.temp_c,
		SimStream.normalized(cake_amounts),
		captured / cake_total if cake_total > 0.0 else 0.0)
	waste.stream = SimStream.make(liquor_total, feed.temp_c,
		SimStream.normalized(liquor_amounts),
		(solids_lps - captured) / liquor_total if liquor_total > 0.0 else 0.0)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "starts": starts}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	starts = int(state.get("starts", starts))
