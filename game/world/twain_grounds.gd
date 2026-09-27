class_name TwainGrounds
extends Node3D
## The Clemens house's grounds at Nook Farm, Hartford, in the 1880s: the
## lawn falling away west toward the Park River, Farmington Avenue along
## the north with its bluestone walk and gas lamps, the gravel drive in
## from the avenue under the porte-cochere and on to the carriage house
## (Potter, 1874: brick below, a gabled loft of painted boards above),
## elms and oaks over the lawn, a hedge along the street. A ring of woods
## closes the view.
##
## Frame: the house's (TwainHouse), +x east, -z north, metres. Art only.

const AVENUE_Z := -33.0         # Farmington Avenue's middle
const AVENUE_W := 12.0
const WALK_Z := -25.5           # the bluestone walk on the house's side
const DRIVE_X := 10.2           # the drive's line, under the porte-cochere

const GRAVEL := Color(0.58, 0.54, 0.46)
const BLUESTONE := Color(0.42, 0.45, 0.48)
const LAWN := Color(0.30, 0.40, 0.17)
const BRICK := Color(0.60, 0.26, 0.17)
const TRIM := Color(0.33, 0.14, 0.09)
const IRON := Color(0.05, 0.05, 0.055)

var k: CourthouseKit
var lamp_mat: StandardMaterial3D
var street_mat: ShaderMaterial
var lights: Array[Dictionary] = []
var stats: Dictionary = {}
var _trees: Forest
var _rng := RandomNumberGenerator.new()


func build(house: TwainHouse) -> void:
	name = "TwainGrounds"
	var t0 := Time.get_ticks_msec()
	_rng.seed = 1874
	var solids := Node3D.new()
	solids.name = "Solids"
	add_child(solids)
	k = CourthouseKit.new(solids)
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	street_mat = ShaderMaterial.new()
	street_mat.shader = load("res://world/street.gdshader")
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.95, 0.85)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.78, 0.50)
	var iron_mat := StandardMaterial3D.new()
	iron_mat.vertex_color_use_as_albedo = true
	iron_mat.vertex_color_is_srgb = true
	iron_mat.metallic = 0.4
	iron_mat.roughness = 0.5
	var glass_mat := house.glass_mat
	_trees = Forest.new()
	_trees.name = "GroundsTrees"
	_ground()
	_avenue()
	_drive()
	_carriage_house()
	_planting()
	k.m.commit(self, {"wall": wall_mat, "lamp": lamp_mat, "street": street_mat, "iron": iron_mat, "glass": glass_mat}, ["wall", "iron"])
	_trees.finish(true, false, true)
	add_child(_trees)
	stats = {"triangles": k.m.triangles, "solids": k.solid_count, "ms": Time.get_ticks_msec() - t0}


func set_darkness(dark: float) -> void:
	var on := smoothstep(0.35, 0.6, dark)
	lamp_mat.emission_energy_multiplier = 3.0 * on
	for l: Dictionary in lights:
		var light := l["light"] as OmniLight3D
		light.visible = on > 0.01
		light.light_energy = float(l["energy"]) * on


func c(col: Color, kind: int) -> Color:
	return CourthouseKit.kc(col, kind)


func _flat(key: String, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	k.m.quad(key, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, col,
		Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))


## A band of ground along a path of points (x, z), w wide, at y.
func _ribbon(key: String, pts: Array, wd: float, y: float, col: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i] as Vector2
		var b := pts[i + 1] as Vector2
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * wd / 2.0
		var ext := d * wd * 0.3
		var p := [a - n - ext, a + n - ext, b + n + ext, b - n + ext]
		k.m.quad(key, Vector3(p[0].x, y, p[0].y), Vector3(p[1].x, y, p[1].y), Vector3(p[2].x, y, p[2].y), Vector3(p[3].x, y, p[3].y),
			Vector3.UP, col)


func _ground() -> void:
	_flat("wall", -600, -600, 600, 600, 0.0, c(Color(0.34, 0.40, 0.21), CourthouseKit.K_LAWN))
	_flat("wall", -60, WALK_Z + 1.5, 70, 70, 0.004, c(LAWN, CourthouseKit.K_LAWN))


