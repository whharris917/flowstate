extends "res://world/blank.gd"
class_name CampaignMap
## The campaign (director, 2026-09-11: the general gameplay of
## Satisfactory): the blank map with the milestone ladder switched on.
## The build menu starts with a tank, a header and a drain plus all the
## structure, and grows as the plant proves each milestone (J opens
## the journal). Its own save file. The blank map stays ungated for
## stress tests; the sandbox stays the showcase.


func _init() -> void:
	super()
	plant_save_path = "user://save_campaign.json"
	with_campaign = true


func _after_plant() -> void:
	# A game continues where it left off: the campaign loads its own
	# save on entry and writes it every two minutes and on quit.
	if FileAccess.file_exists(plant_save_path) and plant.load_game():
		hud.toast("Campaign continued from your last save. J journal · F5 save now")
	else:
		hud.toast("Campaign. J journal — the plant proves each milestone itself · B build · C connect · L library · O options")
	autosave_s = 120.0
	_autosave_left = autosave_s  # the first save waits its full interval
