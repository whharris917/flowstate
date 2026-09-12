extends WorldBase
## The manufacturing hall — 44 x 26 m, 12 m to the roof, skylight
## bands, clerestory glazing, mezzanines on two levels with stairs and
## railings, color-coded pipe runs, and the aseptic annex off the west
## wall. Parked while the sandbox is the daily driver; open this scene
## and Play Current Scene to walk it.

const ROOM_W := 44.0   # x
const ROOM_D := 26.0   # z
const ROOM_H := 12.0
const WALL_T := 0.3
const MEZZ1_Y := 4.0
const MEZZ2_Y := 8.0

const COL_FLOOR := Color(0.62, 0.62, 0.60)
const COL_WALL := Color(0.85, 0.85, 0.82)
const COL_STEEL := Color(0.16, 0.17, 0.19)
const COL_DECK := Color(0.34, 0.35, 0.37)
const COL_PLINTH := Color(0.50, 0.50, 0.49)
const COL_SAFETY := Color(0.95, 0.78, 0.05)
const COL_GLASS := Color(0.75, 0.85, 0.95, 0.16)
const COL_PIPE_BLUE := Color(0.20, 0.42, 0.65)
const COL_PIPE_GRAY := Color(0.55, 0.56, 0.58)
const COL_PIPE_STEEL := Color(0.70, 0.72, 0.74)
const COL_PIPE_YELLOW := Color(0.85, 0.70, 0.10)


func _init() -> void:
	plant_height = 0.08
	plant_save_path = "user://save_hall.json"
	with_suite = true
	with_hum = true
	reverb_room_size = 0.85
	reverb_wet = 0.25


