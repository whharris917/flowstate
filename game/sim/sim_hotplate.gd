class_name SimHotplate
extends SimComponent
## A hotplate stirrer with a temperature probe. Mirrors sim/bench.py
## Hotplate.
##
## The element is on or off (a thermostat relay, so its lamp cycles as a
## real one does) and holds the plate at a target. With no vessel on it
## the target is the setpoint. With one, the probe is in the vessel and
## the target rises above the setpoint in proportion to how far the
## vessel is below it (a cascade, as a probe-mode hotplate does), so the
## plate does not store the heat that would carry the vessel past its
## setpoint. The plate is a lump of metal that heats and cools; heat
## reaches the vessel through its base.

const POWER_W := 600.0
const PLATE_CP := 600.0          # J/K
const PLATE_LOSS := 1.2          # W/K
const TO_VESSEL := 0.8           # W/K, plate to a flat-bottomed vessel
const PLATE_MAX_C := 380.0
const BAND_C := 0.5
const CASCADE := 20.0            # plate degrees above setpoint per degree the vessel is short
const AMBIENT_C := SimMixture.AMBIENT_C

var setpoint_c := 0.0            # at or below the room: heat off
var stir_rpm := 0.0
var plate_c := AMBIENT_C
var heater_on := false
## The vessel standing on the plate, set by the plant from where things
## stand; the only reference between them, so nothing leaks.
var load: SimLabVessel = null
var to_vessel_w := 0.0


func _init(name_: String) -> void:
	super(name_)
	add_observable("plate_c", &"plate_c")
	add_observable("setpoint_c", &"setpoint_c")
	add_observable("stir_rpm", &"stir_rpm")
	add_observable("probe_c", &"probe_c")
	add_observable("heating", &"heating")


var probe_c: float:
	get:
		return load.temp_c if load != null else plate_c

var heating: float:
	get:
		return 1.0 if heater_on else 0.0


func plate_target_c() -> float:
	if load == null:
		return minf(setpoint_c, PLATE_MAX_C)
	var short := setpoint_c - load.temp_c
	return minf(maxf(setpoint_c + CASCADE * short, setpoint_c), PLATE_MAX_C)


func mix_factor() -> float:
	var stir := clampf(stir_rpm / 400.0, 0.0, 1.0)
	return SimMixture.UNSTIRRED + (1.0 - SimMixture.UNSTIRRED) * stir


func tick(dt: float) -> void:
	var wanted := setpoint_c > AMBIENT_C
	var target := plate_target_c()
	if not wanted or plate_c > target + BAND_C:
		heater_on = false
	elif plate_c < target - BAND_C:
		heater_on = true
	var power := POWER_W if heater_on else 0.0
	to_vessel_w = 0.0
	if load != null:
		to_vessel_w = TO_VESSEL * (plate_c - load.temp_c)
		load.heat_w = to_vessel_w
		load.mix = mix_factor()
	var loss := PLATE_LOSS * (plate_c - AMBIENT_C)
	plate_c += (power - to_vessel_w - loss) * dt / PLATE_CP


func state_dict() -> Dictionary:
	return {"setpoint_c": setpoint_c, "stir_rpm": stir_rpm, "plate_c": plate_c,
		"heater_on": heater_on}


func apply_state(state: Dictionary) -> void:
	setpoint_c = float(state.get("setpoint_c", setpoint_c))
	stir_rpm = float(state.get("stir_rpm", stir_rpm))
	plate_c = float(state.get("plate_c", plate_c))
	heater_on = bool(state.get("heater_on", heater_on))
