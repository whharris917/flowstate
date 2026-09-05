class_name SimPilotLight
extends SimComponent
## A pilot light: lit while its lamp circuit is energized, nothing
## more. The thing on a station that tells an operator what the PLC
## believes without a screen. Mirrors sim/components.py PilotLight.

var color: String

var lamp: SimInputPort


func _init(name_: String, color_: String = "green") -> void:
	super(name_)
	color = color_
	lamp = add_input("lamp", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("lit", &"lit")


var lit: bool:
	get:
		return lamp.value > 0.5


func tick(_dt: float) -> void:
	pass
