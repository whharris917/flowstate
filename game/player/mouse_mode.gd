class_name MouseMode
## The one place the mouse is captured. Play captures it for the
## first-person look and releases it for panels; a probe never
## captures it at all (director, 2026-09-12: a test window that grabs
## the cursor while someone is working is a nuisance), so every probe
## sets `probe = true` before it instantiates a world.

static var probe := false


static func capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if probe else Input.MOUSE_MODE_CAPTURED


static func release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func set_captured(on: bool) -> void:
	if on:
		capture()
	else:
		release()
