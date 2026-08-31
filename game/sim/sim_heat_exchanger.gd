class_name SimHeatExchanger
extends SimComponent
## Shell-and-tube preheater: steam on the shell, the process stream
## through the tubes (cold_in -> cold_out, one scan). It heats the
## stream it is actually given, and cannot heat it past the temperature
## of the steam supplying it — so an undersized header shows up as a
## process that will not come up to heat however long it runs. Duty is
## recomputed from the rise actually achieved, so the signal never
## claims heat the process did not take. Mirrors sim/process.py.

const LATENT_KJ_PER_KG := 2000.0
const APPROACH_C := 5.0

var max_duty_kw: float
var duty_kw: float = 0.0
var outlet_temp_c: float = SimStream.AMBIENT_C

var steam_in: SimInputPort
var cold_in: SimInputPort
var cold_out: SimOutputPort
var condensate: SimOutputPort
var duty: SimOutputPort


func _init(name_: String, max_duty_kw_ := 1200.0) -> void:
	super(name_)
	assert(max_duty_kw_ > 0.0, "max_duty_kw must be positive")
	max_duty_kw = max_duty_kw_
	steam_in = add_input("steam_in", SimTypes.PortKind.PROCESS_STREAM)
	cold_in = add_input("cold_in", SimTypes.PortKind.PROCESS_STREAM)
	cold_out = add_output("cold_out", SimTypes.PortKind.PROCESS_STREAM)
	condensate = add_output("condensate", SimTypes.PortKind.PROCESS_STREAM)
	duty = add_output("duty", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("duty_kw", &"duty_kw")
	add_observable("outlet_temp_c", &"outlet_temp_c")


func tick(_dt: float) -> void:
	var steam := steam_in.stream
	var cold := cold_in.stream
	var offered_kw := minf(steam.flow_lps * LATENT_KJ_PER_KG, max_duty_kw)

	if cold.is_flowing() and offered_kw > 0.0:
		var cp := cold.cp_kj_per_kg_k()
		var ceiling_c := maxf(steam.temp_c - APPROACH_C, cold.temp_c)
		var rise_c := offered_kw / (cold.flow_lps * cp)
		outlet_temp_c = minf(cold.temp_c + rise_c, ceiling_c)
		# Honest duty: what the stream actually absorbed.
		duty_kw = cold.flow_lps * cp * (outlet_temp_c - cold.temp_c)
	else:
		outlet_temp_c = cold.temp_c
		# No process flow to heat: the shell still condenses what it can
		# against the tubes, which is what a bypassed exchanger does.
		duty_kw = offered_kw if not cold.is_flowing() else 0.0

	cold_out.stream = cold.with_temp(outlet_temp_c)
	# Everything admitted to the shell condenses — that is what the trap
	# on the outlet is for. Steam the process could not absorb is not
	# destroyed, it leaves hot down the condensate line, so over-steaming
	# shows up as wasted feedwater on a drain totalizer.
	condensate.stream = SimStream.pure(SimSpecies.WATER, steam.flow_lps, steam.temp_c)
	duty.value = duty_kw
