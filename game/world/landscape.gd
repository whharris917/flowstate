class_name Landscape
extends Node3D
## A landscape under a site: a heightfield terrain built from a height
## function, a sea with a tide on the clock, boulders on the shore, a
## forest planted wherever the ground will take a tree, and the sounds
## of the place. Art and collision only — no records, nothing
## simulated — like the forest. A site subclass answers
## height_at() and coast_distance() and builds its landmarks in
## _build_landmarks().
##
## The terrain is one mesh on a grid whose spacing grows from CELL at
## the site to six times that at the edge, so it is fine underfoot
## and cheap on the horizon with no seams; its collision is the same
## triangles. The sea is a flat plane that follows the player; the
## waves are in its shader.

const CELL := 2.0              # grid spacing at the site
const GRID_N := 300            # cells per side
const REACH := 800.0           # metres from the centre to the mesh edge
const SEA_SIZE := 6000.0       # the water plane, following the player
const TIDE_PERIOD_H := 12.42   # a lunar semi-diurnal tide

var centre := Vector3(16.0, 0.0, 10.0)
var sea_level := -7.0          # mean sea level, world y
var tide_range := 1.5          # half the range: high water is sea_level + tide_range
var tide_y := -7.0
var seed := 20260913

var terrain_mat: ShaderMaterial
var rock_mat: ShaderMaterial
var sea_mat: ShaderMaterial
var river_mat: ShaderMaterial
var sea: MeshInstance3D
var stats: Dictionary = {}     # what build() made, for the smoke run's line
var _rng := RandomNumberGenerator.new()
var _rock_meshes: Array[ArrayMesh] = []
var _gull_next := 4.0


## ---- what a site answers -------------------------------------------------

## The ground height at (x, z).
func height_at(_x: float, _z: float) -> float:
	return 0.0


## Signed distance to the shore, positive on land. By default read off
## the height; a site with a designed coast answers exactly.
func coast_distance(x: float, z: float) -> float:
	return height_at(x, z) - sea_level


## Where a tree may stand: the ground height, or -INF for none. By
## default any ground clear of the tide.
func tree_ground(x: float, z: float) -> float:
	var h := height_at(x, z)
	return h if h > sea_level + 2.0 else -INF


## Graded ground (the site, a station) takes no rock and no trees.
func is_graded(_x: float, _z: float) -> bool:
	return false


## How graded the ground is at (x, z), 1 on a site and 0 in the wild;
## the terrain shader keeps rock and heath off it.
func graded_at(_x: float, _z: float) -> float:
	return 0.0


## 1 where bedrock breaks through the turf as a ledge outcrop.
func outcrop_at(_x: float, _z: float) -> float:
	return 0.0


## 1 where the low ground is a beach of cobble rather than ledge.
func beach_at(_x: float, _z: float) -> float:
	return 0.0


## 1 in a stream's channel above the sea, where boulders stand in the
## current.
func stream_at(_x: float, _z: float) -> float:
	return 0.0


## Where a boulder may not lie: a street, a wharf. By default nowhere.
func rock_blocked(_x: float, _z: float) -> bool:
	return false


## A site's own landmarks: a lighthouse, a wharf, a road.
func _build_landmarks() -> void:
	pass


## A site's own response to the clock. horizon and twilight are the
## world's: 1 by day, 0 by night.
func _on_time_of_day(_horizon: float, _twilight: float) -> void:
	pass


## ---- building ------------------------------------------------------------

func build() -> void:
	_rng.seed = seed
	var t0 := Time.get_ticks_msec()
	_build_terrain()
	var t1 := Time.get_ticks_msec()
	_build_sea()
	_build_rocks()
	var t2 := Time.get_ticks_msec()
	_build_forest()
	var t3 := Time.get_ticks_msec()
	_build_landmarks()
	_build_sound()
	stats["ms_terrain"] = t1 - t0
	stats["ms_rocks"] = t2 - t1
	stats["ms_forest"] = t3 - t2
	stats["ms_total"] = Time.get_ticks_msec() - t0
	set_tide(10.0)


## The world's clock: the tide follows it, then the site's own lights.
func set_time_of_day(hours: float, horizon: float, twilight: float) -> void:
	set_tide(hours)
	_on_time_of_day(horizon, twilight)


