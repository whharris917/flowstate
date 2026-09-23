class_name SimLoadCell
extends SimVialMount
## A weighing pan under one spot on the track, with its indicator. The
## indicator tares each vial as it settles, so it reads the net fill; its
## analog output is that weight in grams and its setpoint contact makes
## when the fill reaches the target. Mirrors sim/vials.py LoadCell.

var range_g: float = 100.0
var target_g: float = 10.0
var net_g: float = 0.0
var _on_pan: bool = false
var weight: SimOutputPort
var at_target: SimOutputPort


func _init(name_: String, range_g_: float = 100.0, target_g_: float = 10.0) -> void:
	super(name_)
	assert(range_g_ > 0.0, "range_g must be positive")
	range_g = range_g_
	target_g = target_g_
	weight = add_output("weight", SimTypes.PortKind.SIGNAL_ANALOG)
	at_target = add_output("at_target", SimTypes.PortKind.SIGNAL_DISCRETE)
	add_observable("net_g", &"net_g")


func sense(carrier: SimVialCarrier) -> void:
	var vial := carrier.vial_near(s_m, spot_tol(carrier, 0.004))
	_on_pan = vial != null
	net_g = minf(vial.volume_l * 1000.0, range_g) if vial != null else 0.0


func tick(_dt: float) -> void:
	weight.value = net_g
	at_target.value = 1.0 if _on_pan and net_g >= target_g else 0.0
