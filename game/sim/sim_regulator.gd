class_name SimRegulator
extends SimComponent
## A self-acting pressure-reducing valve: a spring against a diaphragm
## that feels the downstream pressure, throttling the seat as it
## rises. No signal in or out. It holds its outlet near the set
## pressure while the inlet is higher and the flow within its Cv;
## above the set pressure it shuts. Mirrors sim/small_bore.py
## Regulator; the opening is solved with the network
## (SimRegulatorResistance), since one set a scan behind never settles
## against a stiff downstream.
##
##     x = clamp((P_set - P_out) / P_band, 0, 1)
##     Q = Cv * x * sqrt(dP / 1 bar)
##     P_band = max(0.1 * P_set, 5 kPa)

var set_kpa: float
var cv_lps: float
var opening: float = 0.0
var out_kpa: float = 0.0
## Nozzle height above grade, re-derived by the plant from where it
## stands. A regulator holds the static pressure its diaphragm feels,
## at its own height; in the network's piezometric terms that is the
## setting plus rho*g*z, and its gauge reads the static value.
var elevation_m: float = 0.0

var inlet: SimInputPort
var outlet: SimOutputPort

var _branch: SimRegulatorResistance = null


func _init(name_: String, set_kpa_: float = 200.0, cv_lps_: float = 0.5) -> void:
	super(name_)
	assert(set_kpa_ > 0.0, "set_kpa must be positive")
	assert(cv_lps_ > 0.0, "cv_lps must be positive")
	set_kpa = set_kpa_
	cv_lps = cv_lps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("opening", &"opening")
	add_observable("out_kpa", &"out_kpa")
	add_observable("flow_lps", &"flow_lps")


var flow_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


var band_pa: float:
	get:
		return maxf(set_kpa * 1000.0 * 0.1, 5000.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_branch = net.add_branch(SimRegulatorResistance.new(node["inlet"], node["outlet"],
		cv_lps, set_kpa * 1000.0 + SimHydraulics.static_head_pa(elevation_m), band_pa,
		comp_name)) as SimRegulatorResistance


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# Read back for the face and the historian; the branch itself
	# decides the opening as the network is solved. The setting is
	# static, at the regulator's height: piezometric, the setting plus
	# rho*g*z.
	var datum := SimHydraulics.static_head_pa(elevation_m)
	var p_out := net.pressures[node["outlet"]]
	out_kpa = (p_out - datum) / 1000.0
	if _branch != null:
		_branch.cv_lps = cv_lps
		_branch.set_pa = set_kpa * 1000.0 + datum
		_branch.band_pa = band_pa
		opening = _branch.opening_at(p_out)


func tick(_dt: float) -> void:
	pass