func _build_world() -> void:
	_build_environment()
	_build_shell()
	_build_mezzanines()
	_build_pipes()
	_build_fixtures()
	_build_markings()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.70, 0.78, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.60)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_power = 1.8
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_energy = 1.6
	sun.light_angular_distance = 0.5
	sun.light_color = Color(1.0, 0.97, 0.92)
	_sun_base_energy = sun.light_energy
	_sun_base_color = sun.light_color
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_shell() -> void:
	var half_w := ROOM_W / 2.0
	var half_d := ROOM_D / 2.0

	_static_box(Vector3(ROOM_W, 0.5, ROOM_D), Vector3(0, -0.25, 0), COL_FLOOR)
	_static_box(Vector3(9.2, 0.08, 3.4), Vector3(-1.0, 0.04, -3.2), COL_PLINTH)

	# End walls (x = +-22): solid below, one glazed band up high. The
	# west wall carries the doorway into the aseptic annex.
	for side: float in [-1.0, 1.0]:
		var wall_x := side * half_w
		if side < 0.0:
			var z0 := AsepticSuite.HALL_DOOR_Z0
			var z1 := AsepticSuite.HALL_DOOR_Z1
			var door_h := AsepticSuite.HALL_DOOR_H
			_static_box(Vector3(WALL_T, 7.6, z0 + half_d), Vector3(wall_x, 3.8, (-half_d + z0) / 2.0), COL_WALL)
			_static_box(Vector3(WALL_T, 7.6, half_d - z1), Vector3(wall_x, 3.8, (z1 + half_d) / 2.0), COL_WALL)
			_static_box(Vector3(WALL_T, 7.6 - door_h, z1 - z0), Vector3(wall_x, (door_h + 7.6) / 2.0, (z0 + z1) / 2.0), COL_WALL)
		else:
			_static_box(Vector3(WALL_T, 7.6, ROOM_D), Vector3(wall_x, 3.8, 0), COL_WALL)
		_static_box(Vector3(WALL_T, ROOM_H - 9.2, ROOM_D), Vector3(wall_x, (9.2 + ROOM_H) / 2.0, 0), COL_WALL)
		for post_z: float in [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]:
			_static_box(Vector3(WALL_T, 1.6, 0.14), Vector3(wall_x, 8.4, post_z), COL_STEEL)
		_glass(Vector3(0.06, 1.6, ROOM_D), Vector3(wall_x, 8.4, 0))

	# Long walls (z = +-13). The entry wall (+z) gets two glazed bands;
	# the plant wall (-z) only the upper one (mezzanines run along it).
	for side: float in [-1.0, 1.0]:
		var wall_z := side * half_d
		if side > 0.0:
			_static_box(Vector3(ROOM_W, 3.0, WALL_T), Vector3(0, 1.5, wall_z), COL_WALL)
			_static_box(Vector3(ROOM_W, 3.0, WALL_T), Vector3(0, 6.1, wall_z), COL_WALL)
			for post_x: float in [-20.0, -16.0, -12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0, 16.0, 20.0]:
				_static_box(Vector3(0.14, 1.6, WALL_T), Vector3(post_x, 3.8, wall_z), COL_STEEL)
			_glass(Vector3(ROOM_W, 1.6, 0.06), Vector3(0, 3.8, wall_z))
		else:
			_static_box(Vector3(ROOM_W, 7.6, WALL_T), Vector3(0, 3.8, wall_z), COL_WALL)
		for post_x: float in [-20.0, -16.0, -12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0, 16.0, 20.0]:
			_static_box(Vector3(0.14, 1.6, WALL_T), Vector3(post_x, 8.4, wall_z), COL_STEEL)
		_glass(Vector3(ROOM_W, 1.6, 0.06), Vector3(0, 8.4, wall_z))
		_static_box(Vector3(ROOM_W, ROOM_H - 9.2, WALL_T), Vector3(0, (9.2 + ROOM_H) / 2.0, wall_z), COL_WALL)

	# Roof: solid strips with two skylight bands (z = -6 and +6).
	var ceil_y := ROOM_H + 0.1
	for strip: Array in [[-10.25, 5.5], [0.0, 9.0], [10.25, 5.5]]:
		_static_box(Vector3(ROOM_W, 0.2, strip[1]), Vector3(0, ceil_y, strip[0]), COL_WALL)
	for row_z: float in [-6.0, 6.0]:
		for fill_x: float in [-20.75, 20.75]:
			_static_box(Vector3(2.5, 0.2, 3.0), Vector3(fill_x, ceil_y, row_z), COL_WALL)
		for i: int in range(6):
			_static_box(Vector3(3.0, 0.2, 3.0), Vector3(-15.0 + i * 6.0, ceil_y, row_z), COL_WALL)
		for i: int in range(7):
			_glass(Vector3(2.96, 0.06, 2.96), Vector3(-18.0 + i * 6.0, ROOM_H + 0.16, row_z))

	# Steel frame: interior columns, roof beams.
	for col: Vector2 in [
			Vector2(-16, -8), Vector2(-16, 0), Vector2(-16, 8),
			Vector2(-8, -8), Vector2(-8, 0), Vector2(-8, 8),
			Vector2(0, -8), Vector2(0, 8),
			Vector2(8, -8), Vector2(8, 0), Vector2(8, 8),
			Vector2(16, -8), Vector2(16, 0), Vector2(16, 8)]:
		_static_box(Vector3(0.4, ROOM_H, 0.4), Vector3(col.x, ROOM_H / 2.0, col.y), COL_STEEL)
	for beam_z: float in [-4.5, 4.5]:
		_static_box(Vector3(ROOM_W, 0.4, 0.25), Vector3(0, ROOM_H - 0.4, beam_z), COL_STEEL)
	for beam_x: float in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_static_box(Vector3(0.3, 0.35, ROOM_D), Vector3(beam_x, ROOM_H - 0.8, 0), COL_STEEL)


