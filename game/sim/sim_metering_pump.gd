class_name SimMeteringPump
extends SimComponent
## A positive-displacement dosing pump: a diaphragm and two check
## valves, driven by a small motor. It delivers its stroke volume every
## stroke whatever the discharge pressure, until the pressure reaches
## what its drive can push against, so its curve is nearly vertical:
## the opposite of the centrifugal pump's. The stroke length is the
## dose adjustment, a knob on the pump or a 4-20 mA signal on its
## stroke input. 24 V DC, a discrete run command, and with nothing
## wired to run it is a hand pump: E starts it. Mirrors
## sim/small_bore.py MeteringPump.
##
##     Q_stroke = rated_lps * stroke / 100
##     Q = Q_stroke * (1 - (H / H_max)^8)^(1/8)     (running)

const CURVE_EXPONENT := 8.0

var rated_lps: float
var max_head_m: float
var stroke_pct: float = 100.0   # the knob, when nothing is wired to "stroke"
var hand_on: bool = false       # the switch, when nothing is wired to "run"
var running: bool = false
var starts: int = 0
var suction_pa: float = 0.0
var discharge_pa: float = 0.0

var run: SimInputPort
var stroke: SimInputPort
var power: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimPumpCurve = null
var _was_running: bool = false


func _init(name_: String, rated_lps_: float = 0.01, max_head_m_: float = 50.0) -> void:
	super(name_)
	assert(rated_lps_ > 0.0, "rated_lps must be positive")
	assert(max_head_m_ > 0.0, "max_head_m must be positive")
	rated_lps = rated_lps_
	max_head_m = max_head_m_
	run = add_input("run", SimTypes.PortKind.SIGNAL_DISCRETE)
	stroke = add_input("stroke", SimTypes.PortKind.SIGNAL_ANALOG)
	power = add_input("power", SimTypes.PortKind.POWER, "24VDC")
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("flow_lps", &"flow_lps")
	add_observable("head_pa", &"head_pa")
	add_observable("starts", &"starts")
	add_observable("stroke_now", &"stroke_now")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


var head_pa: float:
	get:
		return discharge_pa - suction_pa


## The stroke in use, percent: the signal if one is wired, else the knob.
var stroke_now: float:
	get:
		if stroke.wire_count > 0:
			return clampf(stroke.value, 0.0, 100.0)
		return stroke_pct


var is_hand_operated: bool:
	get:
		return run.wire_count == 0


var wants_run: bool:
	get:
		if is_hand_operated:
			return hand_on
		return run.value > 0.5


func status() -> String:
	if not running:
		return "STOPPED" if power.value > 0.5 else "STOPPED · NO 24 V"
	if flow_lps > 1e-9:
		return "DOSING"
	if head_pa >= SimHydraulics.static_head_pa(max_head_m) - 1.0:
		return "RUNNING · STALLED (%.0f m is all its drive has)" % max_head_m
	return "RUNNING · NO FLOW"


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimPumpCurve.new(node["inlet"], node["outlet"],
		SimHydraulics.static_head_pa(max_head_m), rated_lps, comp_name, CURVE_EXPONENT)) as SimPumpCurve


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	running = wants_run and power.value > 0.5
	if _branch != null:
		_branch.running = running and stroke_now > 0.0
		_branch.head_pa = maxf(SimHydraulics.static_head_pa(max_head_m), 1e-12)
		_branch.max_lps = maxf(rated_lps * stroke_now / 100.0, 1e-12)
	suction_pa = net.pressures[node["inlet"]]
	discharge_pa = net.pressures[node["outlet"]]


func tick(_dt: float) -> void:
	if running and not _was_running:
		starts += 1
	_was_running = running


func state_dict() -> Dictionary:
	return {"hand_on": hand_on, "stroke_pct": stroke_pct, "running": running, "starts": starts}


func apply_state(state: Dictionary) -> void:
	hand_on = bool(state.get("hand_on", hand_on))
	stroke_pct = float(state.get("stroke_pct", stroke_pct))
	running = bool(state.get("running", running))
	_was_running = running
	starts = int(state.get("starts", starts))
