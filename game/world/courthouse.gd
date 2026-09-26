extends "res://world/blank.gd"
class_name CourthouseMap
## Monroe, North Carolina: the old Union County courthouse on its square
## downtown, outside and in, with the streets and shopfronts round the
## square. The blank map's rules otherwise: everything unlocked, its own
## save. The courthouse's clocks keep the world's time and its lamps
## come on at dusk.

var courthouse: UnionCourthouse
var square: CourthouseSquare


func _init() -> void:
	super()
	plant_save_path = "user://save_courthouse.json"
	settings_prefix = "courthouse_"
	time_of_day = 15.5


func _build_ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)
	courthouse = UnionCourthouse.new()
	add_child(courthouse)
	courthouse.build()
	square = CourthouseSquare.new()
	add_child(square)
	square.build()


## The town's own trees stand on the square and the streets; past them
## a ring of woods closes the horizon.
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1886
	var far := Forest.new()
	far.plant_ring(Vector3.ZERO, 240.0, 380.0, 11.0, 16.0, rng)
	far.finish(false, true)
	add_child(far)


## No home pad: the square is the town's.
func _build_pad() -> void:
	pass


func _on_time_of_day(horizon: float, twilight: float) -> void:
	super(horizon, twilight)
	if courthouse != null:
		courthouse.set_clock(time_of_day)
		courthouse.set_darkness(1.0 - twilight)
	if square != null:
		square.set_darkness(1.0 - twilight)


func _after_plant() -> void:
	if not FileAccess.file_exists(plant_save_path):
		# On North Main Street's walk before the courthouse, looking east
		# up the brick path to the west porch.
		player.global_position = Vector3(-33.0, 0.3, 3.0)
		player.rotation.y = -PI / 2.0 + 0.1
	hud.toast("Monroe, North Carolina: the Union County courthouse (1886). The porches east and west open into the hall; the stairs at either end go up to the courtroom. O options · F5/F9 save/load")
	print("[flowstate] courthouse: %d triangles, %d solids, built in %d ms; square %d triangles, %d solids, %d ms"
		% [int(courthouse.stats["triangles"]), int(courthouse.stats["solids"]), int(courthouse.stats["ms"]),
		int(square.stats.get("triangles", 0)), int(square.stats.get("solids", 0)), int(square.stats.get("ms", 0))])
	if DisplayServer.get_name() == "headless":
		_report_in = 20
