class_name SimCapper
extends SimVialMount
## A capping head over one spot: while its command is on and an uncapped
## vial stands under it, it takes a cap from its chute and crimps it on
## over cap_s. Its contact makes while the vial under it is capped.
## Mirrors sim/vials.py Capper.

var cap_s: float = 0.8
var progress: float = 0.0
var caps_used: int = 0
var _vial: SimVial = null
var command: SimInputPort
var power: SimInputPort
var capped: SimOutputPort


func _init(name_: String, cap_s_: float = 0.8) -> void:
	super(name_)
	assert(cap_s_ > 0.0, "cap_s must be positive")
	cap_s = cap_s_
	command = add_input("cap", SimTypes.PortKind.SIGNAL_DISCRETE)
	power = add_input("power", SimTypes.PortKind.POWER, "24VDC")
	capped = add_output("capped", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("caps_used", &"caps_used")


## Whether the head is coming down on a vial now, for the view.
var working: bool:
	get:
		return progress > 0.0


func sense(carrier: SimVialCarrier) -> void:
	var vial := carrier.vial_near(s_m, spot_tol(carrier, 0.004))
	if vial != _vial:
		progress = 0.0
	_vial = vial


func tick(dt: float) -> void:
	if _vial != null and not _vial.capped and command.value > 0.5 and power.value > 0.5:
		progress += dt / cap_s
		if progress >= 1.0:
			_vial.capped = true
			caps_used += 1
			progress = 0.0
	capped.value = 1.0 if _vial != null and _vial.capped else 0.0


func state_dict() -> Dictionary:
	return {"caps_used": caps_used}


func apply_state(state: Dictionary) -> void:
	caps_used = int(state.get("caps_used", caps_used))