func _build_mezzanines() -> void:
	# Level 1 along the plant wall (leaves the corner to the side deck).
	_deck(Vector3(37.0, 0.15, 3.5), Vector3(-3.5, MEZZ1_Y, -11.25))
	# Level 1 side deck along the +x wall.
	_deck(Vector3(7.0, 0.15, 26.0), Vector3(18.5, MEZZ1_Y, 0.0))
	# Level 2 gallery along the plant wall.
	_deck(Vector3(44.0, 0.15, 2.5), Vector3(0, MEZZ2_Y, -11.75))

	# Support posts under the open edges.
	for post_x: float in [-20.0, -12.0, -4.0, 4.0, 12.0]:
		_static_box(Vector3(0.25, MEZZ1_Y, 0.25), Vector3(post_x, MEZZ1_Y / 2.0, -9.7), COL_STEEL)
	for post_z: float in [-4.0, 4.0, 12.0]:
		_static_box(Vector3(0.25, MEZZ1_Y, 0.25), Vector3(15.2, MEZZ1_Y / 2.0, post_z), COL_STEEL)
	for post_x: float in [-18.0, -6.0, 6.0, 18.0]:
		_static_box(Vector3(0.22, MEZZ2_Y - MEZZ1_Y, 0.22), Vector3(post_x, (MEZZ1_Y + MEZZ2_Y) / 2.0, -10.6), COL_STEEL)

	# Railings, with gaps where the stairs land.
	_railing(Vector3(-22, MEZZ1_Y, -9.5), Vector3(-8.7, MEZZ1_Y, -9.5))
	_railing(Vector3(-7.4, MEZZ1_Y, -9.5), Vector3(15, MEZZ1_Y, -9.5))
	_railing(Vector3(15, MEZZ1_Y, -9.5), Vector3(15, MEZZ1_Y, 7.3))
	_railing(Vector3(15, MEZZ1_Y, 8.7), Vector3(15, MEZZ1_Y, 13))
	_railing(Vector3(-22, MEZZ2_Y, -10.5), Vector3(-14.7, MEZZ2_Y, -10.5))
	_railing(Vector3(-13.3, MEZZ2_Y, -10.5), Vector3(22, MEZZ2_Y, -10.5))

	# Stairs: ground -> mezz 1 (two of them), mezz 1 -> gallery.
	_stairs(Vector3(-8.0, MEZZ1_Y, -9.5), Vector3(0, 0, 1), MEZZ1_Y, 1.3)
	_stairs(Vector3(15.0, MEZZ1_Y, 8.0), Vector3(-1, 0, 0), MEZZ1_Y, 1.3)
	_stairs(Vector3(-8.4, MEZZ2_Y, -11.5), Vector3(-1, 0, 0), MEZZ2_Y - MEZZ1_Y, 1.3)


func _deck(size: Vector3, pos: Vector3) -> void:
	_static_box(size, pos, COL_DECK)


