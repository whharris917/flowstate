extends Node
## Renders a take to film. Run it windowed with Godot's movie maker:
##   godot --path game --write-movie <out.avi> --fixed-fps 30 res://world/take_render.tscn
## with FLOWSTATE_TAKE set to the take's title (under user://takes) or
## its path. The world loads, the take plays on the High preset at 1920
## by 1080, and the program quits a moment after the take's end. The
## first seconds (the world loading) are trimmed from the film after.

const LEAD := 4.0

var _world: CourthouseMap


func _ready() -> void:
	MouseMode.probe = true
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_viewport().size = Vector2i(1920, 1080)
	_world = (load("res://world/courthouse.tscn") as PackedScene).instantiate()
	add_child(_world)
	_run()


func _run() -> void:
	await get_tree().create_timer(LEAD).timeout
	_world.graphics.set_preset("High")
	_world.graphics.apply(_world)
	# The player steps off the set.
	_world.player.global_position = Vector3(400, 0.5, 400)
	_world.player.set_physics_process(false)
	var take := StageTakes.load_take(OS.get_environment("FLOWSTATE_TAKE"))
	if take.is_empty():
		push_error("take_render: no take '%s'" % OS.get_environment("FLOWSTATE_TAKE"))
		get_tree().quit(1)
		return
	_world.stage_takes.on_end = func() -> void:
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
	print("[take] %s" % JSON.stringify(_world.stage_takes.play(take)))
