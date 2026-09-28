extends "res://world/blank.gd"
class_name TwainMap
## Hartford, Connecticut, in the 1880s: the house Samuel Clemens built on
## Farmington Avenue, outside and in, on its lawn with the drive, the
## carriage house and the avenue. The blank map's rules otherwise:
## everything unlocked, its own save. The gas is lit as the day goes.

var house: TwainHouse
var grounds: TwainGrounds


func _init() -> void:
	super()
	plant_save_path = "user://save_twain.json"
	settings_prefix = "twain_"
	time_of_day = 10.0


func _build_ground() -> void:
	# The ground outside the lawn is level: four slabs round it (the lawn
	# brings its own collision).
	var body := StaticBody3D.new()
	for r: Rect2 in [Rect2(-600, -600, 1200, 600 + TwainGrounds.LAWN_LO.y), Rect2(-600, TwainGrounds.LAWN_HI.y, 1200, 600),
			Rect2(-600, TwainGrounds.LAWN_LO.y, 600 + TwainGrounds.LAWN_LO.x, TwainGrounds.LAWN_HI.y - TwainGrounds.LAWN_LO.y),
			Rect2(TwainGrounds.LAWN_HI.x, TwainGrounds.LAWN_LO.y, 600, TwainGrounds.LAWN_HI.y - TwainGrounds.LAWN_LO.y)]:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(r.size.x, 2.0, r.size.y)
		shape.shape = b
		shape.position = Vector3(r.get_center().x, -1.0, r.get_center().y)
		body.add_child(shape)
	add_child(body)
	house = TwainHouse.new()
	add_child(house)
	house.build()
	grounds = TwainGrounds.new()
	add_child(grounds)
	grounds.build(house)
	# The lawn falls steeply round the service wing: the trees' shadows on
	# it band without a wider bias.
	if sun != null:
		sun.shadow_normal_bias = 3.5


## Past the neighbours' lawns a ring of woods closes the view.
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1874
	var far := Forest.new()
	far.plant_ring(Vector3.ZERO, 150.0, 320.0, 10.0, 17.0, rng)
	far.finish(false, true)
	add_child(far)


## No home pad: the lawn is the family's.
func _build_pad() -> void:
	pass


func _on_time_of_day(horizon: float, twilight: float) -> void:
	super(horizon, twilight)
	if house != null:
		house.set_darkness(1.0 - twilight)
	if grounds != null:
		grounds.set_darkness(1.0 - twilight)


func _after_plant() -> void:
	if not FileAccess.file_exists(plant_save_path):
		# On the avenue's walk by the drive, looking south-west at the
		# house's north-east corner and the porte-cochere.
		player.global_position = Vector3(20.0, 0.3, -24.0)
		player.rotation.y = PI * 0.82
	hud.toast("Hartford, Connecticut: the Mark Twain house (1874) as the Clemenses knew it. The front door is under the porte-cochere; the stair in the hall climbs to the billiard room. O options · F5/F9 save/load")
	print("[flowstate] twain house: %d triangles (%d inside), %d solids, built in %d ms; grounds %d triangles, %d ms"
		% [int(house.stats["triangles"]), int(house.stats["inside"]), int(house.stats["solids"]), int(house.stats["ms"]),
		int(grounds.stats.get("triangles", 0)), int(grounds.stats.get("ms", 0))])
	if DisplayServer.get_name() == "headless":
		_report_in = 20