func _railing(from: Vector3, to: Vector3) -> void:
	var run := to - from
	var length := run.length()
	var direction := run.normalized()
	var mid := (from + to) / 2.0
	var along := Vector3(length, 0, 0) if absf(direction.x) > 0.5 else Vector3(0, 0, length)
	var rail_size := along + Vector3(0.06 if along.x == 0 else 0, 0.06, 0.06 if along.z == 0 else 0)
	ViewUtil.box(self, rail_size, mid + Vector3(0, 1.05, 0), ViewUtil.flat(COL_STEEL))
	ViewUtil.box(self, rail_size, mid + Vector3(0, 0.55, 0), ViewUtil.flat(COL_STEEL))
	var kick_size := along + Vector3(0.04 if along.x == 0 else 0, 0.15, 0.04 if along.z == 0 else 0)
	ViewUtil.box(self, kick_size, mid + Vector3(0, 0.12, 0), ViewUtil.flat(COL_SAFETY))
	var posts := maxi(2, int(length / 2.0) + 1)
	for i: int in range(posts):
		var t := float(i) / float(posts - 1)
		ViewUtil.box(self, Vector3(0.06, 1.05, 0.06),
			from.lerp(to, t) + Vector3(0, 0.525, 0), ViewUtil.flat(COL_STEEL))
	# One invisible wall so the player can't stroll off the edge.
	var body := StaticBody3D.new()
	body.position = mid + Vector3(0, 0.6, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = along + Vector3(0.08 if along.x == 0 else 0, 1.2, 0.08 if along.z == 0 else 0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## Open-riser steel stairs. Treads are visual; an invisible wedge ramp
## (convex hull, no rotation math to get wrong) does the climbing.
func _stairs(top: Vector3, direction: Vector3, rise: float, width: float) -> void:
	var step_rise := 0.2
	var tread := 0.28
	var steps := int(round(rise / step_rise))
	var run := tread * steps
	for i: int in range(steps):
		var center := top + direction * (tread * (i + 0.5)) \
			+ Vector3(0, -step_rise * (i + 1) + 0.03, 0)
		var size := Vector3(tread, 0.06, width) if absf(direction.x) > 0.5 \
			else Vector3(width, 0.06, tread)
		ViewUtil.box(self, size, center, ViewUtil.flat(COL_DECK))
	var right := direction.cross(Vector3.UP).normalized()
	var points := PackedVector3Array()
	for side: float in [-1.0, 1.0]:
		var offset := right * (width / 2.0 * side)
		points.append(offset)                                       # top edge
		points.append(offset + Vector3(0, -rise, 0))                # below top
		points.append(offset + direction * run + Vector3(0, -rise, 0))  # bottom
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var body := StaticBody3D.new()
	body.position = top
	var shape := CollisionShape3D.new()
	shape.shape = hull
	body.add_child(shape)
	add_child(body)


func _build_pipes() -> void:
	# Main headers high on the plant wall.
	_pipe_run([Vector3(-22, 9.6, -12.4), Vector3(22, 9.6, -12.4)], 0.30, COL_PIPE_BLUE)
	_pipe_run([Vector3(-22, 9.0, -12.4), Vector3(22, 9.0, -12.4)], 0.20, COL_PIPE_GRAY)
	_pipe_run([Vector3(-22, 8.5, -12.4), Vector3(22, 8.5, -12.4)], 0.14, COL_PIPE_YELLOW)
	# Riser dropping from the header, running toward the plant.
	_pipe_run([Vector3(4.5, 9.6, -12.4), Vector3(4.5, 1.1, -12.4),
		Vector3(4.5, 1.1, -6.0), Vector3(3.2, 1.1, -3.6)], 0.14, COL_PIPE_STEEL)
	# Cross-hall runs under the roof.
	_pipe_run([Vector3(-14, 11.0, -13), Vector3(-14, 11.0, 13)], 0.25, COL_PIPE_GRAY)
	_pipe_run([Vector3(10, 11.0, -13), Vector3(10, 11.0, 13)], 0.25, COL_PIPE_BLUE)
	# Utility pair tucked under the side mezzanine.
	_pipe_run([Vector3(21.2, 3.6, -13), Vector3(21.2, 3.6, 13)], 0.16, COL_PIPE_GRAY)
	_pipe_run([Vector3(20.7, 3.6, -13), Vector3(20.7, 3.6, 13)], 0.16, COL_PIPE_STEEL)


func _pipe_run(points: Array, radius: float, color: Color) -> void:
	var mat := ViewUtil.flat(color)
	mat.roughness = 0.5
	for i: int in range(points.size() - 1):
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		var length := from.distance_to(to)
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = mat
		add_child(inst)
		inst.position = (from + to) / 2.0
		var direction := (to - from).normalized()
		if absf(direction.y) < 0.99:
			inst.look_at(to, Vector3.UP)
			inst.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		if i > 0:
			var elbow := SphereMesh.new()
			elbow.radius = radius * 1.15
			elbow.height = radius * 2.3
			var joint := MeshInstance3D.new()
			joint.mesh = elbow
			joint.material_override = mat
			joint.position = from
			add_child(joint)


func _build_fixtures() -> void:
	for grid_x: float in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		for grid_z: float in [-8.0, 0.0, 8.0]:
			var strip := ViewUtil.box(self, Vector3(2.2, 0.06, 0.14),
				Vector3(grid_x, ROOM_H - 1.5, grid_z), ViewUtil.glow(Color(0.95, 0.94, 0.90), 2.2))
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var light := OmniLight3D.new()
			light.position = Vector3(grid_x, ROOM_H - 1.8, grid_z)
			light.light_energy = 1.3
			light.light_color = Color(1.0, 0.96, 0.90)
			light.omni_range = 12.0
			add_child(light)
	# The zone under the level-1 mezzanine needs its own light.
	for under_x: float in [-16.0, -8.0, 0.0, 8.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(under_x, MEZZ1_Y - 0.6, -11.2)
		light.light_energy = 0.8
		light.light_color = Color(1.0, 0.96, 0.90)
		light.omni_range = 6.0
		add_child(light)


func _build_markings() -> void:
	var y := 0.006
	_marking(Vector3(10.0, 0.012, 0.08), Vector3(-1.0, y, -0.9))
	_marking(Vector3(0.08, 0.012, 4.0), Vector3(-6.0, y, -2.9))
	_marking(Vector3(0.08, 0.012, 4.0), Vector3(4.0, y, -2.9))


func _marking(size: Vector3, pos: Vector3) -> void:
	ViewUtil.box(self, size, pos, ViewUtil.flat(COL_SAFETY)) \
		.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _glass(size: Vector3, pos: Vector3) -> void:
	var mat := ViewUtil.flat(COL_GLASS)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.2
	mat.roughness = 0.05
	var pane := ViewUtil.box(self, size, pos, mat)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
