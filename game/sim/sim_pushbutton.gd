class_name SimPushbutton
extends SimComponent
## A pushbutton on a local control station. Momentary by default: the
## contact follows the button while it is held, which in a scanned
## plant means for a short hold after a press. A maintained button (a
## selector) toggles on each press. Normally closed for a STOP, so the
## circuit is made until someone presses it — the seal-in a start/stop
## station relies on. Mirrors sim/components.py Pushbutton.

const HOLD_S := 0.6

var momentary: bool
var normally_closed: bool
var pressed: bool = false
var presses: int = 0
var _hold_left: float = 0.0

var contact: SimOutputPort


func _init(name_: String, momentary_: bool = true, normally_closed_: bool = false) -> void:
	super(name_)
	momentary = momentary_
	normally_closed = normally_closed_
	contact = add_output("contact", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("pressed", &"pressed")
	add_observable("presses", &"presses")
	tick(0.0)


## A finger on the button: a hold for a momentary one, a toggle for a
## maintained one.
func press() -> void:
	presses += 1
	if momentary:
		_hold_left = HOLD_S
		pressed = true
	else:
		pressed = not pressed


func tick(dt: float) -> void:
	if momentary:
		_hold_left = maxf(0.0, _hold_left - dt)
		pressed = _hold_left > 0.0
	contact.value = 1.0 if pressed != normally_closed else 0.0


func state_dict() -> Dictionary:
	return {"pressed": pressed, "presses": presses}


func apply_state(state: Dictionary) -> void:
	presses = int(state.get("presses", presses))
	if not momentary:
		pressed = bool(state.get("pressed", pressed))
	tick(0.0)
