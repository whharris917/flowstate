class_name SimPumpCurve
extends SimBranch
## A centrifugal pump, with the curve that makes it one. Mirrors
## sim/hydraulics.py PumpCurve.
##
##     H(Q) = H0 * (1 - (Q / Qmax)^2)
##
## Head is highest at shutoff and falls away as flow rises, so the pump
## finds its own operating point against whatever the system puts in
## front of it. Ask it to lift more than H0 and it dead-heads: the
## motor spins, the flow is zero, and nothing you do at the control
## valve changes that. A check valve stops it running backwards.

## Flow past which the curve is treated as flat, as a multiple of the
## rating.
const RUNOUT_FACTOR := 1.35
## How far above a hard vacuum the suction has to stay for the pump to
## make its full curve. Inside this band it is losing prime, and at the
## bottom of it it is moving nothing at all.
##
## This is what stops a pump on an empty vessel dragging its suction
## line to vacuum and demanding material anyway. Without it the suction
## pins at the floor, the imbalance can never be driven to zero because
## the node cannot go any lower, and the solve grinds against the
## iteration cap for the rest of the run. A taper rather than a
## cut-off, because Newton cannot follow a cliff.
const CAVITATION_BAND_PA := 20000.0

var head_pa: float
var max_lps: float
var running: bool = false


func _init(node_a_: int, node_b_: int, head_pa_: float, max_lps_: float,
		name_: String = "") -> void:
	super(node_a_, node_b_, name_)
	head_pa = maxf(head_pa_, SimHydraulics.EPS)
	max_lps = maxf(max_lps_, SimHydraulics.EPS)


## How much of its curve it is making, 0 to 1. One whenever there is
## real pressure on the suction, tapering to nothing as that approaches
## a hard vacuum.
func prime(suction_pa: float) -> float:
	var headroom := suction_pa - SimHydraulics.MIN_PRESSURE_PA
	return clampf(headroom / CAVITATION_BAND_PA, 0.0, 1.0)


func flow_at(pa: float, pb: float) -> float:
	return flow(pa - pb) * prime(pa)


func conductance_at(pa: float, pb: float) -> float:
	# Inside the band the suction pressure moves the flow twice over:
	# along the curve, and by how much prime the pump has. Newton needs
	# both terms or it under-steps and grinds -- the same trap as
	# regularising a slope without its flow.
	var p := prime(pa)
	var gg := conductance(pa - pb) * p
	if p > 0.0 and p < 1.0:
		gg += flow(pa - pb) / CAVITATION_BAND_PA
	return gg


func is_conducting_at(pa: float, pb: float) -> bool:
	return is_conducting(pa - pb) and prime(pa) > 0.0


func flow(dp: float) -> float:
	if not running:
		return 0.0
	# dp is suction minus discharge, so the rise the pump must make is
	# -dp. Q = Qmax * sqrt(1 - rise/H0).
	var rise := -dp
	if rise >= head_pa:
		return 0.0  # dead-headed
	# Past the end of the curve a centrifugal pump stops being a pump
	# and is only a fitting, so cap the runout rather than letting a
	# high-pressure header drive it to silly flows.
	return minf(max_lps * sqrt(1.0 - rise / head_pa), max_lps * RUNOUT_FACTOR)


func conductance(dp: float) -> float:
	if not running:
		return 0.0
	var rise := -dp
	if rise >= head_pa:
		return 0.0
	return max_lps / (2.0 * head_pa * sqrt(maxf(1.0 - rise / head_pa, 1e-6)))


func evaluate(pa: float, pb: float) -> void:
	if not running:
		q = 0.0
		g = 0.0
		conducting = false
		return
	var rise := pb - pa
	if rise >= head_pa:
		q = 0.0
		g = 0.0
		conducting = false
		return
	var p := clampf((pa - SimHydraulics.MIN_PRESSURE_PA) / CAVITATION_BAND_PA, 0.0, 1.0)
	var fraction := 1.0 - rise / head_pa
	var on_curve := minf(max_lps * sqrt(fraction), max_lps * RUNOUT_FACTOR)
	q = on_curve * p
	g = max_lps / (2.0 * head_pa * sqrt(maxf(fraction, 1e-6))) * p
	if p > 0.0 and p < 1.0:
		g += on_curve / CAVITATION_BAND_PA
	conducting = p > 0.0