## Farmington Avenue: a macadam road with gravel shoulders, the bluestone
## walk on the house's side, gas lamps on iron posts along it.
func _avenue() -> void:
	_flat("street", -400, AVENUE_Z - AVENUE_W / 2.0, 400, AVENUE_Z + AVENUE_W / 2.0, 0.01, Color(0, 0, 0, 0.25))
	for s: float in [-1.0, 1.0]:
		var z := AVENUE_Z + s * (AVENUE_W / 2.0 + 0.6)
		_flat("wall", -400, z - 0.6, 400, z + 0.6, 0.008, c(GRAVEL, CourthouseKit.K_TAR))
	var slab := c(BLUESTONE, CourthouseKit.K_STONE)
	var x := -80.0
	while x < 90.0:
		k.box("wall", Transform3D(), Vector3(x + 0.6, 0.02, WALK_Z), Vector3(1.18, 0.04, 1.8), slab.lightened(_rng.randf_range(-0.04, 0.04)))
		x += 1.2
	var far_walk := AVENUE_Z - AVENUE_W / 2.0 - 2.4
	_flat("wall", -400, far_walk - 0.9, 400, far_walk + 0.9, 0.012, c(BLUESTONE, CourthouseKit.K_STONE))
	for lx: float in [-40.0, -8.0, 26.0, 58.0]:
		_lamp_post(Vector3(lx, 0.0, WALK_Z - 1.4))


## A gas street lamp on a fluted iron post: a lantern of four panes under
## a cap, its flame lit at dusk.
func _lamp_post(foot: Vector3) -> void:
	var iron := c(Color(0.10, 0.14, 0.10), CourthouseKit.K_PAINT)
	k.m.cylinder("iron", Transform3D(Basis(), foot + Vector3(0, 0.25, 0)), 0.14, 0.11, 0.5, 8, iron)
	k.m.cylinder("iron", Transform3D(Basis(), foot + Vector3(0, 1.8, 0)), 0.07, 0.05, 2.6, 8, iron)
	k.m.bar("iron", foot + Vector3(-0.3, 2.6, 0), foot + Vector3(0.3, 2.6, 0), 0.015, 4, iron)
	k.m.cylinder("lamp", Transform3D(Basis(), foot + Vector3(0, 3.35, 0)), 0.16, 0.22, 0.5, 4, Color(1, 1, 1))
	k.m.cylinder("iron", Transform3D(Basis(), foot + Vector3(0, 3.66, 0)), 0.28, 0.05, 0.14, 4, iron)
	k.solid(Transform3D(), foot + Vector3(0, 1.5, 0), Vector3(0.2, 3.0, 0.2))
	var light := OmniLight3D.new()
	light.position = foot + Vector3(0, 3.3, 0)
	light.omni_range = 10.0
	light.light_color = Color(1.0, 0.76, 0.46)
	light.light_energy = 1.2
	light.visible = false
	add_child(light)
	lights.append({"light": light, "energy": 1.2})


## The drive: in from the avenue, down the east side of the house under
## the porte-cochere, round to the carriage house to the south-east.
func _drive() -> void:
	var gravel := c(GRAVEL, CourthouseKit.K_TAR)
	_ribbon("wall", [Vector2(DRIVE_X + 6.0, AVENUE_Z + 6.0), Vector2(DRIVE_X + 3.0, -18.0), Vector2(DRIVE_X, -6.0), Vector2(DRIVE_X, 4.0),
		Vector2(DRIVE_X + 2.0, 13.0), Vector2(DRIVE_X + 8.0, 22.0), Vector2(DRIVE_X + 10.0, 30.0)], 4.2, 0.016, gravel)
	# A turning court before the carriage house.
	_flat("wall", DRIVE_X + 4.0, 26.0, DRIVE_X + 20.0, 38.0, 0.014, gravel)
	# The flagged walk from the avenue to the veranda's steps round the
	# north-east corner, bluestone.
	var slab := c(BLUESTONE, CourthouseKit.K_STONE)
	var path := [Vector2(2.0, WALK_Z + 1.0), Vector2(3.0, -16.0), Vector2(6.8, -9.0), Vector2(DRIVE_X - 2.0, -4.2)]
	for i in path.size() - 1:
		var a := path[i] as Vector2
		var b := path[i + 1] as Vector2
		var n := int(a.distance_to(b) / 0.9)
		for j in n:
			var p := a.lerp(b, (j + 0.5) / n)
			var d := (b - a).normalized()
			k.m.box("wall", Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, 0.02, p.y)), Vector3(1.5, 0.04, 0.84),
				slab.lightened(_rng.randf_range(-0.05, 0.05)))


