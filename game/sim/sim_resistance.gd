class_name SimResistance
extends SimBranch
## A pipe run, a fitting, an open drain: anything that turns pressure
## into nothing but noise and heat. Mirrors sim/hydraulics.py
## Resistance.
##
##     Q = sign(dp) * sqrt(|dp| / k)
##
## k is in Pa per (L/s)^2, so k = 1000 means one litre a second costs a
## kilopascal. Square law, as turbulent flow is.

var k: float
var _linear: float  # slope of the straight line below the floor


func _init(node_a_: int, node_b_: int, k_pa_per_lps2: float, name_: String = "") -> void:
	super(node_a_, node_b_, name_)
	set_k(k_pa_per_lps2)


func set_k(k_pa_per_lps2: float) -> void:
	k = maxf(k_pa_per_lps2, SimHydraulics.EPS)
	_linear = sqrt(SimHydraulics.DP_FLOOR_PA / k) / SimHydraulics.DP_FLOOR_PA


func flow(dp: float) -> float:
	return SimHydraulics.square_law_flow(dp, k)


func conductance(dp: float) -> float:
	return SimHydraulics.square_law_slope(dp, k)


func is_conducting(_dp: float) -> bool:
	return true  # a pipe always has a path through it


func is_conducting_at(_pa: float, _pb: float) -> bool:
	return true


## The square law, linearised through zero, inline.
func evaluate(pa: float, pb: float) -> void:
	var dp := pa - pb
	conducting = true
	if dp >= SimHydraulics.DP_FLOOR_PA:
		q = sqrt(dp / k)
		g = 1.0 / (2.0 * sqrt(k * dp))
	elif dp <= -SimHydraulics.DP_FLOOR_PA:
		q = -sqrt(-dp / k)
		g = 1.0 / (2.0 * sqrt(-k * dp))
	else:
		q = dp * _linear
		g = _linear
