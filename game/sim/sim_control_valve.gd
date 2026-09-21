class_name SimControlValve
extends SimComponent
## Air-actuated control valve: a 0-100 % command through a first-order
## positioner onto a trim that follows the valve equation. Mirrors
## sim/components.py ControlValve.
##
##     Q = Cv * f(x) * sqrt(dP / dP_ref)
##
## Which means its authority is real. Put it in a line whose own
## resistance dominates and opening it further buys almost nothing —
## the classic badly-sized valve, and now a thing the player can
## actually diagnose.

var cv_lps: float
var tau_s: float
var position: float = 0.0   # percent, follows the command with a lag
## Nozzle height above grade, re-derived by the plant from where it
## stands. The drop across a valve is the same whichever way the
## pressures are reckoned, so the elevation changes no flow; it is
## what makes the static pressure at the valve, which a gauge there
## reads, honest (director, 2026-09-21).
var elevation_m: float = 0.0
var inlet_pa: float = 0.0    # static, at the valve's own height
var outlet_pa: float = 0.0

var cmd: SimInputPort
var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimControlResistance = null


func _init(name_: String, cv_lps_: float = 6.0, tau_s_: float = 1.0) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	assert(tau_s_ > 0.0, "tau_s must be positive")
	cv_lps = cv_lps_
	tau_s = tau_s_
	cmd = add_input("cmd", SimTypes.PortKind.SIGNAL_ANALOG)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("position", &"position")
	add_observable("flow_lps", &"flow_lps")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimControlResistance.new(
		node["inlet"], node["outlet"], cv_lps, comp_name)) as SimControlResistance


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	if _branch != null:
		_branch.cv_lps = cv_lps
		_branch.opening = position / 100.0
	var datum := SimHydraulics.static_head_pa(elevation_m)
	inlet_pa = net.pressures[node["inlet"]] - datum
	outlet_pa = net.pressures[node["outlet"]] - datum


func tick(dt: float) -> void:
	var target := clampf(cmd.value, 0.0, 100.0)
	position += (target - position) * dt / tau_s


## The valve's nominal bore, DN: bought at a size, changed only in its
## CONFIGURE tab (director, 2026-09-20: "valves should be size-adjustable
## just like tees").
var dn: int = 50


func state_dict() -> Dictionary:
	return {"position": position, "dn": dn}


func apply_state(state: Dictionary) -> void:
	position = state.get("position", position)
	dn = int(state.get("dn", dn))
