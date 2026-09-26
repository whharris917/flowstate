class_name NightSky
extends Node3D
## The night sky over a world: every star of the Yale Bright Star
## Catalogue in its place, and behind them the Milky Way and the faint
## glow of the upper air, turning with the clock (SkyClock).
##
## The stars are one mesh, a small square for each, which the shader
## (night_stars.gdshader) sets out in the sky and draws a few pixels
## across whatever the screen: a faint star is a soft point, a bright one
## a little wider, its colour from its temperature. The Milky Way is a
## picture in galactic coordinates (milky_way.png, from
## tools/build_sky.py) on a dome that follows the player
## (stars.gdshader). Both fade in as twilight goes, their faintest light
## last, and the world dims them further for cloud, moonlight and its
## own lamps (limit: the faintest magnitude the eye reaches here on a
## clear moonless night).

const DOME_R := 3800.0

var _stars_mat: ShaderMaterial
var _dome_mat: ShaderMaterial
var _stars: MeshInstance3D
var _dome: MeshInstance3D
var star_count := 0


func _init(limit: float = 6.3) -> void:
	name = "NightSky"
	_stars_mat = ShaderMaterial.new()
	_stars_mat.shader = load("res://world/night_stars.gdshader")
	_stars_mat.render_priority = -2
	_stars_mat.set_shader_parameter("limit", limit)
	_stars = MeshInstance3D.new()
	_stars.name = "Stars"
	_stars.mesh = _star_mesh()
	_stars.material_override = _stars_mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))
	add_child(_stars)
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = load("res://world/stars.gdshader")
	_dome_mat.render_priority = -3
	_dome_mat.set_shader_parameter("milky_way", load("res://world/milky_way.png"))
	var sphere := SphereMesh.new()
	sphere.radius = DOME_R
	sphere.height = DOME_R * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_dome = MeshInstance3D.new()
	_dome.name = "MilkyWay"
	_dome.mesh = sphere
	_dome.material_override = _dome_mat
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dome)


## The sky at a clock hour. visibility: 0 in daylight to 1 on a clear
## dark night (twilight and cloud folded in by the world); moon: how much
## the moon's light brightens the sky, 0 to 1.
func update(hours: float, visibility: float, moon: float) -> void:
	var to_world := SkyClock.to_world(hours)
	_stars_mat.set_shader_parameter("to_world", to_world)
	_stars_mat.set_shader_parameter("visibility", visibility)
	_stars_mat.set_shader_parameter("moon", moon)
	_dome_mat.set_shader_parameter("to_celestial", to_world.transposed())
	_dome_mat.set_shader_parameter("visibility", visibility)
	_dome_mat.set_shader_parameter("moon", moon)
	# By day the sky draws nothing and would still cost the fill.
	visible = visibility > 0.001


## The dome stays centred on the viewer.
func follow(at: Vector3) -> void:
	_dome.position = at


## A square per star: four corners at the star's celestial direction,
## the corner in UV, magnitude and a twinkle seed in UV2, the colour of
## its temperature in the vertex colour (linear).
func _star_mesh() -> ArrayMesh:
	var data := FileAccess.get_file_as_bytes("res://data/stars.bin")
	var n := data.size() / 16
	star_count = n
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	uvs.resize(n * 4)
	uv2s.resize(n * 4)
	cols.resize(n * 4)
	idx.resize(n * 6)
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947
	for i in n:
		var ra := data.decode_float(i * 16)
		var dec := data.decode_float(i * 16 + 4)
		var mag := data.decode_float(i * 16 + 8)
		var kelvin := data.decode_float(i * 16 + 12)
		var dir := SkyClock.celestial(ra, dec)
		var col := _temperature(kelvin)
		var seed := rng.randf()
		for k in 4:
			verts[i * 4 + k] = dir
			uvs[i * 4 + k] = corners[k]
			uv2s[i * 4 + k] = Vector2(mag, seed)
			cols[i * 4 + k] = col
		var b := i * 4
		for k in 6:
			idx[i * 6 + k] = b + order[k]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A star's colour from its temperature: a black body's hue as a
## display shows it, scaled so its brightest channel is one, in linear
## light.
static func _temperature(kelvin: float) -> Color:
	var t := clampf(kelvin, 1500.0, 40000.0) / 100.0
	var r: float
	var g: float
	var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	if t >= 66.0:
		b = 255.0
	elif t <= 19.0:
		b = 0.0
	else:
		b = 138.5177312231 * log(t - 10.0) - 305.0447927307
	var c := Color(clampf(r, 0.0, 255.0) / 255.0, clampf(g, 0.0, 255.0) / 255.0, clampf(b, 0.0, 255.0) / 255.0)
	c = c.srgb_to_linear()
	var top := maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / top, c.g / top, c.b / top, 1.0)
