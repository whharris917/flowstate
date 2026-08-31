class_name SimSteamGen
extends SimComponent
## Electrically fired steam generator. Feedwater arrives through the
## inlet facade pair; the burner needs 480 V and is toggled with
## is_on. Produces steam — a real material stream of water at the
## header saturation temperature — and holds a header pressure that
## follows firing first-order. Mirrors sim/process.py SteamGen.

const PRESS_FULL_PA := 8.0e5
const PRESS_TAU_S := 10.0
## Saturation temperature, linearised across the operating range:
## atmospheric at no pressure, about 180 C at the 8 bar rating.
const SAT_C_AT_ZERO := 100.0
const SAT_C_AT_FULL := 180.0

var rated_kgps: float
var is_on: bool = false
var making: bool = false
var press_pa: float = 0.0
var starve_s: float = 0.0

var inlet: SimInputPort
var power: SimInputPort
var steam: SimOutputPort
var press: SimOutputPort
var draw: SimOutputPort


func _init(name_: String, rated_kgps_ := 0.5) -> void:
	super(name_)
	assert(rated_kgps_ > 0.0, "rated_kgps must be positive")
	rated_kgps = rated_kgps_
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_SUPPLY)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	steam = add_output("steam", SimTypes.PortKind.PROCESS_STREAM)
	press = add_output("press", SimTypes.PortKind.PROCESS_PRESSURE)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("press_pa", &"press_pa")
	add_observable("starve_s", &"starve_s")
	add_observable("sat_temp_c", &"sat_temp_c")


## Saturation temperature at the current header pressure. This is the
## ceiling on anything the steam is used to heat.
var sat_temp_c: float:
	get:
		return SAT_C_AT_ZERO + (SAT_C_AT_FULL - SAT_C_AT_ZERO) * (press_pa / PRESS_FULL_PA)


func tick(dt: float) -> void:
	var feed := inlet.stream
	var wet := feed.flow_lps > 1e-9
	var firing := is_on and power.value > 0.5
	if firing and not wet:
		starve_s += dt  # firing dry: the operator's problem
	making = firing and wet
	var rate := minf(rated_kgps, feed.flow_lps) if making else 0.0
	var target := PRESS_FULL_PA * (rate / rated_kgps)
	press_pa += (target - press_pa) * dt / PRESS_TAU_S
	press.value = press_pa
	draw.value = rate
	# Steam is water, hot. Downstream finds out how hot by being piped
	# to it.
	steam.stream = SimStream.pure(SimSpecies.WATER, rate, sat_temp_c)


func state_dict() -> Dictionary:
	return {"is_on": is_on, "press_pa": press_pa, "starve_s": starve_s}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	press_pa = state.get("press_pa", press_pa)
	starve_s = state.get("starve_s", starve_s)
	press.value = press_pa
