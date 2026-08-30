class_name SimPowerSupply
extends SimComponent
## Control power supply: 480VAC in, 24VDC out. The cabinet's PSU —
## controllers ride on it, and it dies with its feeder. Mirrors
## sim/components.py PowerSupply.

var ac_in: SimInputPort
var dc_out: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	ac_in = add_input("ac_in", SimTypes.PortKind.POWER, "480VAC")
	dc_out = add_output("dc_out", SimTypes.PortKind.POWER, "24VDC")


func tick(_dt: float) -> void:
	dc_out.value = 1.0 if ac_in.value > 0.5 else 0.0
