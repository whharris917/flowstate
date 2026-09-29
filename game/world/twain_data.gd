extends TwainMap
## The Mark Twain house built from its data file (game/data/buildings/
## twain.json) by the general builder, beside the hand-built model, until
## it replaces it. Its own save.


func _init() -> void:
	super()
	from_data = true
	plant_save_path = "user://save_twain_data.json"
	settings_prefix = "twain_data_"
