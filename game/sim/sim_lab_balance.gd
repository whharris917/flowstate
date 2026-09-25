class_name SimLabBalance
extends SimComponent
## A bench balance: what stands on it, less the tare. Mirrors
## sim/bench.py LabBalance.

var load: SimLabVessel = null
var tare_g := 0.0


func _init(name_: String) -> void:
	super(name_)
	add_observable("reading_g", &"reading_g")


var gross_g: float:
	get:
		return load.tare_g + load.mass_g if load != null else 0.0

var reading_g: float:
	get:
		return gross_g - tare_g


func tare() -> void:
	tare_g = gross_g


func tick(_dt: float) -> void:
	pass


func state_dict() -> Dictionary:
	return {"tare_g": tare_g}


func apply_state(state: Dictionary) -> void:
	tare_g = float(state.get("tare_g", tare_g))
