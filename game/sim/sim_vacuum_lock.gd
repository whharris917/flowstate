class_name SimVacuumLock
extends SimComponent
## Cyclic vacuum transfer lock: pulls down to rough vacuum, dwells,
## re-pressurizes through the main air valve in discrete bursts, then
## dumps the cycle's knocked-out condensate through an automatic
## drainer. press is gauge-able; drain_flow is a real water nozzle to
## pipe to a drain — the drainer pushes condensate out at its own rate,
## and where it goes is the plant's problem. Needs 480 V; is_on starts
## the cycle. Mirrors sim/process.py VacuumLock.

const PRESS_ATM_PA := 101300.0
const PRESS_VAC_PA := 18000.0
const EVAC_TAU_S := 6.0
const HOLD_S := 3.0
const VENT_BURSTS := 5
const VENT_PAUSE_S := 1.4
const CONDENSATE_PER_CYCLE_L := 5.0
const DRAIN_LPS := 1.2
const IDLE_EQUALIZE_TAU_S := 20.0

var is_on: bool = false
var state: String = "idle"          # idle/evacuate/hold/vent/drain
var press_pa: float = PRESS_ATM_PA
var condensate_l: float = 0.0
var draining_lps: float = 0.0
var cycles: int = 0
## The material balance's two numbers: everything the lock has
## condensed, which is what it feeds the plant, and what is still in its
## chamber, the scan's worth on its way out included (the drainer pushes
## this tick's rate at the next solve). The chamber's condensate is held,
## not fed.
var condensed_l: float = 0.0
var holdup_l: float = 0.0
var vent_bursts_done: int = 0       # lifetime counter; views watch edges
var timer_s: float = 0.0

var power: SimInputPort
var press: SimOutputPort
var drain_flow: SimOutputPort

var _drainer: SimFixedFlow = null
var _condensate: SimStream = SimStream.pure(SimSpecies.WATER, 1.0, 40.0)


func _init(name_: String) -> void:
	super(name_)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	press = add_output("press", SimTypes.PortKind.PROCESS_PRESSURE)
	drain_flow = add_output("drain_flow", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("press_pa", &"press_pa")
	add_observable("condensate_l", &"condensate_l")
	add_observable("cycles", &"cycles")
	add_observable("condensed_l", &"condensed_l")
	add_observable("holdup_l", &"holdup_l")


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	var chamber := net.add_node(0.0, true)
	_drainer = net.add_branch(SimFixedFlow.new(chamber, node["drain_flow"], 0.0,
		comp_name + ".drainer")) as SimFixedFlow


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _drainer != null:
		_drainer.lps = draining_lps


func supplied_stream(_port_name: String) -> SimStream:
	return _condensate


func tick(dt: float) -> void:
	var rate := 0.0
	if not (is_on and power.value > 0.5):
		state = "idle"
		press_pa += (PRESS_ATM_PA - press_pa) * dt / IDLE_EQUALIZE_TAU_S
	else:
		if state == "idle":
			state = "evacuate"
		match state:
			"evacuate":
				press_pa += (PRESS_VAC_PA - press_pa) * dt / EVAC_TAU_S
				if press_pa < PRESS_VAC_PA * 1.15:
					state = "hold"
					timer_s = HOLD_S
			"hold":
				timer_s -= dt
				if timer_s <= 0.0:
					state = "vent"
					timer_s = VENT_PAUSE_S
			"vent":
				timer_s -= dt
				if timer_s <= 0.0:
					var step := (PRESS_ATM_PA - PRESS_VAC_PA) / float(VENT_BURSTS)
					press_pa = minf(PRESS_ATM_PA, press_pa + step)
					vent_bursts_done += 1
					timer_s = VENT_PAUSE_S
					if press_pa >= PRESS_ATM_PA - 100.0:
						condensate_l += CONDENSATE_PER_CYCLE_L
						condensed_l += CONDENSATE_PER_CYCLE_L
						state = "drain"
			"drain":
				# Drain what is there and no more: the last scan of a
				# cycle has less than a full scan's worth left, and
				# running it at the full rate would push out material
				# that nothing supplied.
				var drained := minf(condensate_l, DRAIN_LPS * dt)
				condensate_l -= drained
				rate = drained / dt if dt > 0.0 else 0.0
				if condensate_l <= 0.0:
					cycles += 1
					state = "evacuate"
	press.value = press_pa
	draining_lps = rate
	holdup_l = condensate_l + draining_lps * dt


func state_dict() -> Dictionary:
	return {"is_on": is_on, "state": state, "press_pa": press_pa,
		"condensate_l": condensate_l, "cycles": cycles, "condensed_l": condensed_l,
		"vent_bursts_done": vent_bursts_done, "timer_s": timer_s}


func apply_state(state_: Dictionary) -> void:
	is_on = state_.get("is_on", is_on)
	state = str(state_.get("state", state))
	press_pa = state_.get("press_pa", press_pa)
	condensate_l = state_.get("condensate_l", condensate_l)
	cycles = int(state_.get("cycles", cycles))
	# A save without the counter: every finished cycle's lump, and the
	# one in the chamber while it drains.
	condensed_l = float(state_.get("condensed_l", cycles * CONDENSATE_PER_CYCLE_L
		+ (CONDENSATE_PER_CYCLE_L if state == "drain" else 0.0)))
	holdup_l = condensate_l
	vent_bursts_done = int(state_.get("vent_bursts_done", vent_bursts_done))
	timer_s = state_.get("timer_s", timer_s)
	press.value = press_pa