## The carriage house: a long brick ground storey with its doors to the
## court, a loft of painted boards above under a steep slate roof, a
## gable over the doors with the hay door, stickwork, a cupola.
func _carriage_house() -> void:
	var o := Vector3(DRIVE_X + 12.0, 0.0, 44.0)
	var f := Transform3D(Basis(Vector3.UP, PI), o)
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var boards := c(Color(0.52, 0.34, 0.22), HarborTown.K_CLAP)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var slate := c(Color(0.34, 0.37, 0.43), CourthouseKit.K_SLATE)
	var wd := 14.0
	var dp := 8.0
	var opens: Array = [CourthouseKit.opening(-3.5, 2.8, 0.0, 3.0, "segment", 0.3), CourthouseKit.opening(0.5, 2.8, 0.0, 3.0, "segment", 0.3),
		CourthouseKit.opening(4.5, 1.1, 0.9, 2.4, "flat")]
	# The front, toward the court (north), and the other three walls.
	var fr := f * Transform3D(Basis(), Vector3(0, 0, dp / 2.0))
	k.wall("wall", fr, -wd / 2.0, wd / 2.0, 0.0, 3.6, 0.3, brick, opens, 100.0)
	k.wall("wall", fr, -wd / 2.0, wd / 2.0, 3.6, 6.2, 0.15, boards, [CourthouseKit.opening(-1.5, 1.2, 4.2, 5.6, "flat")], 100.0)
	for o2: Dictionary in opens:
		if float(o2["y0"]) < 0.1:
			for s: float in [-1.0, 1.0]:
				var leaf := fr * Transform3D(Basis(Vector3.UP, s * 0.35), Vector3(float(o2["u"]) + s * 1.4, 0, 0.05))
				k.door_leaf(leaf, Vector3(-s * 0.7, 0, 0), 1.36, 3.0, c(Color(0.28, 0.14, 0.08), CourthouseKit.K_WOOD))
		else:
			k.sash(fr, o2, -0.1, trim)
	var back := f * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -dp / 2.0))
	k.wall("wall", back, -wd / 2.0, wd / 2.0, 0.0, 3.6, 0.3, brick, [], 100.0)
	k.wall("wall", back, -wd / 2.0, wd / 2.0, 3.6, 6.2, 0.15, boards, [], 100.0)
	for s: float in [-1.0, 1.0]:
		var side := f * Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(s * wd / 2.0, 0, 0))
		k.wall("wall", side, -dp / 2.0, dp / 2.0, 0.0, 3.6, 0.3, brick, [CourthouseKit.opening(0.0, 1.0, 1.0, 2.5, "segment", 0.2)], 100.0)
		k.wall("wall", side, -dp / 2.0, dp / 2.0, 3.6, 6.2, 0.15, boards, [], 100.0)
		k.pediment(side, Vector3(0, 6.2, 0), dp, 4.6, 0.15, boards, trim, 0.4)
	# The stick-work: posts and braces over the boards.
	for i in 8:
		var u := -wd / 2.0 + (i + 0.5) * wd / 8.0
		k.box("wall", fr, Vector3(u, 4.9, 0.03), Vector3(0.12, 2.6, 0.06), trim)
	k.box("wall", fr, Vector3(0, 3.66, 0.06), Vector3(wd + 0.2, 0.14, 0.12), trim)
	k.box("wall", fr, Vector3(0, 6.2, 0.08), Vector3(wd + 0.4, 0.16, 0.16), trim)
	# The roof: steep, its ridge along the length, slate.
	var roof_f := f * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 6.2, 0))
	k.m.prism("wall", roof_f, dp + 1.2, 4.6, wd + 0.8, slate)
	# The front's gable over the doors.
	k.pediment(fr, Vector3(-1.5, 6.2, 0.02), 4.2, 3.2, 0.15, boards, trim, 0.4)
	# A cupola astride the ridge for the loft's air.
	var cup := f * Transform3D(Basis(), Vector3(0, 10.8, 0))
	k.box("wall", cup, Vector3(0, 0.5, 0), Vector3(1.3, 1.0, 1.3), trim)
	k.m.cylinder("wall", cup * Transform3D(Basis(), Vector3(0, 1.4, 0)), 1.0, 0.0, 0.9, 4, slate)
	k.m.bar("iron", (cup * Vector3(0, 1.8, 0)), (cup * Vector3(0, 2.6, 0)), 0.02, 4, IRON)
	# Its floor and the gravel before it.
	k.box("wall", f, Vector3(0, 0.02, 0), Vector3(wd - 0.4, 0.04, dp - 0.4), c(Color(0.40, 0.34, 0.26), HarborTown.K_PLANK))


