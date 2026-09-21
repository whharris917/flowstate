class_name SimPump
extends SimComponent
## Centrifugal transfer pump with a Hand-Off-Auto selector, exactly
## like the selector on a real motor starter. Mirrors sim/components.py
## Pump.
##
## It has a curve, so it does not simply deliver its rating: it finds
## its own operating point against whatever the system puts in front
## of it. Ask it to lift more than its shutoff head and it dead-heads —
## the motor turns, the discharge valve is open, and nothing moves. Two
## in parallel do not double the flow. Run it against a suction that
## cannot keep up and the suction node falls toward vacuum, which is
## what cavitating reports. What comes out the discharge is what went
## in the suction — same temperature, same composition. starts is the
## motor-wear counterpart to the relay's cycles.

const MODES: Array[String] = ["hand", "off", "auto"]
## Suction pressure below which the pump is cavitating rather than
## pumping. Crude stand-in for NPSH.
const CAVITATION_PA := -60000.0

var rated_lps: float
var head_m: float = 30.0
## The height of its nozzles above grade, re-derived by the plant from
## where it stands. The network solves piezometric pressures, so the
## static suction a gauge on the pump reads, and prime and cavitation
## are judged on, is the node's pressure less rho*g*elevation
## (director, 2026-09-21: a pump at the top of a rise is not the pump
## at the bottom of it).
var elevation_m: float = 0.0
var mode: String = "auto"
var running: bool = false
var starts: int = 0
var dry_run_s: float = 0.0
var cavitating: bool = false
var suction_pa: float = 0.0
var discharge_pa: float = 0.0

var run: SimInputPort
var power: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimPumpCurve = null
var _was_running: bool = false


func _init(name_: String, rated_lps_: float, mode_: String = "auto",
		head_m_: float = 30.0, elevation_m_: float = 0.0) -> void:
	super(name_)
	assert(rated_lps_ > 0.0, "rated_lps must be positive")
	assert(head_m_ > 0.0, "head_m must be positive")
	rated_lps = rated_lps_
	head_m = head_m_
	elevation_m = elevation_m_
	set_mode(mode_)
	run = add_input("run", SimTypes.PortKind.SIGNAL_DISCRETE)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("starts", &"starts")
	add_observable("dry_run_s", &"dry_run_s")
	add_observable("flow_lps", &"flow_lps")
	add_observable("head_pa", &"head_pa")


## What it is moving right now, L/s. Read off the suction nozzle,
## which the solve signs into the pump.
var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)

## The rise it is actually making right now.
var head_pa: float:
	get:
		return discharge_pa - suction_pa


## How the selector position reads to the player (director's call,
## 2026-09-02: "Manual On", never "Hand"). The kernel keeps the short
## internal names.
static func mode_label(mode_: String) -> String:
	match mode_:
		"hand": return "MANUAL ON"
		"off": return "OFF"
	return "AUTO"


## One honest word for what the pump is doing, for a label or a hover:
## a running pump that moves nothing is either dead-headed (the system
## asks more lift than its curve has) or cavitating (its suction has
## fallen toward vacuum).
func status() -> String:
	if not running:
		return "STOPPED"
	if flow_lps > 1e-6:
		return "RUNNING"
	if cavitating:
		return "RUNNING · CAVITATING"
	if head_pa >= SimHydraulics.static_head_pa(head_m) - 1.0:
		return "RUNNING · DEAD-HEADED (needs %.1f m, has %.0f m)" % [
			head_pa / SimHydraulics.HEAD_PA_PER_M, head_m]
	return "RUNNING · NO FLOW"


func set_mode(mode_: String) -> void:
	if not MODES.has(mode_):
		push_error("mode must be one of %s" % str(MODES))
		return
	mode = mode_


func next_mode() -> void:
	set_mode(MODES[(MODES.find(mode) + 1) % MODES.size()])


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimPumpCurve.new(node["inlet"], node["outlet"],
		SimHydraulics.static_head_pa(head_m), rated_lps, comp_name)) as SimPumpCurve


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	var wants: bool
	if mode == "hand":
		wants = true
	elif mode == "off":
		wants = false
	else:
		wants = run.value > 0.5
	# No 480 V at the starter, no motor — hand mode included.
	running = wants and power.value > 0.5
	var datum := SimHydraulics.static_head_pa(elevation_m)
	if _branch != null:
		_branch.running = running
		_branch.head_pa = maxf(SimHydraulics.static_head_pa(head_m), 1e-12)
		_branch.max_lps = maxf(rated_lps, 1e-12)
		_branch.datum_pa = datum
	# Static pressures at the pump's own height: what its gauges read.
	suction_pa = net.pressures[node["inlet"]] - datum
	discharge_pa = net.pressures[node["outlet"]] - datum


func tick(dt: float) -> void:
	if running and not _was_running:
		starts += 1
	_was_running = running
	cavitating = running and suction_pa <= CAVITATION_PA
	# The motor can spin against an empty inlet, but nothing moves and
	# the seal wears.
	if running and flow_lps < 1e-6:
		dry_run_s += dt


func state_dict() -> Dictionary:
	return {"mode": mode, "running": running, "starts": starts, "dry_run_s": dry_run_s}


func apply_state(state: Dictionary) -> void:
	mode = state.get("mode", mode)
	running = state.get("running", running)
	_was_running = running
	starts = int(state.get("starts", starts))
	dry_run_s = state.get("dry_run_s", dry_run_s)
