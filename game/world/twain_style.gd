class_name TwainStyle
extends RefCounted
## How the Mark Twain house is finished when BuildingBuilder builds it from
## its data: its colours (orange-red brick in black and vermilion bands,
## woodwork a chocolate red, slate in coloured courses) and its ground,
## which falls away to the north-west (TwainHouse.grade_at, read off the
## four elevations).


## With `house` (a TwainHouse left unbuilt), its joinery and bands dress
## the openings and the brick: the stepped sunburst hoods, sashes, casings,
## doors standing open, the painted black and vermilion bands.
static func style(house: TwainHouse = null) -> Dictionary:
	var st := {
		"brick": TwainHouse.BRICK,
		"brick_dark": TwainHouse.BLACK,
		"nogging": TwainHouse.NOGGING,
		"trim": TwainHouse.TRIM,
		"sash": TwainHouse.SASH,
		"door": Color(0.30, 0.17, 0.09),
		"plaster": Color(0.84, 0.79, 0.68),
		"ceiling": TwainHouse.CEIL,
		"floor": Color(0.52, 0.34, 0.18),
		"deck": TwainHouse.PORCH,
		"slate_courses": [TwainHouse.SLATE, TwainHouse.SLATE, TwainHouse.SLATE, TwainHouse.SLATE_DARK, TwainHouse.SLATE,
			TwainHouse.SLATE, TwainHouse.SLATE_RED, TwainHouse.SLATE, TwainHouse.SLATE, TwainHouse.SLATE_DARK, TwainHouse.SLATE,
			TwainHouse.SLATE_RED],
		"ground_at": func(p: Vector2) -> float: return TwainHouse.grade_at(p),
	}
	if house != null:
		st["on_kit"] = func(kit: CourthouseKit) -> void: house.k = kit
		st["dress"] = func(f: Transform3D, o: Dictionary, _wl: Dictionary) -> void:
			if str(o["kind"]) == "idoor" or str(o["kind"]) == "ishut":
				return
			house._dress(f, o)
		st["bands"] = func(f: Transform3D, length: float, y0: float, y1: float, mine: Array) -> void:
			house._bands(f, length, y0, y1, mine)
		st["extra_meshes"] = [house.dress_m]
		st["chimney"] = func(ch: Dictionary, at: Vector2, size: Vector2, y0: float, y1: float) -> void:
			if str(ch["id"]) == "great_north":
				house.great_north()
			else:
				house._chimney(at, size, y0, y1)
	return st
