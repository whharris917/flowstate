class_name BenchView
extends Node3D
## What every piece of bench equipment shares: its record, and the
## heights things stand at on it. The origin is the base, on whatever
## surface it stands on (a bench top, the floor, a hotplate's plate).

const HOTPLATE_TOP := 0.11      # the plate's surface above the hotplate's base
const HOTPLATE_PLATE := 0.09    # half the plate's width: a vessel on it within this is seated
const BALANCE_TOP := 0.09       # the pan's surface above the balance's base
const BALANCE_PAN := 0.07       # the pan's radius
const METER_REACH := Vector3(0.20, 0.0, 0.0)   # the probe's point, from the meter's base
const METER_CATCH := 0.10       # a vessel this near the probe's point has the probe in it

var record: SimComponent


## Build (or rebuild) the view for its record.
func setup_record(record_: SimComponent) -> void:
	record = record_
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_build()


func _build() -> void:
	pass


## The footprint's radius in plan, for keeping bench things apart.
func radius() -> float:
	return 0.1
