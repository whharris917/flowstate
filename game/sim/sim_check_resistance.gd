class_name SimCheckResistance
extends SimResistance
## A resistance with a check valve in it: flow from a to b only.
## Mirrors sim/hydraulics.py CheckResistance.
##
## A top-entry nozzle is one of these. The line discharges above the
## liquid, so material can fall in and nothing can come back out,
## which is not a detail: without it an empty vessel will happily
## supply liquid it does not have through the nozzle at its roof.
##
## The flow is one-way. The SLOPE is not, and that distinction is
## load-bearing. A shut check reporting zero slope tells Newton the
## node is insensitive, so it takes a step sized by the pipe alone and
## sails clean past the pressure at which the valve cracks, then back,
## then forwards, until the iteration cap. Reporting the open-side
## slope instead says "there is a wall a few hundred pascals away", and
## it lands on the crack point in two steps. The flow it passes while
## shut is still exactly zero, so nothing is invented; only the step
## length changes. is_conducting keeps connectivity honest, because for
## working out what is joined to what a shut check really is a wall.


func flow(dp: float) -> float:
	return super.flow(dp) if dp > 0.0 else 0.0


func is_conducting(dp: float) -> bool:
	return dp > 0.0


func is_conducting_at(pa: float, pb: float) -> bool:
	return pa > pb


func crack_target(node: int, pa: float, pb: float, push: float) -> float:
	if pa > pb:
		return NAN
	var drop := SimHydraulics.drop_for(push, k)
	if node == node_a and push > 0.0:
		return pb + drop
	if node == node_b and push < 0.0:
		return pa - drop
	return NAN


func evaluate(pa: float, pb: float) -> void:
	var dp := pa - pb
	conducting = dp > 0.0
	if dp >= SimHydraulics.DP_FLOOR_PA:
		q = sqrt(dp / k)
		g = 1.0 / (2.0 * sqrt(k * dp))
	elif dp <= -SimHydraulics.DP_FLOOR_PA:
		q = 0.0
		g = 1.0 / (2.0 * sqrt(-k * dp))
	else:
		q = dp * _linear if dp > 0.0 else 0.0
		g = _linear
