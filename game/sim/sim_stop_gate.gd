class_name SimStopGate
extends SimVialMount
## A pin across the track, spring-extended: it holds every vial that
## reaches it until its coil is energized, which pulls the pin clear. A
## lost signal is a held line. A pin coming down onto a vial drops
## behind it. Mirrors sim/vials.py StopGate.

var stroke_s: float = 0.1
var retracted: float = 0.0    # 0 = pin across the track, 100 = clear
var release: SimInputPort


func _init(name_: String, stroke_s_: float = 0.1) -> void:
	super(name_)
	stroke_s = stroke_s_
	release = add_input("release", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("retracted", &"retracted")


var blocking: bool:
	get:
		return retracted < 50.0


func tick(dt: float) -> void:
	retracted = move_toward(retracted, 100.0 if release.value > 0.5 else 0.0, 100.0 * dt / stroke_s)


func state_dict() -> Dictionary:
	return {"retracted": retracted}


func apply_state(state: Dictionary) -> void:
	retracted = float(state.get("retracted", retracted))
