class_name TwainStyle
extends RefCounted
## How the Mark Twain house is finished when BuildingBuilder builds it from
## its data: its colours (orange-red brick in black and vermilion bands,
## woodwork a chocolate red, slate in coloured courses) and its ground,
## which falls away to the north-west (TwainHouse.grade_at, read off the
## four elevations).


static func style() -> Dictionary:
	return {
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
