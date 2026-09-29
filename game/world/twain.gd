extends "res://world/blank.gd"
class_name TwainMap
## Hartford, Connecticut, in the 1880s: the house Samuel Clemens built on
## Farmington Avenue, outside and in, on its lawn with the drive, the
## carriage house and the avenue. The blank map's rules otherwise:
## everything unlocked, its own save. The gas is lit as the day goes.

var house: TwainHouse
var built: BuildingMesh
## Generated from its data file and checked by tools/building/build.py
## (twain_data.tscn, or FLOWSTATE_TW_BUILDER=data) rather than built by
## hand.
var from_data := false
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
	# FLOWSTATE_TW_BUILDER=data: the house generated from its data file
	# (game/data/buildings/twain.json, written out as twain.bld) instead;
	# FLOWSTATE_BLD_FILE names another generated building to stand here.
	if from_data or OS.get_environment("FLOWSTATE_TW_BUILDER") == "data":
		house.name = "TwainHouseUnbuilt"
		house._materials()
		add_child(house)
		var bld := OS.get_environment("FLOWSTATE_BLD_FILE")
		built = BuildingMesh.open(bld if bld != "" else "res://data/buildings/twain.bld")
		add_child(built)
	else:
		add_child(house)
		house.build()
	grounds = TwainGrounds.new()
	add_child(grounds)
	grounds.build(house)


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
	if built != null:
		print("[flowstate] twain house from its data: %d faces, %d triangles, loaded in %d ms%s"
			% [int(built.stats.get("faces", 0)), int(built.stats.get("triangles", 0)), int(built.stats.get("ms", 0)),
			" (BROKEN: it fails its checks)" if built.broken else ""])
	else:
		print("[flowstate] twain house: %d triangles (%d inside), %d solids, built in %d ms; grounds %d triangles, %d ms"
			% [int(house.stats["triangles"]), int(house.stats["inside"]), int(house.stats["solids"]), int(house.stats["ms"]),
			int(grounds.stats.get("triangles", 0)), int(grounds.stats.get("ms", 0))])
	if DisplayServer.get_name() == "headless":
		_report_in = 20
