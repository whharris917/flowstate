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
## How strongly a node cut off from every fixed pressure is tied to where
## it stands, relative to its own slope: enough to fix an island's common
## level, too little to hold its liquid still. Mirrors ISLAND_TIE.
const ISLAND_TIE := 1e-6


## Pressure at the bottom of a column of liquid this deep.
static func static_head_pa(depth_m: float) -> float:
	return HEAD_PA_PER_M * maxf(depth_m, 0.0)


## A pipe's resistance follows its length and size (director,
## 2026-09-22): Darcy-Weisbach with one friction factor, plus a loss
## coefficient per quarter-turn of bend, dP = (f*L/D + K*bends) * rho*v^2/2.
## The bore is the nominal size, DN millimetres. The kernel stays
## geometry-free: whoever lays the run measures it and asks this.
## Mirrors sim/hydraulics.py pipe_k.
const FRICTION_FACTOR := 0.02     # clean commercial pipe, turbulent
const BEND_K := 0.3               # one long-radius 90-degree bend


## Pa per (L/s)^2 for a run `length_m` long at `dn`, turning through
## `bend_quarters` right angles in all.
static func pipe_k(length_m: float, dn: int, bend_quarters: float = 0.0) -> float:
	var d := float(dn) / 1000.0
	var area := PI * d * d / 4.0
	var v_per_lps := 0.001 / area                     # m/s for each L/s
	var dynamic := RHO_KG_PER_M3 / 2.0 * v_per_lps * v_per_lps
	var k := (FRICTION_FACTOR * maxf(length_m, 0.0) / d + BEND_K * maxf(bend_quarters, 0.0)) * dynamic
	return maxf(k, 1e-6)


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


## The pressure drop at which a square-law element passes |q|: the
## inverse of square_law_flow, linear part included. A plateau step aims
## exactly there -- a fixed margin of a pascal through a wide open end is
## a flow a thousand times a drip's, and the step overshoots.
static func drop_for(q: float, k: float) -> float:
	q = absf(q)
	var dp := k * q * q
	if dp >= DP_FLOOR_PA:
		return dp
	return q * sqrt(k * DP_FLOOR_PA)


static func square_law_slope(dp: float, k: float) -> float:
	if absf(dp) >= DP_FLOOR_PA:
		return 1.0 / (2.0 * sqrt(k * absf(dp)))
	return sqrt(DP_FLOOR_PA / k) / DP_FLOOR_PA
