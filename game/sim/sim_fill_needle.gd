class_name SimFillNeedle
extends SimVialMount
## An open end pointing straight down: a filling needle on its stand.
## Its node vents to the air at the tip's height, one way, and what
## leaves falls into the vial under it -- or, with no vial there or the
## vial brimful, onto the track, counted as spilled. With no track under
## it, an open vessel the plant finds below catches it as it would an
## open pipe end. The valve upstream is the dose control; the needle
## only has a bore. Mirrors sim/vials.py FillNeedle.
##
##     Q = Cv * sqrt(dP / 1 bar), out to the air at the tip, one way

var cv_lps: float = 0.05
var elevation_m: float = 1.0
var delivered_l: float = 0.0
var spilled_l: float = 0.0
var catch_vial: SimVial = null
## An open vessel under the tip, named by the plant (the open pipe end's rule).
var catch: SimTank = null
var inlet: SimInputPort
var _vent: SimControlResistance = null
var _air: int = -1


func _init(name_: String, cv_lps_: float = 0.05, elevation_m_: float = 1.0) -> void:
	super(name_)
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	cv_lps = cv_lps_
	elevation_m = elevation_m_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("delivered_l", &"delivered_l")
	add_observable("spilled_l", &"spilled_l")
	add_observable("flow_lps", &"flow_lps")


var flow_lps: float:
	get:
		return maxf(_vent.flow_lps, 0.0) if _vent != null else 0.0


## What falls from it this scan, L/s: the SpillJet's rate.
func spill_lps() -> float:
	return flow_lps


func lands() -> bool:
	return catch_vial != null or (catch != null and catch.open_top)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_air = net.add_node(SimHydraulics.static_head_pa(elevation_m), true)
	_vent = net.add_branch(SimControlResistance.new(node["inlet"], _air, cv_lps, comp_name)) \
		as SimControlResistance
	_vent.one_way = true


func update_hydraulics(net: SimNetwork, _node: Dictionary) -> void:
	if _air >= 0:
		net.set_pressure(_air, SimHydraulics.static_head_pa(elevation_m), true)
	if _vent != null:
		_vent.cv_lps = cv_lps
		_vent.opening = 1.0


## The stream falls into a vial's mouth only: its neck is about half its
## width, so the vial must stand within a quarter of its diameter of the
## tip. On a star wheel, the pocket at its station while at rest.
func sense(carrier: SimVialCarrier) -> void:
	var found: SimVial = null
	if carrier is SimStarWheel:
		var vial := carrier.vial_near(s_m, 0.3)
		if vial != null and not vial.capped:
			found = vial
	else:
		for pair: Array in carrier.vials():
			var vial: SimVial = pair[0]
			if absf(float(pair[1]) - s_m) <= vial.diameter_m * 0.25 and not vial.capped:
				found = vial
	catch_vial = found


func tick(dt: float) -> void:
	var q := flow_lps
	if q <= 0.0:
		return
	var litres := q * dt
	var stream := inlet.stream if inlet.stream != null else SimStream.pure(SimSpecies.WATER, q)
	if catch_vial != null:
		var over := catch_vial.add(stream, litres)
		delivered_l += litres - over
		spilled_l += over
	elif catch != null and catch.open_top:
		catch.receive(stream.with_flow(q))
		delivered_l += litres
	else:
		spilled_l += litres


func state_dict() -> Dictionary:
	return {"delivered_l": delivered_l, "spilled_l": spilled_l, "elevation_m": elevation_m}


func apply_state(state: Dictionary) -> void:
	delivered_l = float(state.get("delivered_l", delivered_l))
	spilled_l = float(state.get("spilled_l", spilled_l))
	elevation_m = float(state.get("elevation_m", elevation_m))
