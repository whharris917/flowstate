class_name SimPump
extends SimComponent
## Fixed-rate transfer pump with a Hand-Off-Auto selector, exactly like
## the selector on a real motor starter. Draws from an unlimited supply
## main for now. starts is the motor-wear counterpart to the relay's
## cycles.

const MODES: Array[String] = ["hand", "off", "auto"]

var rated_lps: float
var mode: String = "auto"
var running: bool = false
var starts: int = 0

var run: SimInputPort
var flow: SimOutputPort


func _init(name_: String, rated_lps_: float, mode_: String = "auto") -> void:
	super(name_)
	assert(rated_lps_ > 0.0, "rated_lps must be positive")
	rated_lps = rated_lps_
	set_mode(mode_)
	run = add_input("run", SimTypes.PortKind.SIGNAL_DISCRETE)
	flow = add_output("flow", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("starts", &"starts")


func set_mode(mode_: String) -> void:
	if not MODES.has(mode_):
		push_error("mode must be one of %s" % str(MODES))
		return
	mode = mode_


func next_mode() -> void:
	set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])


func tick(_dt: float) -> void:
	var should_run: bool
	if mode == "hand":
		should_run = true
	elif mode == "off":
		should_run = false
	else:
		should_run = run.value > 0.5
	if should_run and not running:
		starts += 1
	running = should_run
	flow.value = rated_lps if running else 0.0


func state_dict() -> Dictionary:
	return {"mode": mode, "running": running, "starts": starts}


func apply_state(state: Dictionary) -> void:
	mode = state.get("mode", mode)
	running = state.get("running", running)
	starts = int(state.get("starts", starts))
	flow.value = rated_lps if running else 0.0
