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
## Space jumps; in the air the player keeps the speed they left the
## ground with and can steer it a little.

const SPEED := 4.0
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8
const JUMP_SPEED := 3.43       # a 0.6 m rise: clears a knee-high pipe
const AIR_STEER := 4.0         # m/s² of steering while airborne
const JUMP_GRACE := 0.12       # s: a jump pressed just before landing, or
                               # just after walking off an edge, still counts

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
var port_ray: RayCast3D

var zoom_t: float = 0.0        # 0 = blade tip (first person), 1 = top of the curve
var _zoom_now: float = 0.0     # smoothed follower
var _fov_target: float = FOV_DEFAULT
var _shaft_dir: Vector3 = (ZOOM_TOP - ZOOM_KNEE).normalized()
var _shaft_speed: float = 2.0 * (ZOOM_TOP - ZOOM_KNEE).length()

var figure: PlayerFigure

var _step_streams: Array[AudioStream] = []
var _land_stream: AudioStream
var _steps: AudioStreamPlayer
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _off_floor: float = 0.0     # seconds since last on the floor
var _jump_wanted: float = 0.0   # seconds a jump press stays pending


func _ready() -> void:
	ray.add_exception(self)
	# The ground and structures (1) and the plant's equipment and lines.
	collision_mask = 1 | PlantSolids.SOLID_LAYER
	# World (1) + interact volumes (4) + routed runs (8); connect mode
	# adds port markers (2).
	ray.collision_mask = 1 | 4 | 8
	# A second ray that sees only port fittings. A fitting
	# lies inside its equipment's interaction volume, and a ray that
	# sees both stops at the volume; whenever the main ray admits
	# fittings, this one is asked first.
	port_ray = RayCast3D.new()
	port_ray.collision_mask = 2
	port_ray.target_position = ray.target_position
	port_ray.add_exception(self)
	camera.add_child(port_ray)
	MouseMode.capture()
	figure = PlayerFigure.new()
	add_child(figure)
	for i in range(1, 5):
		_step_streams.append(load("res://audio/step_%d.wav" % i))
	_land_stream = load("res://audio/land.wav")
	_steps = AudioStreamPlayer.new()
	_steps.bus = "Room"
	_steps.volume_db = -17.0
	add_child(_steps)


## Set while a full-screen panel owns the screen. The movement code
## polls Input directly rather than going through the event queue, so a
## panel cannot stop the player walking just by marking events handled.
var input_locked: bool = false


## Space is taken before the interface sees it, so a button left
## focused by a click is not pressed by a jump.
func _input(event: InputEvent) -> void:
	if input_locked or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("jump"):
		_jump_wanted = JUMP_GRACE
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
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
		MouseMode.capture()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("interact"):
		var view := look_view()
		if view != null and view.has_method("use"):
			view.call("use")


func _physics_process(delta: float) -> void:
	var grounded := is_on_floor()
	_off_floor = 0.0 if grounded else _off_floor + delta
	_jump_wanted = maxf(_jump_wanted - delta, 0.0)
	if not grounded:
		velocity.y -= GRAVITY * delta
		_fall_speed = -velocity.y
	var input := Vector2.ZERO if input_locked else Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var wanted := Vector2(direction.x, direction.z) * SPEED
	var ground := Vector2(velocity.x, velocity.z)
	if grounded:
		ground = wanted
	elif input != Vector2.ZERO:
		ground = ground.move_toward(wanted, AIR_STEER * delta)
	velocity.x = ground.x
	velocity.z = ground.y
	if _jump_wanted > 0.0 and _off_floor < JUMP_GRACE:
		velocity.y = JUMP_SPEED
		_jump_wanted = 0.0
		_off_floor = JUMP_GRACE
		_play(_step_streams[randi() % _step_streams.size()], randf_range(0.78, 0.86))
	move_and_slide()
	_update_landing()


## The camera follows every rendered frame, not every physics step:
## at a frame rate off the physics rate the step count per frame
## alternates, and a camera moved in steps looks jumpy.
func _process(delta: float) -> void:
	_update_camera(delta)
	figure.show_head(camera.position.distance_to(EYE) > 0.3)
	var moving := global_basis.inverse() * velocity
	if figure.pose(delta, moving, is_on_floor(), camera.rotation.x):
		_play(_step_streams[randi() % _step_streams.size()], randf_range(0.88, 1.12))


## Slide the camera along the zoom track, pulling it in when a wall,
## floor, or ceiling sits between the head and the desired spot.
func _update_camera(delta: float) -> void:
	_zoom_now = lerpf(_zoom_now, zoom_t, 1.0 - exp(-10.0 * delta))
	var head := to_global(EYE)
	var target := to_global(_zoom_point(_zoom_now))
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(head, target, 1 | PlantSolids.SOLID_LAYER)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		target = (hit["position"] as Vector3) + (head - target).normalized() * 0.18
	camera.position = to_local(target)
	camera.fov = lerpf(camera.fov, _fov_target, 1.0 - exp(-12.0 * delta))
	ray.target_position = Vector3(0, 0, -(BASE_REACH + zoom_offset()))
	port_ray.target_position = ray.target_position


## What the crosshair is on. A port fitting under the crosshair wins
## over the interaction volume it sits inside, in any mode (a click on
## a fitting starts a line, a right-hold moves
## a nozzle), unless the main ray stops well short of it — a fitting
## behind a wall is not under the crosshair. Otherwise the main ray.
func aimed_collider() -> Node:
	if _fitting_in_front():
		return port_ray.get_collider() as Node
	if ray.is_colliding():
		return ray.get_collider() as Node
	return null


## The ray that answered aimed_collider(), for its point and normal.
func aimed_ray() -> RayCast3D:
	if _fitting_in_front():
		return port_ray
	return ray


func _fitting_in_front() -> bool:
	if not port_ray.is_colliding():
		return false
	if not ray.is_colliding():
		return true
	var origin := camera.global_position
	return port_ray.get_collision_point().distance_to(origin) \
		<= ray.get_collision_point().distance_to(origin) + 0.5


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


## A landing from a fall or a jump: the thud, and the knees take it.
func _update_landing() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > 1.0:
		figure.land(_fall_speed)
		if _fall_speed > 2.5:
			_play(_land_stream, randf_range(0.92, 1.02))
		else:
			_play(_step_streams[randi() % _step_streams.size()], randf_range(0.88, 1.12))
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
