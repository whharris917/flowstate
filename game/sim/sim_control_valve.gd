class_name SimControlValve
extends SimComponent
## Air-actuated control valve: 0-100 % analog command through a
## first-order positioner into flow (position/100 * cv_lps). It passes
## only what its supply offers: wire an upstream level in and draw
## back — an empty header flows nothing no matter the command.
## Mirrors sim/components.py ControlValve.

var cv_lps: float
var tau_s: float
var position: float = 0.0   # percent, follows the command with a lag
var flow_lps: float = 0.0

var cmd: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort
var draw: SimOutputPort


func _init(name_: String, cv_lps_ := 6.0, tau_s_ := 1.0) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	assert(tau_s_ > 0.0, "tau_s must be positive")
	cv_lps = cv_lps_
	tau_s = tau_s_
	cmd = add_input("cmd", SimTypes.PortKind.SIGNAL_ANALOG)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("position", &"position")
	add_observable("flow_lps", &"flow_lps")


func tick(dt: float) -> void:
	var target := clampf(cmd.value, 0.0, 100.0)
	position += (target - position) * dt / tau_s
	# The valve passes what it is opened for, or what the header can
	# actually give it, whichever is less. Material through a valve is
	# unchanged: same temperature, same composition, different rate.
	var offered := inlet.stream
	flow_lps = minf(position / 100.0 * cv_lps, offered.flow_lps)
	outlet.stream = offered.with_flow(flow_lps)
	draw.value = flow_lps


func state_dict() -> Dictionary:
	return {"position": position}


func apply_state(state: Dictionary) -> void:
	position = state.get("position", position)
