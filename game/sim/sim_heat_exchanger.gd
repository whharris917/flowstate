class_name SimHeatExchanger
extends SimComponent
## Shell-and-tube preheater: steam on the shell, the process stream
## through the tubes (cold_in -> cold_out, one scan). The transferred
## duty (kW) is a real analog output. Mirrors sim/process.py.

const LATENT_KJ_PER_KG := 2000.0

var max_duty_kw: float
var duty_kw: float = 0.0

var steam_in: SimInputPort
var cold_in: SimInputPort
var cold_out: SimOutputPort
var duty: SimOutputPort


func _init(name_: String, max_duty_kw_ := 1200.0) -> void:
	super(name_)
	assert(max_duty_kw_ > 0.0, "max_duty_kw must be positive")
	max_duty_kw = max_duty_kw_
	steam_in = add_input("steam_in", SimTypes.PortKind.PROCESS_FLOW)
	cold_in = add_input("cold_in", SimTypes.PortKind.PROCESS_FLOW)
	cold_out = add_output("cold_out", SimTypes.PortKind.PROCESS_FLOW)
	duty = add_output("duty", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("duty_kw", &"duty_kw")


func tick(_dt: float) -> void:
	duty_kw = minf(steam_in.value * LATENT_KJ_PER_KG, max_duty_kw)
	cold_out.value = cold_in.value
	duty.value = duty_kw
