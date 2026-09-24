class_name VialPartView
extends Node3D
## What every part of the filling line shares: the height
## of the line (a conveyor stands its vials at bench height), the vial
## size the line runs (set by the plant from the magazine upstream,
## VialLine.sync), and a smoothed position per vial, since the kernel
## moves them twenty times a second and the eye sees the steps.

const DECK := 0.90        # top of the belt above the floor
const BELT := 0.006       # belt thickness: vials stand on DECK
const SMOOTH := 18.0      # how fast a drawn vial closes on its kernel position, 1/s

var record: SimComponent
var vial_ml: int = 10
var _shown: Dictionary = {}   # SimVial -> drawn position (float)


## Build (or rebuild) the view for its record.
func setup_record(record_: SimComponent) -> void:
	record = record_
	rebuild()


func rebuild() -> void:
	for child in get_children():
		# The port fittings are the plant's: they stay (it moves them if
		# the part's size moved them).
		if child.has_meta("port_name") or child.has_meta("merged_markers"):
			continue
		remove_child(child)
		child.free()
	_shown.clear()
	_build()


func _build() -> void:
	pass


## The line's vial size changed (the magazine upstream was resized):
## rails and pockets are sized to it.
func set_vial_ml(ml: int) -> void:
	if ml == vial_ml:
		return
	vial_ml = ml
	rebuild()
	MeshMerge.merge_view(self)


## The vial's size row: [diameter, height, brim mL, tare g].
func vial_row() -> Array:
	return SimVial.SIZES[SimVial.size_of(vial_ml)]


## A kernel position eased toward, per vial; forgets vials gone.
func smoothed(pairs: Array, delta: float) -> Array:
	var seen := {}
	var out: Array = []
	var k := clampf(delta * SMOOTH, 0.0, 1.0)
	for pair: Array in pairs:
		var vial: SimVial = pair[0]
		var target: float = pair[1]
		var shown: float = _shown.get(vial, target)
		# A jump (a load, a handoff back) is taken at once.
		shown = target if absf(target - shown) > 0.2 else lerpf(shown, target, k)
		_shown[vial] = shown
		seen[vial] = true
		out.append([vial, shown])
	for vial: SimVial in _shown.keys():
		if not seen.has(vial):
			_shown.erase(vial)
	return out


## Where vials hand off, in this view's space: {port: Vector3}. The
## plant links an outfeed to the infeed that stands where it ends.
func item_points() -> Dictionary:
	return {}
