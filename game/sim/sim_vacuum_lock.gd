class_name SimVacuumLock
extends SimComponent
## Cyclic vacuum transfer lock: pulls down to rough vacuum, dwells,
## re-pressurizes through the main air valve in discrete bursts, then
## dumps the cycle's knocked-out condensate through an automatic
## drainer. press is gauge-able; drain_flow is a real stream to pipe
## to a drain. Needs 480 V; is_on starts the cycle.
## Mirrors sim/process.py VacuumLock.

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
var cycles: int = 0
var vent_bursts_done: int = 0       # lifetime counter; views watch edges
var timer_s: float = 0.0

var power: SimInputPort
var press: SimOutputPort
var drain_flow: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	press = add_output("press", SimTypes.PortKind.PROCESS_PRESSURE)
	drain_flow = add_output("drain_flow", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("press_pa", &"press_pa")
	add_observable("condensate_l", &"condensate_l")
	add_observable("cycles", &"cycles")


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
						state = "drain"
			"drain":
				rate = DRAIN_LPS if condensate_l > 0.0 else 0.0
				condensate_l = maxf(condensate_l - rate * dt, 0.0)
				if condensate_l <= 0.0:
					cycles += 1
					state = "evacuate"
	press.value = press_pa
	drain_flow.value = rate


func state_dict() -> Dictionary:
	return {"is_on": is_on, "state": state, "press_pa": press_pa,
		"condensate_l": condensate_l, "cycles": cycles,
		"vent_bursts_done": vent_bursts_done, "timer_s": timer_s}


func apply_state(state_: Dictionary) -> void:
	is_on = state_.get("is_on", is_on)
	state = str(state_.get("state", state))
	press_pa = state_.get("press_pa", press_pa)
	condensate_l = state_.get("condensate_l", condensate_l)
	cycles = int(state_.get("cycles", cycles))
	vent_bursts_done = int(state_.get("vent_bursts_done", vent_bursts_done))
	timer_s = state_.get("timer_s", timer_s)
	press.value = press_pa
