class_name SimRegulatorResistance
extends SimControlResistance
## A self-acting pressure regulator: a valve whose opening is a
## function of its own downstream pressure, solved with the network
## rather than a scan behind it. Mirrors sim/hydraulics.py
## RegulatorResistance.
##
##     x = clamp((P_set - P_b) / P_band, 0, 1)
##     Q = Cv * x * sqrt(dp / dp_ref)
##
## Why a branch and not a component adjusting a valve each scan: the
## downstream side of a regulator is stiff (an orifice, a shut line),
## so a proportional opening set from last scan's pressure swings from
## shut to full open and back every scan and never settles. Solved
## simultaneously it is one equilibrium, found in a few iterations. The
## slope reported to Newton carries the opening's own dependence on the
## downstream pressure, so a step lands rather than under-shoots.

var set_pa: float
var band_pa: float


func _init(node_a_: int, node_b_: int, cv_lps_: float, set_pa_: float, band_pa_: float,
		name_: String = "") -> void:
	super(node_a_, node_b_, cv_lps_, name_)
	set_pa = set_pa_
	band_pa = maxf(band_pa_, 1.0)
	opening = 1.0
	two_sided = true


func opening_at(pb: float) -> float:
	return clampf((set_pa - pb) / band_pa, 0.0, 1.0)


func flow_at(pa: float, pb: float) -> float:
	opening = opening_at(pb)
	return flow(pa - pb)


## The a side: the seat as it stands, the square law through it.
func conductance_at(pa: float, pb: float) -> float:
	opening = opening_at(pb)
	return conductance(pa - pb)


## The b side: the square law, and the seat closing as the outlet
## rises (dQ/dx * dx/dP_b), which is the stiff part.
func conductance_b_at(pa: float, pb: float) -> float:
	var x := opening_at(pb)
	opening = x
	var gg := conductance(pa - pb)
	if x > 0.0 and x < 1.0:
		gg += absf(flow(pa - pb)) / (x * band_pa)
	return gg


func is_conducting_at(_pa: float, pb: float) -> bool:
	return opening_at(pb) > 1e-4


func evaluate(pa: float, pb: float) -> void:
	opening = opening_at(pb)
	super.evaluate(pa, pb)
	gb = g
	if conducting and opening < 1.0:
		gb += absf(q) / (opening * band_pa)
