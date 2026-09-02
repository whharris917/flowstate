class_name SimSteamGen
extends SimComponent
## Electrically fired steam generator. Mirrors sim/process.py SteamGen.
##
## Feedwater arrives through the inlet nozzle and the burner needs
## 480 V; is_on fires it. What it holds is a header PRESSURE, and that
## pressure is what pushes steam through anything connected downstream
## — so an exchanger only gets steam if its condensate has somewhere to
## go. Steam is a real material stream of water at the saturation
## temperature; downstream finds out how hot by being piped to it.
##
## Known gap, stated on its page: the drum is a pressure boundary, so
## it hands out whatever steam is drawn and makes up the difference
## from nowhere. The two totals below are what let a balance around
## the plant say so honestly.

const PRESS_FULL_PA := 8.0e5
const PRESS_TAU_S := 10.0
## Saturation temperature, linearised across the operating range:
## atmospheric at no pressure, about 180 C at the 8 bar rating.
const SAT_C_AT_ZERO := 100.0
const SAT_C_AT_FULL := 180.0
## Shutoff head of the boiler feed pump. It has to beat drum pressure
## or the boiler cannot feed itself once it is hot, which is why a real
## BFW pump is the tallest one in the plant: 8 bar of drum is 81 m
## before the suction line has cost anything.
const FEED_HEAD_M := 110.0

var rated_kgps: float
var is_on: bool = false
var making: bool = false
var press_pa: float = 0.0
var starve_s: float = 0.0
var steam_total_l: float = 0.0
var feedwater_total_l: float = 0.0

var inlet: SimInputPort
var power: SimInputPort
var steam: SimOutputPort
var press: SimOutputPort

var _feed: SimPumpCurve = null


func _init(name_: String, rated_kgps_: float = 0.5) -> void:
	super(name_)
	assert(rated_kgps_ > 0.0, "rated_kgps must be positive")
	rated_kgps = rated_kgps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	steam = add_output("steam", SimTypes.PortKind.PROCESS_MATERIAL)
	press = add_output("press", SimTypes.PortKind.PROCESS_PRESSURE)
	add_observable("press_pa", &"press_pa")
	add_observable("starve_s", &"starve_s")
	add_observable("sat_temp_c", &"sat_temp_c")
	add_observable("steam_lps", &"steam_lps")
	add_observable("steam_total_l", &"steam_total_l")
	add_observable("feedwater_total_l", &"feedwater_total_l")


## Saturation temperature at the current header pressure. This is the
## ceiling on anything the steam is used to heat.
var sat_temp_c: float:
	get:
		return SAT_C_AT_ZERO + (SAT_C_AT_FULL - SAT_C_AT_ZERO) * (press_pa / PRESS_FULL_PA)

var steam_lps: float:
	get:
		return maxf(-steam.flow_lps, 0.0)

var feedwater_lps: float:
	get:
		return maxf(inlet.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# The feed pump discharges into the drum, and the drum IS the steam
	# nozzle -- there is no boiler inventory, so feedwater arriving and
	# steam leaving are two flows at one node. Giving the drum its own
	# node instead would dead-end the feedwater: a node with a single
	# branch can carry no flow, so the boiler could never take water
	# and would starve for ever.
	_feed = net.add_branch(SimPumpCurve.new(node["inlet"], node["steam"],
		SimHydraulics.static_head_pa(FEED_HEAD_M), rated_kgps, comp_name + ".feed")) as SimPumpCurve


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	var firing := is_on and power.value > 0.5
	if _feed != null:
		_feed.running = firing
	# The drum holds header pressure: that is what drives steam
	# anywhere at all, and it is also what the feed pump has to push
	# against, which is why a hot boiler feeds more slowly.
	net.set_pressure(node["steam"], press_pa, true)


func supplied_stream(port_name: String) -> SimStream:
	if port_name == "steam":
		return SimStream.pure(SimSpecies.WATER, 1.0, sat_temp_c)
	return null


func tick(dt: float) -> void:
	var wet := feedwater_lps > 1e-6
	var firing := is_on and power.value > 0.5
	if firing and not wet:
		starve_s += dt  # firing dry: the operator's problem
	making = firing and wet
	var rate := feedwater_lps if making else 0.0
	var target := PRESS_FULL_PA * minf(rate / rated_kgps, 1.0)
	press_pa += (target - press_pa) * dt / PRESS_TAU_S
	press.value = press_pa
	steam_total_l += steam_lps * dt
	feedwater_total_l += feedwater_lps * dt


func state_dict() -> Dictionary:
	return {"is_on": is_on, "press_pa": press_pa, "starve_s": starve_s,
		"steam_total_l": steam_total_l, "feedwater_total_l": feedwater_total_l}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	press_pa = state.get("press_pa", press_pa)
	starve_s = state.get("starve_s", starve_s)
	steam_total_l = state.get("steam_total_l", steam_total_l)
	feedwater_total_l = state.get("feedwater_total_l", feedwater_total_l)
	press.value = press_pa
