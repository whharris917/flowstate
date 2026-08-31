class_name SimPump
extends SimComponent
## Fixed-rate transfer pump with a Hand-Off-Auto selector, exactly like
## the selector on a real motor starter. It moves material at its
## rating or at whatever the suction can actually give it, so a tank
## running empty throttles the pump instead of going negative. What
## comes out the discharge is what went in the suction — same
## temperature, same composition, different rate. starts is the
## motor-wear counterpart to the relay's cycles.

const MODES: Array[String] = ["hand", "off", "auto"]

var rated_lps: float
var mode: String = "auto"
var running: bool = false
var starts: int = 0
var dry_run_s: float = 0.0
var flow_lps: float = 0.0

var run: SimInputPort
var power: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort
var draw: SimOutputPort


func _init(name_: String, rated_lps_: float, mode_: String = "auto") -> void:
	super(name_)
	assert(rated_lps_ > 0.0, "rated_lps must be positive")
	rated_lps = rated_lps_
	set_mode(mode_)
	run = add_input("run", SimTypes.PortKind.SIGNAL_DISCRETE)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("starts", &"starts")
	add_observable("dry_run_s", &"dry_run_s")
	add_observable("flow_lps", &"flow_lps")


func set_mode(mode_: String) -> void:
	if not MODES.has(mode_):
		push_error("mode must be one of %s" % str(MODES))
		return
	mode = mode_


func next_mode() -> void:
	set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])


func tick(dt: float) -> void:
	var should_run: bool
	if mode == "hand":
		should_run = true
	elif mode == "off":
		should_run = false
	else:
		should_run = run.value > 0.5
	# No 480 V at the starter, no motor — hand mode included.
	should_run = should_run and power.value > 0.5
	if should_run and not running:
		starts += 1
	running = should_run
	# The motor can spin against an empty inlet, but nothing moves and
	# the seal wears.
	var offered := inlet.stream
	var wet := offered.flow_lps > 1e-9
	if running and not wet:
		dry_run_s += dt
	# Take the rating, or whatever the vessel can still give — which is
	# how a tank running empty throttles the pump smoothly.
	flow_lps = minf(rated_lps, offered.flow_lps) if running else 0.0
	outlet.stream = offered.with_flow(flow_lps)
	draw.value = flow_lps


func state_dict() -> Dictionary:
	return {"mode": mode, "running": running, "starts": starts, "dry_run_s": dry_run_s}


func apply_state(state: Dictionary) -> void:
	mode = state.get("mode", mode)
	running = state.get("running", running)
	starts = int(state.get("starts", starts))
	dry_run_s = state.get("dry_run_s", dry_run_s)