## High water about four in the morning and again twelve and a half
## hours on; the water plane and the wet band on the rock follow it.
func set_tide(hours: float) -> void:
	tide_y = sea_level + tide_range * cos(TAU * (hours - 4.2) / TIDE_PERIOD_H)
	if sea != null:
		sea.position.y = tide_y
	for mat: ShaderMaterial in [terrain_mat, rock_mat]:
		if mat != null:
			mat.set_shader_parameter("tide_y", tide_y)


## Grid index to metres from the centre: linear at the site, cubic
## toward the edge, so the spacing is CELL at the middle and about six
## times that at REACH.
func _axis(i: int) -> float:
	var t := float(i) / GRID_N * 2.0 - 1.0
	var a := absf(t)
	var lin := GRID_N * CELL / 2.0
	return signf(t) * (lin * a + (REACH - lin) * a * a * a)


func _build_terrain() -> void:
	var n := GRID_N
	var side := n + 1
	var coords := PackedFloat32Array()
	coords.resize(side)
	for i in side:
		coords[i] = _axis(i)
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	var verts := PackedVector3Array()
	verts.resize(side * side)
	var colors := PackedColorArray()
	colors.resize(side * side)
	var below := 0
	for j in side:
		var z := centre.z + coords[j]
		for i in side:
			var x := centre.x + coords[i]
			var y := height_at(x, z)
			var k := j * side + i
			heights[k] = y
			verts[k] = Vector3(x, y, z)
			colors[k] = Color(beach_at(x, z), graded_at(x, z), outcrop_at(x, z), 1.0)
			if y < sea_level:
				below += 1
	# Normals and tangents from the neighbouring heights, so the
	# lighting agrees with the triangles rather than with a finer
	# function the mesh cannot show.
	var norms := PackedVector3Array()
	norms.resize(side * side)
	var tangents := PackedFloat32Array()
	tangents.resize(side * side * 4)
	var uvs := PackedVector2Array()
	uvs.resize(side * side)
	for j in side:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, n)
		var dz := coords[j1] - coords[j0]
		for i in side:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n)
			var dx := coords[i1] - coords[i0]
			var k := j * side + i
			var dhx := heights[j * side + i1] - heights[j * side + i0]
			var dhz := heights[j1 * side + i] - heights[j0 * side + i]
			var nrm := Vector3(-dhx / dx, 1.0, -dhz / dz).normalized()
			norms[k] = nrm
			var tan := (Vector3(1, 0, 0) - nrm * nrm.x).normalized()
			tangents[k * 4] = tan.x
			tangents[k * 4 + 1] = tan.y
			tangents[k * 4 + 2] = tan.z
			tangents[k * 4 + 3] = 1.0
			uvs[k] = Vector2(verts[k].x, verts[k].z) * 0.1
	var indices := PackedInt32Array()
	indices.resize(n * n * 6)
	var q := 0
	for j in n:
		for i in n:
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			indices[q] = a
			indices[q + 1] = b
			indices[q + 2] = c
			indices[q + 3] = b
			indices[q + 4] = d
			indices[q + 5] = c
			q += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://world/terrain.gdshader")
	terrain_mat.set_shader_parameter("sea_y", sea_level)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = terrain_mat
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	body.add_child(inst)
	add_child(body)
	stats["vertices"] = side * side
	stats["sea_fraction"] = float(below) / float(side * side)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SEA_SIZE, SEA_SIZE)
	sea = MeshInstance3D.new()
	sea.mesh = plane
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = load("res://world/sea.gdshader")
	sea.material_override = sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Vector3(centre.x, sea_level, centre.z)
	add_child(sea)


## A water surface along a stream: one strip of quads through the
## samples, each {c: the centre at the water's height, n: the across
## direction, w: the half width, s: metres along}, UV in metres across
## and along so a shader can flow down it. Transparent, no shadow.
func _water_ribbon(samples: Array[Dictionary], mat: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for sample in samples:
		var c: Vector3 = sample["c"]
		var n: Vector2 = sample["n"]
		var w: float = sample["w"]
		var s: float = sample["s"]
		var side := Vector3(n.x, 0.0, n.y) * w
		verts.append(c - side)
		verts.append(c + side)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(-w, s))
		uvs.append(Vector2(w, s))
	var indices := PackedInt32Array()
	for i in samples.size() - 1:
		var a := i * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


