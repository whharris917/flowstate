class_name SimBranch
extends RefCounted
## One flow path between two nodes of the hydraulic network. Mirrors
## sim/hydraulics.py Branch.
##
## Sign convention everywhere: dp is P(node_a) - P(node_b), and a
## positive flow runs from a to b.
##
## The solver asks three questions of every branch every Newton
## iteration -- what flows, what the slope is, and whether there is a
## path at all -- and in GDScript the method calls cost more than the
## arithmetic. So evaluate() answers all three at once into q, g and
## conducting, and the solver reads the fields. The per-question
## methods stay for the tests and for anything that only wants one.

var node_a: int
var node_b: int
var branch_name: String
var flow_lps: float = 0.0  # filled in by the solve

# Answers from the last evaluate(), at the pressures it was given.
var q: float = 0.0
var g: float = 0.0
var conducting: bool = false


func _init(node_a_: int, node_b_: int, name_: String = "") -> void:
	node_a = node_a_
	node_b = node_b_
	branch_name = name_


func flow(_dp: float) -> float:
	push_error("SimBranch.flow is abstract")
	return 0.0


## dQ/d(dp). Newton needs the slope, not an exact derivative: an
## approximate one costs an iteration, never correctness.
func conductance(_dp: float) -> float:
	push_error("SimBranch.conductance is abstract")
	return 0.0


## Whether material can actually cross this branch right now.
##
## Kept separate from conductance because the two answer different
## questions. Connectivity asks "is there a path?", and a shut valve is
## a wall whatever slope it reports. Newton asks "which way should I
## step?", and near a kink the useful slope is the one on the far side
## of it.
func is_conducting(dp: float) -> bool:
	return conductance(dp) > SimHydraulics.CONDUCTING_EPS


# Most branches care only about the difference across them. A pump is
# the exception: it also cares how close its suction is to a vacuum,
# because that is what decides whether it is pumping or cavitating.
# These hand the absolute pressures over so it can ask.

func flow_at(pa: float, pb: float) -> float:
	return flow(pa - pb)


func conductance_at(pa: float, pb: float) -> float:
	return conductance(pa - pb)


func is_conducting_at(pa: float, pb: float) -> bool:
	return is_conducting(pa - pb)


## All three answers in one call. Subclasses override this inline.
func evaluate(pa: float, pb: float) -> void:
	q = flow_at(pa, pb)
	g = conductance_at(pa, pb)
	conducting = is_conducting_at(pa, pb)
