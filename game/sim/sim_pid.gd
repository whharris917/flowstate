class_name SimPID
extends SimComponent
## Positional PID on analog signals: derivative on PV, clamped
## integrator for anti-windup, bumpless manual/auto via integrator
## tracking. Output 0-100 % by default — a valve command. Mirrors
## sim/control.py.

var kp: float
var ki: float
var kd: float
var sp: float
var out_min: float
var out_max: float
var mode: String = "auto"
var manual_out: float = 0.0
var output: float = 0.0
var error: float = 0.0

var _integrator: float = 0.0
var _prev_pv: float = 0.0
var _seen_pv: bool = false

var pv: SimInputPort
var out: SimOutputPort


func _init(name_: String, kp_ := 1.0, ki_ := 0.0, kd_ := 0.0, sp_ := 0.0,
		out_min_ := 0.0, out_max_ := 100.0) -> void:
	super(name_)
	assert(out_max_ > out_min_, "out_max must exceed out_min")
	kp = kp_
	ki = ki_
	kd = kd_
	sp = sp_
	out_min = out_min_
	out_max = out_max_
	pv = add_input("pv", SimTypes.PortKind.SIGNAL_ANALOG)
	out = add_output("out", SimTypes.PortKind.SIGNAL_ANALOG)
	add_observable("sp", &"sp")
	add_observable("output", &"output")
	add_observable("error", &"error")


func set_mode(mode_: String) -> void:
	if mode_ in ["auto", "manual"]:
		mode = mode_


func tick(dt: float) -> void:
	var pv_now := pv.value
	if not _seen_pv:
		_prev_pv = pv_now
		_seen_pv = true
	error = sp - pv_now
	if mode == "manual":
		output = clampf(manual_out, out_min, out_max)
		# Track so a later auto transfer is bumpless.
		_integrator = output - kp * error
	else:
		_integrator += ki * error * dt
		var derivative := -kd * (pv_now - _prev_pv) / dt if dt > 0.0 else 0.0
		var raw := kp * error + _integrator + derivative
		output = clampf(raw, out_min, out_max)
		if raw != output:  # clamped: hold the integrator back
			_integrator = output - kp * error - derivative
	_prev_pv = pv_now
	out.value = output


func state_dict() -> Dictionary:
	return {
		"kp": kp, "ki": ki, "kd": kd, "sp": sp, "mode": mode,
		"manual_out": manual_out, "integrator": _integrator, "output": output,
	}


func apply_state(state: Dictionary) -> void:
	kp = state.get("kp", kp)
	ki = state.get("ki", ki)
	kd = state.get("kd", kd)
	sp = state.get("sp", sp)
	mode = str(state.get("mode", mode))
	manual_out = state.get("manual_out", manual_out)
	_integrator = state.get("integrator", _integrator)
	output = state.get("output", output)
	out.value = output
