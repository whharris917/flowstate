class_name Player
extends CharacterBody3D
## First-person controller: WASD + mouse look, click to capture the
## mouse, Esc to release, E to use what you're looking at.

const SPEED := 4.0
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractRay


func _ready() -> void:
	ray.add_exception(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x - motion.relative.y * MOUSE_SENS,
			-PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
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
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	move_and_slide()


## The equipment view under the crosshair, or null.
func look_view() -> Node3D:
	if not ray.is_colliding():
		return null
	var collider := ray.get_collider()
	if collider is Node and (collider as Node).has_meta("view"):
		return (collider as Node).get_meta("view") as Node3D
	return null
