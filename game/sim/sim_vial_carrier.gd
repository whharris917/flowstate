class_name SimVialCarrier
extends SimComponent
## Holds vials at positions and hands them on: a track or a star wheel.
## Mirrors sim/vials.py _Carrier.

var mounts: Array[SimVialMount] = []


func _init(name_: String) -> void:
	super(name_)
	add_observable("held_l", &"held_l")
	add_observable("vials_on", &"vials_on")


func mount(device: SimVialMount, s: float) -> void:
	if not mounts.has(device):
		mounts.append(device)
	device.s_m = s
	device.host = comp_name


func unmount(device: SimVialMount) -> void:
	mounts.erase(device)
	device.host = ""


func clear_mounts() -> void:
	for device in mounts:
		device.host = ""
	mounts.clear()


## Every vial it holds, as [vial, position] pairs.
func vials() -> Array:
	return []


func vial_near(_s: float, _tol: float) -> SimVial:
	return null


var held_l: float:
	get:
		var total := 0.0
		for pair: Array in vials():
			total += (pair[0] as SimVial).volume_l
		return total


var vials_on: int:
	get:
		return vials().size()


func _sense_mounts() -> void:
	for device in mounts:
		device.sense(self)
