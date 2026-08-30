class_name Player
extends CharacterBody3D
## First-person controller: WASD + mouse look, click to capture the
## mouse, Esc to release, E to use what you're looking at. The mouse
## wheel slides the camera along a hockey-stick track — blade tip at
## eye level in front of the face (zoomed in), knee at the eyes, and a
## handle rising up and slightly behind that extends indefinitely, so
## zooming out keeps climbing toward a bird's-eye view still centered
## on the player. Ctrl+wheel is optical zoom: it narrows the field of
## view from wherever the camera sits, with look sensitivity scaled to
## match. Yaw turns the body, pitch free-looks from the vantage point.

const SPEED := 4.0
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8
const STEP_DISTANCE := 1.85

const EYE := Vector3(0, 1.6, 0)
# The zoom track, eye-local: a quadratic through tip -> knee -> top,
# then an unbounded straight handle continuing past the top in the
# same direction, exponentially faster per notch (C1 at the joint).
const ZOOM_TIP := Vector3(0, 0, -0.55)
const ZOOM_KNEE := Vector3(0, 0.15, 0.25)
const ZOOM_TOP := Vector3(0, 5.4, 0.9)   # nearly overhead, just trailing the player
const ZOOM_STEP := 0.07
const ZOOM_T_MAX := 4.0        # ~870 m up the handle — effectively unbounded
const ZOOM_EXT_RATE := 1.6     # exponential growth rate past the top
const FOV_DEFAULT := 75.0
const BASE_REACH := 3.0

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractRay

var zoom_t: float = 0.0        # 0 = blade tip (first person), 1 = top of the curve
var _zoom_now: float = 0.0     # smoothed follower
var _fov_target: float = FOV_DEFAULT
var _shaft_dir: Vector3 = (ZOOM_TOP - ZOOM_KNEE).normalized()
var _shaft_speed: float = 2.0 * (ZOOM_TOP - ZOOM_KNEE).length()

var _step_streams: Array[AudioStream] = []
var _land_stream: AudioStream
var _steps: AudioStreamPlayer
var _step_accum: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0


func _ready() -> void:
	ray.add_exception(self)
	# World (1) + interact volumes (4); connect mode adds port markers (2).
	ray.collision_mask = 1 | 4
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_body()
	for i in range(1, 5):
		_step_streams.append(load("res://audio/step_%d.wav" % i))
	_land_stream = load("res://audio/land.wav")
	_steps = AudioStreamPlayer.new()
	_steps.bus = "Room"
	_steps.volume_db = -17.0
	add_child(_steps)


## A simple suit-dark torso so looking down (or at your shadow) shows a
## person, not a floating camera.
func _build_body() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.30
	mesh.height = 1.25
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.position = Vector3(0, 0.72, 0)
	body.material_override = ViewUtil.flat(Color(0.16, 0.18, 0.22))
	add_child(body)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := MOUSE_SENS * camera.fov / FOV_DEFAULT
		rotate_y(-motion.relative.x * sens)
		camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * sens,
			-PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	elif event.is_action_pressed("zoom_in"):
		if Input.is_key_pressed(KEY_CTRL):
			_fov_target = clampf(_fov_target * 0.90, 8.0, 85.0)
		else:
			zoom_t = clampf(zoom_t - ZOOM_STEP, 0.0, ZOOM_T_MAX)
	elif event.is_action_pressed("zoom_out"):
		if Input.is_key_pressed(KEY_CTRL):
			_fov_target = clampf(_fov_target / 0.90, 8.0, 85.0)
		else:
			zoom_t = clampf(zoom_t + ZOOM_STEP, 0.0, ZOOM_T_MAX)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("interact"):
		var view := look_view()
		if view != null and view.has_method("use"):
			view.call("use")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_fall_speed = -velocity.y
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	move_and_slide()
	_update_camera(delta)
	_update_footsteps(delta)


## Slide the camera along the zoom track, pulling it in when a wall,
## floor, or ceiling sits between the head and the desired spot.
func _update_camera(delta: float) -> void:
	_zoom_now = lerpf(_zoom_now, zoom_t, 1.0 - exp(-10.0 * delta))
	var head := to_global(EYE)
	var target := to_global(_zoom_point(_zoom_now))
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(head, target, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		target = (hit["position"] as Vector3) + (head - target).normalized() * 0.18
	camera.position = to_local(target)
	camera.fov = lerpf(camera.fov, _fov_target, 1.0 - exp(-12.0 * delta))
	ray.target_position = Vector3(0, 0, -(BASE_REACH + zoom_offset()))


func _zoom_point(t: float) -> Vector3:
	if t <= 1.0:
		var a := ZOOM_TIP.lerp(ZOOM_KNEE, t)
		var b := ZOOM_KNEE.lerp(ZOOM_TOP, t)
		return EYE + a.lerp(b, t)
	# The handle: straight on in the shaft direction, exponentially
	# faster per notch so the sky is a few clicks away, not a hundred.
	var dist := (exp(ZOOM_EXT_RATE * (t - 1.0)) - 1.0) * _shaft_speed / ZOOM_EXT_RATE
	return EYE + ZOOM_TOP + _shaft_dir * dist


## How far the camera currently sits from the head. Reach-based systems
## (interact ray, build ghost) add this so the crosshair keeps working
## from a zoomed-out vantage.
func zoom_offset() -> float:
	return camera.position.distance_to(EYE)


func _update_footsteps(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > 2.5:
		_play(_land_stream, randf_range(0.92, 1.02))
	elif on_floor:
		var ground_speed := Vector2(velocity.x, velocity.z).length()
		if ground_speed > 0.5:
			_step_accum += ground_speed * delta
			if _step_accum >= STEP_DISTANCE:
				_step_accum = 0.0
				_play(_step_streams[randi() % _step_streams.size()],
					randf_range(0.88, 1.12))
		else:
			_step_accum = STEP_DISTANCE * 0.6  # next step comes quickly
	_was_on_floor = on_floor


func _play(stream: AudioStream, pitch: float) -> void:
	_steps.stream = stream
	_steps.pitch_scale = pitch
	_steps.volume_db = -17.0 + randf_range(-2.0, 0.0)
	_steps.play()


## The equipment view under the crosshair, or null.
func look_view() -> Node3D:
	if not ray.is_colliding():
		return null
	var collider := ray.get_collider()
	if collider is Node and (collider as Node).has_meta("view"):
		return (collider as Node).get_meta("view") as Node3D
	return null
