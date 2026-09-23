class_name SimPhotoEye
extends SimVialMount
## A through-beam across the track: its contact makes while a vial
## breaks the beam. Mirrors sim/vials.py PhotoEye.

var seen: bool = false
var present: SimOutputPort


func _init(name_: String) -> void:
	super(name_)
	present = add_output("present", SimTypes.PortKind.SIGNAL_DISCRETE)


func sense(carrier: SimVialCarrier) -> void:
	seen = false
	if carrier is SimVialTrack:
		for pair: Array in carrier.vials():
			if absf(float(pair[1]) - s_m) < (pair[0] as SimVial).diameter_m / 2.0:
				seen = true
	else:
		seen = carrier.vial_near(s_m, 0.3) != null


func tick(_dt: float) -> void:
	present.value = 1.0 if seen else 0.0
