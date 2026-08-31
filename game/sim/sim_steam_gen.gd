class_name SimSteamGen
extends SimComponent
## Electrically fired steam generator. Feedwater arrives through the
## inlet facade pair; the burner needs 480 V and is toggled with
## is_on. Produces steam at the rated rate and holds a header
## pressure that follows firing first-order — tap it with a gauge.
## Mirrors sim/process.py SteamGen.

const PRESS_FULL_PA := 8.0e5
const PRESS_TAU_S := 10.0

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
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_LEVEL)
	power = add_input("power", SimTypes.PortKind.POWER, "480VAC")
	steam = add_output("steam", SimTypes.PortKind.PROCESS_FLOW)
	press = add_output("press", SimTypes.PortKind.PROCESS_PRESSURE)
	draw = add_output("draw", SimTypes.PortKind.PROCESS_FLOW)
	add_observable("press_pa", &"press_pa")
	add_observable("starve_s", &"starve_s")


func tick(dt: float) -> void:
	var wet := inlet.value > 0.05
	var firing := is_on and power.value > 0.5
	if firing and not wet:
		starve_s += dt  # firing dry: the operator's problem
	making = firing and wet
	var rate := rated_kgps if making else 0.0
	steam.value = rate
	draw.value = rate
	var target := PRESS_FULL_PA * (rate / rated_kgps)
	press_pa += (target - press_pa) * dt / PRESS_TAU_S
	press.value = press_pa


func state_dict() -> Dictionary:
	return {"is_on": is_on, "press_pa": press_pa, "starve_s": starve_s}


func apply_state(state: Dictionary) -> void:
	is_on = state.get("is_on", is_on)
	press_pa = state.get("press_pa", press_pa)
	starve_s = state.get("starve_s", starve_s)
	press.value = press_pa
