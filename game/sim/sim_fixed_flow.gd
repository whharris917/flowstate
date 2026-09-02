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

var lps: float


func _init(node_a_: int, node_b_: int, lps_: float = 0.0, name_: String = "") -> void:
	super(node_a_, node_b_, name_)
	lps = lps_


func flow(_dp: float) -> float:
	return lps


func conductance(_dp: float) -> float:
	return 0.0


func is_conducting(_dp: float) -> bool:
	return true


func flow_at(_pa: float, _pb: float) -> float:
	return lps


func conductance_at(_pa: float, _pb: float) -> float:
	return 0.0


func is_conducting_at(_pa: float, _pb: float) -> bool:
	return true


func evaluate(_pa: float, _pb: float) -> void:
	q = lps
	g = 0.0
	conducting = true