func _planting() -> void:
	# Elms and oaks over the lawn and along the avenue.
	for t: Array in [[Vector3(-22.0, 0, -18.0), 22.0, "elm", Color(0.24, 0.34, 0.12)],
			[Vector3(-30.0, 0, 8.0), 20.0, "oak", Color(0.22, 0.32, 0.10)],
			[Vector3(-24.0, 0, 30.0), 18.0, "elm", Color(0.26, 0.36, 0.14)],
			[Vector3(28.0, 0, -14.0), 19.0, "maple", Color(0.30, 0.38, 0.12)],
			[Vector3(32.0, 0, 10.0), 21.0, "elm", Color(0.24, 0.34, 0.12)],
			[Vector3(-4.0, 0, 36.0), 17.0, "oak", Color(0.22, 0.32, 0.10)],
			[Vector3(-52.0, 0, -22.0), 20.0, "elm", Color(0.24, 0.33, 0.12)],
			[Vector3(52.0, 0, -22.0), 18.0, "maple", Color(0.28, 0.36, 0.12)],
			[Vector3(-12.0, 0, -28.0), 16.0, "elm", Color(0.26, 0.35, 0.13)],
			[Vector3(40.0, 0, 36.0), 17.0, "oak", Color(0.22, 0.30, 0.10)]]:
		_trees.plant_species(t[0], float(t[1]), str(t[2]), t[3], _rng)
	# The evergreens by the house, as in the old views.
	for p: Vector3 in [Vector3(-12.5, 0, -12.0), Vector3(16.5, 0, -12.0), Vector3(19.0, 0, 7.0), Vector3(-17.0, 0, 14.0)]:
		_trees.plant_conifer(p, _rng.randf_range(6.0, 9.0), _rng)
	# A clipped hedge along the avenue's walk, broken for the drive and the path.
	var box := Color(0.10, 0.20, 0.08)
	for seg: Vector2 in [Vector2(-80.0, 0.5), Vector2(4.5, DRIVE_X + 2.0), Vector2(DRIVE_X + 11.0, 90.0)]:
		var length := seg.y - seg.x
		if length > 1.0:
			_trees.plant_species(Vector3((seg.x + seg.y) / 2.0, 0, WALK_Z + 1.6), 1.1, "hedge", box, _rng, PI / 2.0, Vector3(1.0, 1.0, length))
	for p: Vector3 in [Vector3(-9.0, 0, -8.0), Vector3(-9.5, 0, 6.0), Vector3(12.8, 0, -8.0), Vector3(5.0, 0, 13.0), Vector3(-6.0, 0, 14.5)]:
		_trees.plant_species(p, 1.4, "shrub", Color(0.12, 0.24, 0.09), _rng)
