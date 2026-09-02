class_name SimHydraulics
## The hydraulic network's constants and the square-law helpers every
## branch shares. Mirrors the module-level part of sim/hydraulics.py.
##
## Before this existed, flow was *asserted*: a pump moved 2 L/s because
## it was labelled a 2 L/s pump, and every consumer announced what it
## took on a draw wire so the supplier could decrement its inventory.
## Here flow is *solved*. Every material nozzle is a node at some
## pressure, every pipe run and every pump or valve is a branch, and
## what flows is whatever satisfies all of them at once.
##
## Units throughout: pressure in Pa gauge, flow in L/s, and one density
## for everything, consistent with the kernel's 1 L = 1 kg basis.

## One density for every liquid, matching the kernel's aqueous basis.
const RHO_KG_PER_M3 := 1000.0
const G := 9.81
## Pa of static head per metre of liquid: 9810, near enough 9.8 kPa/m.
const HEAD_PA_PER_M := RHO_KG_PER_M3 * G

const ATMOSPHERIC_PA := 0.0  # gauge
## Nothing may be pulled below a hard vacuum. A branch demanding more
## than the system can deliver pins its suction node here, which is
## what a component should read as cavitation.
const MIN_PRESSURE_PA := -101300.0

## Below this pressure difference a branch is treated as linear, so the
## Jacobian of a square-law element stays finite through zero flow.
const DP_FLOOR_PA := 1.0
const EPS := 1e-12
## Below this a branch is treated as carrying nothing, for the purpose
## of working out what is connected to what.
const CONDUCTING_EPS := 1e-12


## Pressure at the bottom of a column of liquid this deep.
static func static_head_pa(depth_m: float) -> float:
	return HEAD_PA_PER_M * maxf(depth_m, 0.0)


## Q for a square-law element, linearised through zero.
##
## Below the floor the square law is replaced by the straight line that
## meets it at the floor. The linearisation has to be applied to the
## FLOW as well as to the slope: regularising only the slope leaves
## Newton chasing a target its own derivative disagrees with, and it
## grinds against the iteration cap forever without ever landing.
static func square_law_flow(dp: float, k: float) -> float:
	if absf(dp) >= DP_FLOOR_PA:
		return signf(dp) * sqrt(absf(dp) / k)
	return dp * sqrt(DP_FLOOR_PA / k) / DP_FLOOR_PA


static func square_law_slope(dp: float, k: float) -> float:
	if absf(dp) >= DP_FLOOR_PA:
		return 1.0 / (2.0 * sqrt(k * absf(dp)))
	return sqrt(DP_FLOOR_PA / k) / DP_FLOOR_PA
