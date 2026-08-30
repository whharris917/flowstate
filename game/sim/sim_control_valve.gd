class_name SimControlValve
extends SimComponent
## Air-actuated control valve: 0-100 % analog command through a
## first-order positioner into flow (position/100 * cv_lps). Draws
## from an unlimited supply main for now, like the pump. Mirrors
## sim/components.py ControlValve.

var cv_lps: float
var tau_s: float
var position: float = 0.0   # percent, follows the command with a lag

var cmd: SimInputPort
var flow: SimOutputPort


func _init(name_: String, cv_lps_ := 6.0, tau_s_ := 1.0) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	assert(tau_s_ > 0.0, "tau_s must be positive")
	cv_lps = cv_lps_
	tau_s = tau_s_
	cmd = add_input("cmd", SimTypes.PortKind.SIGNAL_ANALOG)
	flow = add_output("flow", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("position", &"position")


func tick(dt: float) -> void:
	var target := clampf(cmd.value, 0.0, 100.0)
	position += (target - position) * dt / tau_s
	flow.value = position / 100.0 * cv_lps


func state_dict() -> Dictionary:
	return {"position": position}


func apply_state(state: Dictionary) -> void:
	position = state.get("position", position)
	flow.value = position / 100.0 * cv_lps
