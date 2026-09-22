class_name SimNozzleResistance
extends SimResistance
## A vessel nozzle: node_a is the vessel side, node_b the line, so a
## positive flow leaves the vessel. Mirrors sim/hydraulics.py
## NozzleResistance.
##
## What a nozzle passes depends on where it stands relative to the
## liquid (director, 2026-09-22: the nozzle's position on the shell
## belongs in the kernel). Inflow is always free: a line can discharge
## into a vessel through a nozzle above the liquid or under it. Outflow
## needs liquid standing over the nozzle, and submergence (0..1) is how
## much of it does: 1 well under the surface, 0 once the level has
## fallen past it, the ramp between them the same 3 cm the bottom
## nozzle always tailed off over, so an emptying vessel does not
## chatter shut.
##
## Dry, it is a check valve seen from the vessel's side, and it keeps
## the check valve's lesson: no flow out, but the SLOPE reported is the
## open side's, so Newton lands on the crack point instead of stepping
## past it for ever. Connectivity still sees a wall.

const REF_DROP_PA := SimControlResistance.REF_DROP_PA

var cv_lps: float
var submergence: float = 0.0:
	set(value):
		submergence = value
		_k_out = REF_DROP_PA / pow(maxf(cv_lps * value, SimHydraulics.EPS), 2.0)
		_lin_out = sqrt(SimHydraulics.DP_FLOOR_PA / _k_out) / SimHydraulics.DP_FLOOR_PA

var _k_out: float = 1.0
var _lin_out: float = 1.0


func _init(node_a_: int, node_b_: int, cv_lps_: float, name_: String = "") -> void:
	super(node_a_, node_b_, REF_DROP_PA / pow(maxf(cv_lps_, SimHydraulics.EPS), 2.0), name_)
	cv_lps = cv_lps_
	submergence = 0.0


## Size the nozzle: the flow it passes wide open across the reference
## drop. A nozzle takes the size of the line on it.
func set_cv(cv_lps_: float) -> void:
	cv_lps = cv_lps_
	set_k(REF_DROP_PA / pow(maxf(cv_lps_, SimHydraulics.EPS), 2.0))
	submergence = submergence   # the outflow law follows the size


func flow(dp: float) -> float:
	if dp > 0.0:
		if submergence <= 1e-4:
			return 0.0
		return SimHydraulics.square_law_flow(dp, _k_out)
	return SimHydraulics.square_law_flow(dp, k)


func conductance(dp: float) -> float:
	if dp > 0.0 and submergence > 1e-4:
		return SimHydraulics.square_law_slope(dp, _k_out)
	# The inflow slope: the branch in force for inflow, and the open
	# side's slope while the nozzle stands dry.
	return SimHydraulics.square_law_slope(dp, k)


func is_conducting(dp: float) -> bool:
	if dp > 0.0:
		return submergence > 1e-4
	return true


## Dry, nothing leaves the vessel: a line node standing below the
## vessel side with liquid arriving must rise past it to pass it in; one
## pulled on (a pump drawing from a vessel gone dry) can get nothing from
## it and falls to where whatever pulls runs out of suction, the
## hard-vacuum floor.
func is_wall() -> bool:
	return true


func crack_target(node: int, pa: float, pb: float, push: float, passing: bool = true) -> float:
	if node == node_b and pb < pa and submergence <= 1e-4:
		if push > 0.0:
			return pa + (SimHydraulics.drop_for(push, k) if passing else 0.0)
		return SimHydraulics.MIN_PRESSURE_PA
	return NAN


func is_conducting_at(pa: float, pb: float) -> bool:
	return is_conducting(pa - pb)


func evaluate(pa: float, pb: float) -> void:
	var dp := pa - pb
	if dp > 0.0:
		if submergence <= 1e-4:
			# Dry: nothing out, the open side's slope, a wall for
			# connectivity.
			conducting = false
			q = 0.0
			g = 1.0 / (2.0 * sqrt(k * dp)) if dp >= SimHydraulics.DP_FLOOR_PA else _linear
			return
		conducting = true
		if dp >= SimHydraulics.DP_FLOOR_PA:
			q = sqrt(dp / _k_out)
			g = 1.0 / (2.0 * sqrt(_k_out * dp))
		else:
			q = dp * _lin_out
			g = _lin_out
		return
	conducting = true
	if dp <= -SimHydraulics.DP_FLOOR_PA:
		q = -sqrt(-dp / k)
		g = 1.0 / (2.0 * sqrt(-k * dp))
	else:
		q = dp * _linear
		g = _linear
