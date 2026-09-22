class_name SimFixedFlow
extends SimBranch
## A machine that sets its own throughput: a metering pump, or a unit
## with its own feed pump inside it. It takes what it takes and the
## network works around it, which is what a positive-displacement
## machine does until something cavitates. Mirrors sim/hydraulics.py
## FixedFlow.
##
## Its conductance is zero -- pressure does not change what it does --
## but it is emphatically CONDUCTING. Material crosses it, so whatever
## it discharges into has a pressure to find rather than being
## hydraulically adrift. Reading its flat slope as a wall is what
## stopped a dryer ever pushing cake into a hopper: the receiving
## nozzle sat behind a check that had not cracked yet, the solver
## decided nothing could reach it, and the two ends waited for each
## other for ever.
##
## What it draws, though, has to be there (2026-09-22): drawing from a
## line nothing supplies, it starves as its suction nears a hard vacuum,
## the pump's taper over the same band. Imposed regardless, the vial
## filler "filled" from a silo whose outlet stood above the liquid, and
## every millilitre was an imbalance the solve could never close. A
## machine drawing from its own fixed bowl or drum never nears vacuum
## and is unchanged. The flow depends on the suction alone, so the
## branch is two-sided: all of its slope on the a side, none on the b.

const STARVE_BAND_PA := SimPumpCurve.CAVITATION_BAND_PA

var lps: float


func _init(node_a_: int, node_b_: int, lps_: float = 0.0, name_: String = "") -> void:
	super(node_a_, node_b_, name_)
	lps = lps_
	two_sided = true


## How much of its rate the suction lets it draw, 0 to 1.
func supply(suction_pa: float) -> float:
	return clampf((suction_pa - SimHydraulics.MIN_PRESSURE_PA) / STARVE_BAND_PA, 0.0, 1.0)


func flow(_dp: float) -> float:
	return lps


func conductance(_dp: float) -> float:
	return 0.0


func is_conducting(_dp: float) -> bool:
	return true


func flow_at(pa: float, _pb: float) -> float:
	return lps * supply(pa)


func conductance_at(pa: float, _pb: float) -> float:
	var s := supply(pa)
	return lps / STARVE_BAND_PA if s > 0.0 and s < 1.0 else 0.0


func is_conducting_at(_pa: float, _pb: float) -> bool:
	return true


func evaluate(pa: float, _pb: float) -> void:
	var s := supply(pa)
	q = lps * s
	g = lps / STARVE_BAND_PA if s > 0.0 and s < 1.0 else 0.0
	gb = 0.0
	conducting = true
