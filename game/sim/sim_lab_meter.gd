class_name SimLabMeter
extends SimComponent
## A bench meter with a combined pH and temperature probe, dipped in the
## vessel beside it (the plant sets which from where things stand).
## Reads nothing with no vessel, and no pH in a liquid without water.
## Mirrors sim/bench.py LabMeter.

var target: SimLabVessel = null
var ph := NAN
var temp_c := NAN


func _init(name_: String) -> void:
	super(name_)
	add_observable("ph", &"ph")
	add_observable("temp_c", &"temp_c")


func tick(_dt: float) -> void:
	if target == null or target.contents.liquid_ml() < 1.0:
		ph = NAN
		temp_c = NAN
		return
	ph = target.contents.ph()
	temp_c = target.temp_c
