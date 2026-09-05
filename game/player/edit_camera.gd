class_name EditCamera
extends Camera3D
## The edit-mode camera (director, 2026-09-05): untethered from the
## player, it orbits the equipment being modified the way a CAD
## viewport does, with Fusion 360's controls — middle-drag pans, shift
## + middle-drag orbits, the wheel zooms; right-drag orbits too, for a
## trackpad. It starts exactly where the player's camera was, so
## entering edit mode does not cut, and the player's camera takes over
## again on exit.

const MIN_DIST := 1.2
const MAX_DIST := 80.0
const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0016
const ZOOM_STEP := 0.85
const MIN_PITCH := -0.25
const MAX_PITCH := 1.50

var target := Vector3.ZERO
var distance := 6.0
var yaw := 0.0
var pitch := 0.4


## Take over from another camera, looking at target_ from where it stood.
func start_from(from: Camera3D, target_: Vector3) -> void:
	target = target_
	fov = from.fov
	var offset := from.global_position - target
	distance = clampf(offset.length(), MIN_DIST, MAX_DIST)
	yaw = atan2(offset.x, offset.z)
	pitch = clampf(asin(clampf(offset.y / maxf(offset.length(), 1e-6), -1.0, 1.0)),
		MIN_PITCH, MAX_PITCH)
	apply()


func orbit(delta: Vector2) -> void:
	yaw -= delta.x * ORBIT_SPEED
	pitch = clampf(pitch + delta.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
	apply()


func pan(delta: Vector2) -> void:
	var k := distance * PAN_SPEED
	target += -global_basis.x * delta.x * k + global_basis.y * delta.y * k
	apply()


func zoom(steps: float) -> void:
	distance = clampf(distance * pow(ZOOM_STEP, steps), MIN_DIST, MAX_DIST)
	apply()


func apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	global_position = target + offset
	look_at(target, Vector3.UP)
