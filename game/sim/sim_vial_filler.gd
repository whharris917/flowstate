class_name SimVialFiller
extends SimComponent
## Automated vial filler/capper in an isolator: index -> fill -> cap,
## repeating only while powered, on, and fed through the inlet facade
## pair. Every millilitre filled is genuinely drawn from the supplier;
## vials_done is the lifetime count. Mirrors sim/process.py VialFiller.

const VIAL_ML := 10.0
const INDEX_S := 0.5
const FILL_S := 1.1
const CAP_S := 0.8

var is_on: bool = false
var state: String = "idle"          # idle/index/fill/cap
var timer_s: float = 0.0
var vials_done: int = 0

var inlet: SimInputPort
var power: SimInputPort
var draw: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_LEVEL)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("vials_done", &"vials_done")


func tick(dt: float) -> void:
	var fed := inlet.value > 1.0
	var running := is_on and power.value > 0.5 and fed
	var rate := 0.0
	if not running:
		state = "idle"
	else:
		if state == "idle":
			state = "index"
			timer_s = INDEX_S
		timer_s -= dt
		if state == "fill":
			rate = VIAL_ML / 1000.0 / FILL_S
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
	draw.value = rate


func state_dict() -> Dictionary:
	return {"is_on": is_on, "vials_done": vials_done}


func apply_state(state_: Dictionary) -> void:
	is_on = state_.get("is_on", is_on)
	vials_done = int(state_.get("vials_done", vials_done))
