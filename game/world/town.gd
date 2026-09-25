extends "res://world/maine.gd"
class_name TownMap
## The harbour town: the Maine coast with a 1940s town on its graded
## site, a waterfront at the head of the cove, boats in the harbour and
## a bell buoy off its mouth, under weather that runs from a fair day to
## a storm off the sea. The blank map's rules otherwise: everything
## unlocked, its own save. The clock and the weather are the town's
## own (the options panel sets both); it opens on an early evening
## storm.

var town: HarborTown
var harbor: Harbor
var weather: Weather


func _init() -> void:
	super()
	plant_save_path = "user://save_town.json"
	with_exercises = false
	settings_prefix = "town_"
	time_of_day = 18.1
	weather_level = 0.9


func _build_ground() -> void:
	var c := TownCoast.new()
	coast = c
	add_child(c)
	c.build()
	town = HarborTown.new()
	c.add_child(town)
	town.build(c)
	harbor = Harbor.new()
	c.add_child(harbor)
	harbor.build(c, town)
	weather = Weather.new()
	add_child(weather)
	weather.setup(self, c, town, harbor)
	weather.set_level(weather_level)


## No home pad: the town stands where it would be.
func _build_pad() -> void:
	pass


func set_weather(level: float) -> void:
	super(level)
	if weather != null:
		weather.set_level(weather_level)
		set_time_of_day(time_of_day)


func _on_time_of_day(horizon: float, twilight: float) -> void:
	super(horizon, twilight)
	if weather == null:
		return
	weather.apply_light(horizon, twilight)
	# Cloud hides the stars.
	if _stars_mat != null:
		var o := weather.overcast()
		_stars_mat.set_shader_parameter("visibility", pow(1.0 - twilight, 1.8) * pow(1.0 - o, 2.0))


func _after_plant() -> void:
	if not FileAccess.file_exists(plant_save_path):
		# On Main Street by the drug store, looking east up the street
		# to the church.
		player.global_position = Vector3(-6.0, 0.4, 17.5)
		player.rotation.y = -PI / 2.0
	hud.toast("The harbour town. Main Street runs east to the church; Harbor Street goes down to the wharf. O options: the time of day and the weather. B build · C connect · L library · F5/F9 save/load")
	var s := town.stats
	print("[flowstate] harbour town: %d houses, %d street trees, %d lamps, %d signs, %d triangles, %d solids, built in %d ms; %d trees in the woods"
		% [int(s["houses"]), int(s["trees"]), int(s["lamps"]), int(s["signs"]), int(s["triangles"]), int(s["solids"]), int(s["ms"]),
		int(coast.stats.get("trees", 0))])
	if DisplayServer.get_name() == "headless":
		_self_check()
		_town_check()
		_report_in = 20


## Headless: the town stands on dry ground, the wharf over high water,
## the boats and the buoy in water deep enough for them; the storm
## brings rain, cloud, dark and lit lamps, and a lightning stroke and
## its thunder; the buoy's bell rings in a sea and the harbour moves.
func _town_check() -> void:
	var problems: Array[String] = []
	var high := coast.sea_level + coast.tide_range
	for body in town.find_child("Solids", false, false).get_children():
		var p := (body as Node3D).global_position
		if p.y < -0.5:
			continue  # the waterfront stands in the water on purpose
		if coast.height_at(p.x, p.z) < high + 0.3:
			problems.append("a solid at (%.0f, %.0f) stands below high water" % [p.x, p.z])
			break
	if TownCoast.DECK_Y < high + 1.0:
		problems.append("wharf deck %.1f m over high water" % (TownCoast.DECK_Y - high))
	var low := coast.sea_level - coast.tide_range
	for spot: Vector2 in [Vector2(-6.0, 130.0), Vector2(-50.0, 134.0), Vector2(-26.0, 146.0), Vector2(-62.0, 118.0),
			Vector2(-30.0, TownCoast.HEAD_Z.y + 3.2), Vector2(-10.0, 116.0)]:
		if coast.height_at(spot.x, spot.y) > low - 1.8:
			problems.append("mooring at (%.0f, %.0f) dries at low water" % [spot.x, spot.y])
	var buoy := coast.height_at(TownCoast.BUOY.x, TownCoast.BUOY.y)
	if buoy > low - 6.0:
		problems.append("the buoy in %.1f m at low water" % (low - buoy))
	var ramp_top := coast.height_at(TownCoast.RAMP_TOP.x, TownCoast.RAMP_TOP.z)
	var ramp_foot := coast.height_at(TownCoast.RAMP_FOOT.x, TownCoast.RAMP_FOOT.z)
	if absf(ramp_top) > 0.1 or absf(ramp_foot - TownCoast.APRON_Y) > 0.15:
		problems.append("harbour road runs %.2f to %.2f m" % [ramp_top, ramp_foot])
	# The storm at dusk: rain, heavy cloud, dark enough for the lamps.
	set_weather(1.0)
	set_time_of_day(18.4)
	if weather.rain < 0.99 or weather.overcast() < 0.99:
		problems.append("a storm without rain or cloud")
	if not weather.lamps_on:
		problems.append("lamps off in a storm at dusk (darkness %.2f)" % weather.night)
	var lit := 0
	for lamp: Dictionary in town.lamps:
		if (lamp["light"] as Light3D).visible:
			lit += 1
	if lit < town.lamps.size() / 2:
		problems.append("only %d of %d lamps lit in the storm" % [lit, town.lamps.size()])
	# A stroke, and its thunder after the sound has come the distance.
	weather._strike(player.global_position)
	var queued := weather._thunder.size()
	var harbor_before := harbor.bell_strikes
	var boat: Node3D = harbor._boats[0]["node"]
	harbor.step(1.0 / 60.0)
	var y0 := boat.global_position.y
	var moved := 0.0
	for _i in 600:
		weather._process(1.0 / 60.0)
		harbor.step(1.0 / 60.0)
		moved = maxf(moved, absf(boat.global_position.y - y0))
	if queued != 1:
		problems.append("a stroke queued %d thunders" % queued)
	if harbor.bell_strikes == harbor_before:
		problems.append("the bell buoy never rang in ten seconds of a storm sea")
	if moved < 0.05:
		problems.append("the moored boat rode %.2f m in a storm" % moved)
	# A fair noon: no rain, the lamps off.
	set_weather(0.0)
	set_time_of_day(12.0)
	if weather.rain > 0.0 or weather.lamps_on:
		problems.append("rain or lamps on a fair noon")
	if problems.is_empty():
		print("[flowstate] town self-check OK — %d lamps lit in the storm, the moored boat rode %.2f m, the bell rang %d times in ten seconds, thunder queued"
			% [lit, moved, harbor.bell_strikes - harbor_before])
	else:
		print("[flowstate] town self-check FAILED: " + ", ".join(problems))