## ---- rock ----------------------------------------------------------------

## A boulder: a sphere pushed about by noise and flat-shaded, with a
## flat underside to sit in the ground. Three variants share the
## scatter.
func _rock_mesh(variant_seed: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = variant_seed
	noise.frequency = 0.7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, idx.size(), 3):
		for j in 3:
			var v := verts[idx[k + j]]
			v *= 1.0 + 0.32 * noise.get_noise_3d(v.x * 2.0, v.y * 2.0, v.z * 2.0)
			v.y = maxf(v.y, -0.6)
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Boulders along the shore band, in and just out of the water, and
## the odd glacial erratic standing alone in the woods. The big ones
## are solid.
func _build_rocks() -> void:
	for v in 3:
		_rock_meshes.append(_rock_mesh(seed + v))
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = load("res://world/rock.gdshader")
	rock_mat.set_shader_parameter("sea_y", sea_level)
	var xforms: Array[Array] = [[], [], []]
	var colors: Array[Array] = [[], [], []]
	var placed := 0
	var reach := 480.0
	var count := int(PI * reach * reach / 81.0)
	for _i in count:
		var r := sqrt(_rng.randf_range(0.0, reach * reach))
		var a := _rng.randf_range(0.0, TAU)
		var x := centre.x + r * cos(a)
		var z := centre.z + r * sin(a)
		var d := coast_distance(x, z)
		var size := 0.0
		if d > -6.0 and d < 14.0:
			if _rng.randf() < 0.55:
				size = _rng.randf_range(0.5, 2.3)
		elif stream_at(x, z) > 0.0:
			# Boulders in a stream's bed, the big ones breaking the surface.
			if _rng.randf() < 0.30:
				size = _rng.randf_range(0.9, 2.6)
		elif d > 40.0 and _rng.randf() < 0.012:
			if height_at(x, z) > sea_level + 6.0 and not is_graded(x, z):
				size = _rng.randf_range(1.6, 3.4)
		if size <= 0.0 or rock_blocked(x, z):
			continue
		var y := height_at(x, z)
		var sy := size * _rng.randf_range(0.55, 0.85)
		var sz := size * _rng.randf_range(0.75, 1.25)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.25, 0.25),
			_rng.randf_range(0.0, TAU), _rng.randf_range(-0.25, 0.25))).scaled(Vector3(size, sy, sz))
		var at := Vector3(x, y + sy * 0.2, z)
		var variant := _rng.randi() % 3
		xforms[variant].append(Transform3D(basis, at))
		colors[variant].append(Color.WHITE.lightened(_rng.randf_range(-0.14, 0.06)))
		if size >= 1.0:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.position = at
			var shape := CollisionShape3D.new()
			var ball := SphereShape3D.new()
			ball.radius = minf(minf(size, sz), sy) * 0.85
			shape.shape = ball
			body.add_child(shape)
			add_child(body)
		placed += 1
	for v in 3:
		if xforms[v].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _rock_meshes[v]
		mm.instance_count = xforms[v].size()
		for i in xforms[v].size():
			mm.set_instance_transform(i, xforms[v][i])
			mm.set_instance_color(i, colors[v][i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = rock_mat
		add_child(inst)
	stats["rocks"] = placed


## ---- forest --------------------------------------------------------------

## A near wood, dense and shadowed, within 260 m of the site; a far
## wood beyond it to the mesh edge, sparser, taller, unshadowed and
## low-detail: silhouettes in the haze.
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 77
	var r_near := 260.0
	var r_far := 760.0
	var near_sampler := func(x: float, z: float) -> float:
		if Vector2(x - centre.x, z - centre.z).length() > r_near:
			return -INF
		return tree_ground(x, z)
	var far_sampler := func(x: float, z: float) -> float:
		if Vector2(x - centre.x, z - centre.z).length() <= r_near:
			return -INF
		return tree_ground(x, z)
	var near := Forest.new()
	var planted := near.plant_scatter(Vector2(centre.x - r_near, centre.z - r_near),
		Vector2(centre.x + r_near, centre.z + r_near), 5.2, 13.0, 0.85, rng, near_sampler)
	near.finish(true)
	add_child(near)
	var far := Forest.new()
	planted += far.plant_scatter(Vector2(centre.x - r_far, centre.z - r_far),
		Vector2(centre.x + r_far, centre.z + r_far), 12.0, 17.0, 0.9, rng, far_sampler)
	far.finish(false, true)
	add_child(far)
	stats["trees"] = planted


## ---- sound ---------------------------------------------------------------

## Surf: an emitter every forty metres along the shore nearest the
## site, each started at its own point in the loop so the whole coast
## does not breathe in unison; wind everywhere; gulls now and then
## over the water. Headless runs count the emitters and make none.
func _build_sound() -> void:
	var spots: Array[Vector3] = []
	var step := 6.0
	var reach := 240.0
	var gx := -reach
	while gx <= reach:
		var gz := -reach
		while gz <= reach:
			var x := centre.x + gx
			var z := centre.z + gz
			if absf(coast_distance(x, z)) < 3.0:
				var clear := true
				for s in spots:
					if Vector2(s.x - x, s.z - z).length() < 40.0:
						clear = false
						break
				if clear:
					spots.append(Vector3(x, height_at(x, z) + 1.0, z))
			gz += step
		gx += step
	stats["surf_emitters"] = spots.size()
	if DisplayServer.get_name() == "headless":
		return
	var surf := _loop_stream("res://audio/surf_loop.wav")
	for s in spots:
		var p := AudioStreamPlayer3D.new()
		p.stream = surf
		p.position = s
		p.volume_db = -6.0
		p.unit_size = 14.0
		p.max_distance = 170.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		p.play(_rng.randf() * surf.get_length())
	var wind := AudioStreamPlayer.new()
	wind.stream = _loop_stream("res://audio/wind_loop.wav")
	wind.volume_db = -22.0
	wind.bus = "Master"
	add_child(wind)
	wind.play()


func _loop_stream(path: String) -> AudioStreamWAV:
	var stream := load(path) as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


## A one-shot with the range a bird over the water needs.
func _one_shot(path: String, at: Vector3, volume_db: float, pitch: float) -> void:
	var node := AudioStreamPlayer3D.new()
	node.stream = load(path) as AudioStreamWAV
	node.position = at
	node.volume_db = volume_db
	node.pitch_scale = pitch
	node.bus = "Master"
	node.unit_size = 20.0
	node.max_distance = 220.0
	node.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	node.autoplay = true
	node.finished.connect(node.queue_free)
	add_child(node)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and sea != null:
		sea.position.x = snappedf(cam.global_position.x, 2.0)
		sea.position.z = snappedf(cam.global_position.z, 2.0)
	if DisplayServer.get_name() == "headless" or cam == null:
		return
	_gull_next -= delta
	if _gull_next <= 0.0:
		_gull_next = _rng.randf_range(7.0, 22.0)
		for _try in 6:
			var a := _rng.randf_range(0.0, TAU)
			var r := _rng.randf_range(30.0, 90.0)
			var at := cam.global_position + Vector3(cos(a) * r, _rng.randf_range(8.0, 25.0), sin(a) * r)
			if coast_distance(at.x, at.z) < 5.0:
				_one_shot("res://audio/gull_%d.wav" % (1 + _rng.randi() % 3), at, -4.0,
					_rng.randf_range(0.9, 1.15))
				break


## ---- solid art for landmarks ---------------------------------------------

func _solid_box(size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	inst.mesh = mesh
	inst.material_override = mat
	body.add_child(inst)
	add_child(body)
	return inst


func _solid_cylinder(r_bottom: float, r_top: float, height: float, pos: Vector3,
		mat: Material, sides: int = 24) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(r_bottom, r_top)
	cyl.height = height
	shape.shape = cyl
	body.add_child(shape)
	var inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r_bottom
	mesh.top_radius = r_top
	mesh.height = height
	mesh.radial_segments = sides
	inst.mesh = mesh
	inst.material_override = mat
	body.add_child(inst)
	add_child(body)
	return inst
