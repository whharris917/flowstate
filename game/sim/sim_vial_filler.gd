class_name SimVialFiller
extends SimComponent
## Automated vial filler/capper in an isolator: index -> fill -> cap,
## repeating while powered and on. Mirrors sim/process.py VialFiller.
##
## Every millilitre it puts in a vial is genuinely pulled through its
## inlet, and only while the fill station is actually filling — which
## is what gives the machine its rhythm. The dose is an imposed draw,
## so a starved machine drags its suction toward vacuum and fills a
## short vial rather than faulting. It fills vials with whatever it is
## piped to and keeps an honest record of what that was.

const VIAL_ML := 10.0
const INDEX_S := 0.5
const FILL_S := 1.1
const CAP_S := 0.8

var is_on: bool = false
var state: String = "idle"          # idle/index/fill/cap
var timer_s: float = 0.0
var vials_done: int = 0
var fill_purity: float = 0.0
var filled_l: float = 0.0
var product_filled_l: float = 0.0
var starved: bool = false

var inlet: SimInputPort
var power: SimInputPort

var _draw: SimFixedFlow = null


func _init(name_: String) -> void:
	super(name_)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	add_observable("vials_done", &"vials_done")
	add_observable("fill_purity", &"fill_purity")
	add_observable("product_filled_l", &"product_filled_l")


var needed_lps: float:
	get:
		return VIAL_ML / 1000.0 / FILL_S

## What the dosing pump is actually pulling right now, L/s.
var draw_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# Filled vials leave the modelled system.
	var away := net.add_node(0.0, true)
	_draw = net.add_branch(SimFixedFlow.new(node["inlet"], away, 0.0,
		comp_name + ".fill")) as SimFixedFlow


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	var filling := state == "fill" and is_on and power.value > 0.5
	if _draw != null:
		_draw.lps = needed_lps if filling else 0.0


func tick(dt: float) -> void:
	var feed := inlet.stream
	var drawn := draw_lps
	# A dosing pump that cannot get its charge is starved, and the
	# suction going toward vacuum is how it finds out.
	starved = state == "fill" and drawn < needed_lps * 0.9
	var running := is_on and power.value > 0.5
	if not running:
		state = "idle"
	else:
		if state == "idle":
			state = "index"
			timer_s = INDEX_S
		timer_s -= dt
		if timer_s <= 0.0:
			match state:
				"index":
					state = "fill"
					timer_s = FILL_S
				"fill":
					state = "cap"
					timer_s = CAP_S
				"cap":
					vials_done += 1
					state = "index"
					timer_s = INDEX_S
	# It fills vials with whatever it is piped to, and keeps an honest
	# record of what that was — so a train that quietly went off-spec is
	# provable after the fact instead of arguable.
	fill_purity = feed.frac(SimSpecies.PRODUCT)
	filled_l += drawn * dt
	product_filled_l += drawn * fill_purity * dt


func state_dict() -> Dictionary:
	return {"is_on": is_on, "vials_done": vials_done, "filled_l": filled_l,
		"product_filled_l": product_filled_l}


func apply_state(state_: Dictionary) -> void:
	is_on = state_.get("is_on", is_on)
	vials_done = int(state_.get("vials_done", vials_done))
	filled_l = state_.get("filled_l", filled_l)
	product_filled_l = state_.get("product_filled_l", product_filled_l)
