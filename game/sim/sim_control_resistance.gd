class_name SimControlResistance
extends SimResistance
## A valve: the same square law, but the coefficient opens and closes.
## Mirrors sim/hydraulics.py ControlResistance.
##
##     Q = Cv * f(x) * sqrt(dp)
##
## cv_lps is the flow at full open across the reference drop, so the
## number a player sizes stays the familiar one. Shut, it passes
## nothing at all rather than a very large resistance, so a closed
## valve is genuinely closed.
##
## One-way (2026-09-22), it passes from a to b only: an open drain to an
## atmospheric sewer, which under suction draws air, never sewer water
## (it had passed 3.46 L/s backwards for a scan onto a pump's suction,
## 0.17 L from nowhere). Backwards it passes nothing and joins nothing,
## but reports the open side's slope, as the check valve does, so
## Newton knows where the wall is.

const REF_DROP_PA := 100000.0  # 1 bar, the usual sizing basis

var cv_lps: float
var opening: float = 0.0  # 0..1, set from the positioner each tick
var one_way: bool = false


func _init(node_a_: int, node_b_: int, cv_lps_: float, name_: String = "") -> void:
	# k such that Q = cv_lps at the reference drop.
	super(node_a_, node_b_, REF_DROP_PA / pow(maxf(cv_lps_, SimHydraulics.EPS), 2.0), name_)
	cv_lps = cv_lps_


func _k_now() -> float:
	var effective := cv_lps * opening
	return REF_DROP_PA / pow(maxf(effective, SimHydraulics.EPS), 2.0)


func flow(dp: float) -> float:
	if opening <= 1e-4 or (one_way and dp <= 0.0):
		return 0.0
	return SimHydraulics.square_law_flow(dp, _k_now())


func conductance(dp: float) -> float:
	if opening <= 1e-4:
		return 0.0
	return SimHydraulics.square_law_slope(dp, _k_now())


func is_conducting(dp: float) -> bool:
	return opening > 1e-4 and (not one_way or dp > 0.0)


func is_conducting_at(pa: float, pb: float) -> bool:
	return opening > 1e-4 and (not one_way or pa > pb)


func evaluate(pa: float, pb: float) -> void:
	if opening <= 1e-4:
		q = 0.0
		g = 0.0
		conducting = false
		return
	var kk := _k_now()
	var dp := pa - pb
	conducting = not one_way or dp > 0.0
	if dp >= SimHydraulics.DP_FLOOR_PA:
		q = sqrt(dp / kk)
		g = 1.0 / (2.0 * sqrt(kk * dp))
	elif dp <= -SimHydraulics.DP_FLOOR_PA:
		q = 0.0 if one_way else -sqrt(-dp / kk)
		g = 1.0 / (2.0 * sqrt(-kk * dp))
	else:
		var linear := sqrt(SimHydraulics.DP_FLOOR_PA / kk) / SimHydraulics.DP_FLOOR_PA
		q = dp * linear if (not one_way or dp > 0.0) else 0.0
		g = linear
