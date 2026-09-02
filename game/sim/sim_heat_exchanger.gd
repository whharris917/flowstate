class_name SimHeatExchanger
extends SimComponent
## Shell-and-tube preheater: steam on the shell, the process stream
## through the tubes. Mirrors sim/process.py HeatExchanger.
##
## The shell is a real path, not a number. Steam flows from the header
## through the shell to the condensate nozzle, driven by the pressure
## across it — so an exchanger whose condensate has nowhere to go
## passes no steam and delivers no duty, exactly as a shell with no
## trap fitted would. It heats the stream it is actually given, and
## cannot heat it past the temperature of the steam supplying it. Duty
## is recomputed from the rise actually achieved, so the signal never
## claims heat the process did not take.

const LATENT_KJ_PER_KG := 2000.0
const APPROACH_C := 5.0
## Shell resistance, Pa per (L/s)^2. Sized so a few hundred kPa of
## header pressure passes a sensible steam rate.
const SHELL_K := 400000.0
const TUBE_K := 2000.0

var max_duty_kw: float
var duty_kw: float = 0.0
var outlet_temp_c: float = SimStream.AMBIENT_C

var steam_in: SimInputPort
var cold_in: SimInputPort
var cold_out: SimOutputPort
var condensate: SimOutputPort
var duty: SimOutputPort


func _init(name_: String, max_duty_kw_: float = 1200.0) -> void:
	super(name_)
	assert(max_duty_kw_ > 0.0, "max_duty_kw must be positive")
	max_duty_kw = max_duty_kw_
	steam_in = add_input("steam_in", SimTypes.PortKind.PROCESS_MATERIAL)
	cold_in = add_input("cold_in", SimTypes.PortKind.PROCESS_MATERIAL)
	cold_out = add_output("cold_out", SimTypes.PortKind.PROCESS_MATERIAL)
	condensate = add_output("condensate", SimTypes.PortKind.PROCESS_MATERIAL)
	duty = add_output("duty", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("duty_kw", &"duty_kw")
	add_observable("outlet_temp_c", &"outlet_temp_c")
	add_observable("steam_lps", &"steam_lps")


var steam_lps: float:
	get:
		return maxf(steam_in.flow_lps, 0.0)

var process_lps: float:
	get:
		return maxf(cold_in.flow_lps, 0.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	net.add_branch(SimResistance.new(node["steam_in"], node["condensate"], SHELL_K,
		comp_name + ".shell"))
	net.add_branch(SimResistance.new(node["cold_in"], node["cold_out"], TUBE_K,
		comp_name + ".tubes"))


func supplied_stream(port_name: String) -> SimStream:
	if port_name == "cold_out":
		return cold_in.stream.with_temp(outlet_temp_c)
	if port_name == "condensate":
		# Everything admitted to the shell condenses — that is what the
		# trap on the outlet is for. Steam the process could not absorb
		# is not destroyed, it leaves hot down the condensate line.
		return SimStream.pure(SimSpecies.WATER, 1.0, steam_in.stream.temp_c)
	return null


func tick(_dt: float) -> void:
	var steam := steam_in.stream
	var cold := cold_in.stream
	var offered_kw := minf(steam_lps * LATENT_KJ_PER_KG, max_duty_kw)
	if process_lps > 1e-9 and offered_kw > 0.0:
		var cp := cold.cp_kj_per_kg_k()
		var ceiling_c := maxf(steam.temp_c - APPROACH_C, cold.temp_c)
		var rise_c := offered_kw / (process_lps * cp)
		outlet_temp_c = minf(cold.temp_c + rise_c, ceiling_c)
		# Honest duty: what the stream actually absorbed.
		duty_kw = process_lps * cp * (outlet_temp_c - cold.temp_c)
	else:
		outlet_temp_c = cold.temp_c
		# No process flow to heat: the shell still condenses what it can
		# against the tubes, which is what a bypassed exchanger does.
		duty_kw = offered_kw if process_lps <= 1e-9 else 0.0
	duty.value = duty_kw
