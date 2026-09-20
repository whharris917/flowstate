class_name SimCap
extends SimComponent
## A pipe cap: a two-nozzle fitting that is one hydraulic node, a
## blind end while only one nozzle carries a line and a plain
## coupling once both do. A cut leaves one on each side of the cut
## (director, 2026-09-13: cutting is putting a closed cap on a pipe
## until it is connected again). A node with one branch carries no
## flow, so a capped line stands at pressure and moves nothing.
## Open (director, 2026-09-20: a line laid to nowhere "simply becomes
## an overflow point at atmospheric pressure"), the cap is an open
## pipe end: its node vents to the air at its own height through a
## wide free discharge, and what arrives spills and is totalled.
## Mirrors sim/components.py Cap.

const VENT_CV_LPS := 60.0   # an open bore: the line's own resistance limits the spill

var open: bool = false
var elevation_m: float = 0.0   # the height of the open end, for the air it vents to
var spilled_l: float = 0.0
## What lands in an open vessel below (director, 2026-09-20: fill an
## open tank from a line ending in the air above it). The plant names
## the vessel under the end; the kernel hands it the stream.
var catch: SimTank = null
var delivered_l: float = 0.0
var _vent: SimControlResistance = null
var inlet: SimInputPort


func _init(name_: String) -> void:
	super(name_)
	inlet = add_input("a", SimTypes.PortKind.PROCESS_MATERIAL)
	add_output("b", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("spilled_l", &"spilled_l")
	add_observable("delivered_l", &"delivered_l")


func shared_node_ports() -> Array:
	return [material_ports().keys()]


## The spill this scan, L/s: the flow out of the vent while open.
func spill_lps() -> float:
	return maxf(_vent.flow_lps, 0.0) if open and _vent != null else 0.0


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	var air := net.add_node(SimHydraulics.static_head_pa(elevation_m), true)
	_vent = net.add_branch(SimControlResistance.new(node["a"], air, VENT_CV_LPS, comp_name)) \
		as SimControlResistance


func update_hydraulics(_net: SimNetwork, _node: Dictionary) -> void:
	if _vent != null:
		_vent.cv_lps = VENT_CV_LPS
		_vent.opening = 1.0 if open else 0.0


## Whether the spill has somewhere to go: an open-topped vessel under
## the end. Otherwise it is lost to the ground and counted.
func lands() -> bool:
	return catch != null and catch.open_top


func tick(dt: float) -> void:
	var q := spill_lps()
	if q <= 0.0:
		return
	if lands():
		catch.receive((inlet.stream if inlet.stream != null else SimStream.pure(SimSpecies.WATER, q)).with_flow(q))
		delivered_l += q * dt
	else:
		spilled_l += q * dt


func state_dict() -> Dictionary:
	return {"open": open, "spilled_l": spilled_l, "delivered_l": delivered_l, "elevation_m": elevation_m}


func apply_state(state: Dictionary) -> void:
	open = bool(state.get("open", open))
	spilled_l = float(state.get("spilled_l", spilled_l))
	delivered_l = float(state.get("delivered_l", delivered_l))
	elevation_m = float(state.get("elevation_m", elevation_m))
