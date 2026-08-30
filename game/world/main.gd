extends Node3D
## Bootstraps the first playable: room, light, plant, HUD. Placeholder
## art throughout — flat boxes until systems are proven.

@onready var player: Player = $Player

var plant: Plant
var hud: Hud


func _ready() -> void:
	_build_environment()
	_build_room()
	plant = Plant.new()
	add_child(plant)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.toast("WASD move · mouse look · E use · F5 save · F9 load · Esc mouse")


func _process(_delta: float) -> void:
	var view := player.look_view()
	if view != null and view.has_method("describe"):
		hud.set_look_text(str(view.call("describe")))
	else:
		hud.set_look_text("")
	hud.set_readout_text("t %s   level %.1f L   relay %d cyc   pump %s" % [
		_fmt_time(plant.sim.time), plant.tank.level_l, plant.relay.cycles,
		"RUN" if plant.pump.running else "stop"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quicksave"):
		hud.toast("saved" if plant.save_game() else "save FAILED")
	elif event.is_action_pressed("quickload"):
		hud.toast("loaded" if plant.load_game() else "no save found")


func _fmt_time(seconds: float) -> String:
	var total := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)


func _build_room() -> void:
	_static_box(Vector3(14, 0.5, 10), Vector3(0, -0.25, 0), Color(0.28, 0.29, 0.31))  # floor
	_static_box(Vector3(14, 3, 0.3), Vector3(0, 1.5, -5), Color(0.36, 0.37, 0.40))   # back wall
	_static_box(Vector3(14, 3, 0.3), Vector3(0, 1.5, 5), Color(0.36, 0.37, 0.40))    # front wall
	_static_box(Vector3(0.3, 3, 10), Vector3(-7, 1.5, 0), Color(0.33, 0.34, 0.37))   # left wall
	_static_box(Vector3(0.3, 3, 10), Vector3(7, 1.5, 0), Color(0.33, 0.34, 0.37))    # right wall


func _static_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = ViewUtil.flat(color)
	body.add_child(mesh)
	add_child(body)
