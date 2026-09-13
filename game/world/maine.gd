extends "res://world/blank.gd"
class_name MaineMap
## The Maine coast (director, 2026-09-12: "let's start by building a
## site at a scenic spot in coastal Maine"): the blank map's rules —
## bare ground, everything unlocked, its own save — on a graded site
## over the Gulf of Maine. MaineCoast builds the landscape; this world
## owns the sky, the fog that lies on the water at dawn, the tide's
## clock, and what the camera sees under water.

var coast: MaineCoast
var _fog_density := 0.0
var _underwater := false


func _init() -> void:
	super()
	plant_save_path = "user://save_maine.json"


func _build_environment() -> void:
	super()
	# Coastal air: more water in it than the sandbox's crisp autumn
	# day, and a dark sea under the horizon in the reflections.
	var physical := sky_mat as PhysicalSkyMaterial
	physical.turbidity = 4.0
	physical.mie_coefficient = 0.0035
	physical.ground_color = Color(0.12, 0.16, 0.18)
	sky_env.fog_density = 0.0009
	sky_env.fog_aerial_perspective = 0.45
	sky_env.fog_height = MaineCoast.SEA + 4.0
	sky_env.fog_height_density = 0.0
	_fog_density = sky_env.fog_density


func _build_ground() -> void:
	coast = MaineCoast.new()
	add_child(coast)
	coast.build()


## The landscape plants its own wood, by the ground.
func _build_forest() -> void:
	pass


func _on_time_of_day(horizon: float, twilight: float) -> void:
	super(horizon, twilight)
	if coast != null:
		coast.set_time_of_day(time_of_day, horizon, twilight)
	# Sea fog: a veil on the water at dawn that burns off by mid-morning.
	if sky_env != null:
		var morning := clampf(1.0 - absf(time_of_day - 6.5) / 3.0, 0.0, 1.0)
		sky_env.fog_height_density = 0.02 * morning
		sky_env.fog_height = MaineCoast.SEA + 2.0 + 2.0 * morning


func _process(delta: float) -> void:
	super._process(delta)
	if coast == null or sky_env == null:
		return
	# Under the surface the world goes green and short.
	var under := player.camera.global_position.y < coast.tide_y
	if under != _underwater:
		_underwater = under
		if under:
			sky_env.fog_density = 0.09
			sky_env.fog_light_color = Color(0.04, 0.12, 0.13)
			sky_env.fog_sky_affect = 1.0
		else:
			sky_env.fog_density = _fog_density
			sky_env.fog_sky_affect = 0.0
			set_time_of_day(time_of_day)


func _after_plant() -> void:
	hud.toast("The Maine coast. The site is graded; the shore is a walk east or south, the lighthouse is across the cove. B build · C connect · L library · O options · F5/F9 save/load")
	var s := coast.stats
	print("[flowstate] landscape: %d vertices, %.0f%% sea, %d trees, %d rocks, %d surf emitters — terrain %d ms, rocks %d ms, forest %d ms, %d ms in all"
		% [int(s.get("vertices", 0)), 100.0 * float(s.get("sea_fraction", 0.0)), int(s.get("trees", 0)),
		int(s.get("rocks", 0)), int(s.get("surf_emitters", 0)), int(s.get("ms_terrain", 0)),
		int(s.get("ms_rocks", 0)), int(s.get("ms_forest", 0)), int(s.get("ms_total", 0))])
	if DisplayServer.get_name() == "headless":
		_self_check()


## Headless: the site is flat at grade, the spawn stands on dry land,
## the sea is there and the shore is a walk, the light stands above
## high water, and the tide moves with the clock.
func _self_check() -> void:
	var problems: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var worst := 0.0
	for _i in 80:
		var x := MaineCoast.SITE.x + rng.randf_range(-MaineCoast.SITE_HALF.x, MaineCoast.SITE_HALF.x)
		var z := MaineCoast.SITE.y + rng.randf_range(-MaineCoast.SITE_HALF.y, MaineCoast.SITE_HALF.y)
		worst = maxf(worst, absf(coast.height_at(x, z)))
	if worst > 0.01:
		problems.append("site not flat (%.2f m off grade)" % worst)
	if coast.height_at(0.0, 3.0) < coast.sea_level + coast.tide_range + 1.0:
		problems.append("spawn under high water")
	var frac := float(coast.stats.get("sea_fraction", 0.0))
	if frac < 0.25 or frac > 0.75:
		problems.append("sea covers %.0f%% of the map" % (100.0 * frac))
	var walk := INF
	var x := MaineCoast.SITE.x + MaineCoast.SITE_HALF.x
	while x < 400.0:
		if coast.coast_distance(x, MaineCoast.SITE.y) < 0.0:
			walk = x - (MaineCoast.SITE.x + MaineCoast.SITE_HALF.x)
			break
		x += 2.0
	if walk > 120.0:
		problems.append("shore is %.0f m east of the site" % walk)
	if MaineCoast.LIGHT_Y < coast.sea_level + coast.tide_range + 1.0:
		problems.append("light station under high water")
	coast.set_tide(4.2)
	var high := coast.tide_y
	coast.set_tide(4.2 + Landscape.TIDE_PERIOD_H / 2.0)
	var low := coast.tide_y
	if absf((high - low) - 2.0 * coast.tide_range) > 0.01:
		problems.append("tide range %.2f m" % (high - low))
	coast.set_tide(time_of_day)
	if problems.is_empty():
		print("[flowstate] maine self-check OK — site flat to %.3f m, shore %.0f m east of the site, tide %.1f m, spawn %.1f m over high water"
			% [worst, walk, high - low, coast.height_at(0.0, 3.0) - high])
	else:
		print("[flowstate] maine self-check FAILED: " + ", ".join(problems))
