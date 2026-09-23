class_name SimVialMount
extends SimComponent
## Something that acts at one point along a vial carrier: a stop gate, a
## photo-eye, a load cell, a fill needle, a capper. s_m is that point,
## metres along a track or a station number on a star wheel; the plant
## derives it, and the host, from where the device stands. The carrier
## calls sense() after it has moved its vials each scan. Holds only the
## host's name: the carrier holds the device, never the other way round.
## Mirrors sim/vials.py _Mounted.

var s_m: float = 0.0
var host: String = ""


func sense(_carrier: SimVialCarrier) -> void:
	pass


## Tolerance for "the vial at my spot": a few millimetres along a track,
## a third of a station on a star wheel.
static func spot_tol(carrier: SimVialCarrier, on_track: float) -> float:
	return on_track if carrier is SimVialTrack else 0.3
