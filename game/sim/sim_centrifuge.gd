class_name SimCentrifuge
extends SimComponent
## Disc-stack separator: pulls mix from an upstream vessel through the
## inlet facade pair and splits it into product and waste streams
## using the wired purity quality signal. The bowl is a 480 V drive
## toggled with is_on. Mirrors sim/process.py Centrifuge.

var rate_lps: float
var is_on: bool = false
var spinning: bool = false
var starts: int = 0

var inlet: SimInputPort
var purity_in: SimInputPort
var power: SimInputPort
var product: SimOutputPort
var waste: SimOutputPort
var draw: SimOutputPort


func _init(name_: String, rate_lps_ := 4.0) -> void:
	super(name_)
	assert(rate_lps_ > 0.0, "rate_lps must be positive")
	rate_lps = rate_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_LEVEL)
	purity_in = add_input("purity_in", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	product = add_output("product", SimTypes.PortKind.PROCESS_FLOW)
	waste = add_output("waste", SimTypes.PortKind.PROCESS_FLOW)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("starts", &"starts")


func tick(_dt: float) -> void:
	var now_spinning := is_on and power.value > 0.5
	if now_spinning and not spinning:
		starts += 1
	spinning = now_spinning
	var wet := inlet.value > 0.5
	var rate := rate_lps if (spinning and wet) else 0.0
	var pure := clampf(purity_in.value, 0.0, 1.0)
	draw.value = rate
	product.value = rate * pure
	waste.value = rate * (1.0 - pure)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "starts": starts}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	starts = int(state.get("starts", starts))
