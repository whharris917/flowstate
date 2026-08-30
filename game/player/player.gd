class_name Player
extends CharacterBody3D
## First-person controller: WASD + mouse look, click to capture the
## mouse, Esc to release, E to use what you're looking at. The player
## has a visible body and footsteps that feed the Room reverb bus.

const SPEED := 4.0
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8
const STEP_DISTANCE := 1.85

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractRay

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
	_steps.volume_db = -15.0
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
		rotate_y(-motion.relative.x * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * MOUSE_SENS,
			-PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
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
	_update_footsteps(delta)


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
	_steps.play()


## The equipment view under the crosshair, or null.
func look_view() -> Node3D:
	if not ray.is_colliding():
		return null
	var collider := ray.get_collider()
	if collider is Node and (collider as Node).has_meta("view"):
		return (collider as Node).get_meta("view") as Node3D
	return null
