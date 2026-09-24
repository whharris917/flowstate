extends "res://world/sandbox.gd"
class_name BlankMap
## The blank map: the sandbox's infinite plane, sky and home pad with
## nothing on it, for building by hand. No starting loop, no showcase,
## no gallery; the material balance screen stands on the pad because it
## is right with nothing placed. Saves to its own file. The showcase is
## world/sandbox.tscn.


func _init() -> void:
	super()
	plant_save_path = "user://save_blank.json"
	with_home = false


## Nothing pre-built: the stress test starts from bare ground.
func _after_plant() -> void:
	hud.toast("Blank map. B build · C connect · L library · O options · F5/F9 save/load. Place a mains feeder first: nothing runs without power.")
