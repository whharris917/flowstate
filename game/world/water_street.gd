class_name WaterStreet
extends RefCounted
## Water Street dressed as lived in: the street along the town's harbour
## edge. Every house on it gets a picket fence with its gate, a
## mailbox, pumpkins by the steps (some carved, lit at dusk), pots of
## chrysanthemums, and a share of the rest: bicycles leaning on the
## fence, a wagon, window boxes, a bed of mums along the foundation,
## rocking chairs and a swing on a porch, a flag by the door, milk
## and the paper on the step, a cat, a raked pile of leaves. The south
## side's back yards run down toward the harbour: vegetable beds at the
## season's end, bird baths and feeders, woodpiles, Adirondack chairs
## turned to the water, the wash on the line, a dory turned over for
## the winter, a shed hung with buoys, an apple tree. Smoke rises from
## every chimney on the street and leans with the wind.
##
## Art only. Each house's plan comes from HarborTown.houses_built; the
## Cape at 14 is dressed to match.



static func dress(town: HarborTown) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1944
	for h: Dictionary in town.houses_built:
		if not bool(h["water"]):
			continue
		_front(town, h, rng)
		if bool(h["harbour_side"]):
			_back(town, h, rng)
		_smoke(town, h["chimney"])
	_cape(town, rng)
	_smoke(town, town.cape.transform * Vector3(-5.3, 8.7, -4.0))


## A transform at a point of a house's frame, set on the ground there.
static func _ground(town: HarborTown, base: Transform3D, local: Vector3, yaw := 0.0) -> Transform3D:
	var p := base * local
	p.y = town.coast.height_at(p.x, p.z) + local.y
	return Transform3D(base.basis * Basis(Vector3.UP, yaw), p)


static func _front(town: HarborTown, h: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := town.m
	var base: Transform3D = h["base"]
	var w: float = h["w"]
	var door_x: float = h["door_x"]
	var found: float = h["found"]
	var style: int = h["style"]
	# The front yard reaches to the road's edge: four metres on the south
	# side, three on the north.
	var depth := 4.0 if bool(h["harbour_side"]) else 3.0
	var fz := depth - 0.45
	YardProps.picket_fence(m, base * HarborTown.at(Vector3(0, 0, fz)), -5.8, 5.8, door_x)
	for seg: Vector2 in [Vector2(-5.8, door_x - 0.62), Vector2(door_x + 0.62, 5.8)]:
		town._solid(base * HarborTown.at(Vector3((seg.x + seg.y) / 2.0, 0.5, fz)), Vector3(seg.y - seg.x, 1.0, 0.1))
	var box_colors: Array[Color] = [Color(0.15, 0.2, 0.18), Color(0.12, 0.12, 0.12), Color(0.55, 0.12, 0.1), Color(0.2, 0.28, 0.45)]
	YardProps.mailbox(m, base * HarborTown.at(Vector3(door_x + 1.0, 0, fz + 0.3)), box_colors[rng.randi() % box_colors.size()], rng.randf() < 0.3)
	# Where the door is met: the porch floor, or the top step.
	var porch := style == 2
	var stand_y := found + 0.05 if porch else found - 0.05
	var stand_z := 0.6 if porch else 0.35
	if rng.randf() < 0.6:
		YardProps.milk_and_paper(m, base * HarborTown.at(Vector3(door_x + 0.35, stand_y, stand_z)))
	if rng.randf() < 0.2:
		var furs: Array[Color] = [Color(0.12, 0.1, 0.09), Color(0.7, 0.45, 0.2), Color(0.55, 0.55, 0.55), Color(0.9, 0.88, 0.82)]
		YardProps.cat(m, base * HarborTown.at(Vector3(door_x - 0.3, stand_y, stand_z + 0.1), rng.randf_range(-0.6, 0.6)), furs[rng.randi() % furs.size()])
	# Pumpkins by the steps, some carved; pots of mums.
	var blooms: Array[Color] = [Color(0.85, 0.55, 0.12), Color(0.75, 0.2, 0.2), Color(0.85, 0.75, 0.25), Color(0.55, 0.3, 0.6)]
	var step_z := 2.8 if porch else 1.1
	for s: float in [-1.0, 1.0]:
		var px := door_x + s * (1.0 + rng.randf_range(0.0, 0.3))
		if rng.randf() < 0.75:
			YardProps.pumpkin(m, base * HarborTown.at(Vector3(px, 0, step_z), rng.randf_range(-0.4, 0.4)), rng.randf_range(0.13, 0.2), rng.randf() < 0.5, rng.randf())
		if rng.randf() < 0.6:
			YardProps.flower_pot(m, base * HarborTown.at(Vector3(px + s * 0.4, 0, step_z - 0.15)), blooms[rng.randi() % blooms.size()])
	# Window boxes under the first-floor windows.
	if rng.randf() < 0.6:
		var f1: float = h["f1"]
		for x: float in h["front_xs"]:
			YardProps.window_box(m, base * HarborTown.at(Vector3(x, f1 - 0.86, 0.0)), 0.85, rng)
	# Mums along the foundation where no porch stands.
	if not porch and rng.randf() < 0.6:
		var x0 := door_x + 1.2
		var x1 := w / 2.0 - 0.3
		if x1 - x0 > 1.0:
			YardProps.mum_bed(m, base * HarborTown.at(Vector3((x0 + x1) / 2.0, 0, 0.45)), x1 - x0, rng)
	# The porch: rockers, a swing, a flag.
	var paints: Array[Color] = [Color(0.92, 0.91, 0.87), Color(0.25, 0.38, 0.3), Color(0.12, 0.12, 0.12), Color(0.55, 0.15, 0.12)]
	if porch:
		var paint := paints[rng.randi() % paints.size()]
		YardProps.rocker(m, base * HarborTown.at(Vector3(-0.2, found + 0.05, 1.3), rng.randf_range(-0.4, 0.2)), paint)
		YardProps.rocker(m, base * HarborTown.at(Vector3(0.8, found + 0.05, 1.3), rng.randf_range(-0.2, 0.4)), paint)
		YardProps.porch_swing(m, base * HarborTown.at(Vector3(w / 2.0 - 1.05, found + 0.05, 1.1)), found + 2.75, paint)
	elif rng.randf() < 0.45:
		# Two chairs out on the lawn, turned to each other.
		var paint := paints[rng.randi() % paints.size()]
		var cx := -w / 2.0 + 1.3 if door_x > -1.0 else w / 2.0 - 1.3
		YardProps.adirondack(m, base * HarborTown.at(Vector3(cx - 0.55, 0, 2.2), PI / 2.0 + 0.4), paint)
		YardProps.adirondack(m, base * HarborTown.at(Vector3(cx + 0.55, 0, 2.2), -PI / 2.0 - 0.4), paint)
	if rng.randf() < 0.4:
		YardProps.flag(m, base * HarborTown.at(Vector3(door_x + (-0.75 if porch else 0.8), found + 1.9, 0.06)))
	# Children's things by the fence.
	var frames: Array[Color] = [Color(0.62, 0.1, 0.08), Color(0.15, 0.3, 0.55), Color(0.2, 0.42, 0.25), Color(0.1, 0.1, 0.1)]
	if rng.randf() < 0.5:
		var bx := door_x + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(1.8, 3.8)
		YardProps.bicycle(m, base * HarborTown.at(Vector3(bx, 0, fz - 0.33)), frames[rng.randi() % frames.size()], -0.24)
		if rng.randf() < 0.35:
			YardProps.bicycle(m, base * HarborTown.at(Vector3(bx + (1.2 if bx < door_x else -1.2), 0, fz - 0.33)), frames[rng.randi() % frames.size()], -0.26)
	if rng.randf() < 0.25:
		YardProps.wagon(m, base * HarborTown.at(Vector3(door_x + rng.randf_range(-3.0, 3.0), 0, 2.0 if not porch else 3.0), rng.randf_range(0.0, TAU)))
	if rng.randf() < 0.35:
		YardProps.leaf_pile(m, base * HarborTown.at(Vector3(door_x + (-3.4 if door_x > -1.0 else 2.8), 0, depth - 1.5), rng.randf_range(0.0, TAU)), rng)
	var front := base * Vector3(0, 0, depth / 2.0)
	var span := (base.basis * Vector3(12.0, 0, depth)).abs()
	town._keep_clear.append(Rect2(Vector2(front.x - span.x / 2.0, front.z - span.z / 2.0), Vector2(span.x, span.z)))


static func _back(town: HarborTown, h: Dictionary, rng: RandomNumberGenerator) -> void:
	var m := town.m
	var base: Transform3D = h["base"]
	var w: float = h["w"]
	var d: float = h["d"]
	var z0 := -d
	var found: float = h["found"]
	# The kitchen door at the back: a door, its trim, a granite stoop; the
	# trash can by it, a rain barrel under the downspout at the corner.
	var bx := 0.0 if int(h["style"]) == 2 else -w / 2.0 + 1.8
	var door_paint: Color = [Color(0.25, 0.38, 0.30), Color(0.45, 0.09, 0.08), Color(0.92, 0.91, 0.87)][rng.randi() % 3]
	m.box("wall", base * HarborTown.at(Vector3(bx, found + 1.0, z0 - 0.03)), Vector3(0.88, 2.0, 0.06), HarborTown.kc(door_paint, HarborTown.K_PAINT), true)
	m.quad("clear", base * Vector3(bx - 0.3, found + 1.25, z0 - 0.07), base * Vector3(bx - 0.3, found + 1.8, z0 - 0.07),
		base * Vector3(bx + 0.3, found + 1.8, z0 - 0.07), base * Vector3(bx + 0.3, found + 1.25, z0 - 0.07), base.basis * Vector3(0, 0, -1), Color.WHITE)
	var trim := HarborTown.kc(HarborTown.TRIM, HarborTown.K_PAINT)
	for s2: float in [-1.0, 1.0]:
		m.box("wall", base * HarborTown.at(Vector3(bx + s2 * 0.5, found + 1.05, z0 - 0.04)), Vector3(0.1, 2.1, 0.06), trim, true)
	m.box("wall", base * HarborTown.at(Vector3(bx, found + 2.12, z0 - 0.05)), Vector3(1.1, 0.12, 0.08), trim, true)
	m.box("wall", _ground(town, base, Vector3(bx, found / 2.0 - 0.03, z0 - 0.45)), Vector3(1.3, found, 0.9), HarborTown.kc(HarborTown.GRANITE, HarborTown.K_GRANITE), true)
	m.box("wall", _ground(town, base, Vector3(bx, found / 4.0, z0 - 1.05)), Vector3(1.1, found / 2.0, 0.35), HarborTown.kc(HarborTown.GRANITE, HarborTown.K_GRANITE), true)
	var can := _ground(town, base, Vector3(bx + 1.05, 0, z0 - 0.4))
	m.cylinder("steel", can * HarborTown.at(Vector3(0, 0.36, 0)), 0.24, 0.26, 0.72, 14, Color.WHITE)
	m.cylinder("steel", can * HarborTown.at(Vector3(0, 0.74, 0)), 0.27, 0.27, 0.05, 14, Color.WHITE)
	m.cylinder("iron", can * HarborTown.at(Vector3(0, 0.79, 0)), 0.05, 0.05, 0.04, 8, Color(0.5, 0.5, 0.5))
	var corner := _ground(town, base, Vector3(-w / 2.0 + 0.4, 0, z0 - 0.4))
	m.cylinder("wall", corner * HarborTown.at(Vector3(0, 0.45, 0)), 0.3, 0.3, 0.9, 12, HarborTown.kc(Color(0.42, 0.32, 0.22), HarborTown.K_TIMBER))
	for y: float in [0.15, 0.75]:
		m.cylinder("iron", corner * HarborTown.at(Vector3(0, y, 0)), 0.31, 0.31, 0.04, 12, Color(0.2, 0.2, 0.2))
	var eave := base * Vector3(-w / 2.0 + 0.1, 3.4 if int(h["style"]) == 0 else 6.0, z0 - 0.1)
	m.bar("wall", corner.origin + Vector3(0, 0.95, 0), eave, 0.04, 6, trim)
	if rng.randf() < 0.25:
		var dog := _ground(town, base, Vector3(-4.3, 0, z0 - 1.4), PI)
		m.box("wall", dog * HarborTown.at(Vector3(0, 0.35, 0)), Vector3(0.8, 0.7, 1.0), HarborTown.kc(Color(0.55, 0.15, 0.12), HarborTown.K_CLAP), true)
		m.prism("wall", dog * HarborTown.at(Vector3(0, 0.7, 0)), 0.95, 0.4, 1.1, HarborTown.kc(Color(0.22, 0.22, 0.22), HarborTown.K_ROOF))
		m.box("wall", dog * HarborTown.at(Vector3(0, 0.28, 0.505)), Vector3(0.32, 0.42, 0.01), HarborTown.kc(Color(0.05, 0.05, 0.05), HarborTown.K_PAINT), true)
		m.cylinder("wall", dog * HarborTown.at(Vector3(0.6, 0.04, 0.6)), 0.12, 0.1, 0.08, 10, HarborTown.kc(Color(0.6, 0.62, 0.7), HarborTown.K_ENAMEL))
	# The garden, the bird bath and feeder.
	if rng.randf() < 0.75:
		YardProps.vegetable_bed(m, _ground(town, base, Vector3(-2.3, 0, z0 - 3.4)), Vector2(3.0, 2.0), rng)
		if rng.randf() < 0.5:
			YardProps.wheelbarrow(m, _ground(town, base, Vector3(-0.2, 0, z0 - 3.0), rng.randf_range(-0.5, 0.5)))
	if rng.randf() < 0.65:
		YardProps.bird_bath(m, _ground(town, base, Vector3(1.8, 0, z0 - 2.4)))
	if rng.randf() < 0.45:
		YardProps.bird_feeder(m, _ground(town, base, Vector3(3.6, 0, z0 - 3.8)))
	if rng.randf() < 0.55:
		YardProps.woodpile(m, _ground(town, base, Vector3(w / 2.0 - 1.6, 0, z0 - 0.45)), 2.0)
	# Out at the foot of the yard, toward the water: the wash, the
	# chairs turned to the harbour, a dory for the winter, a shed.
	var line := rng.randf() < 0.45
	if line:
		YardProps.clothesline(m, _ground(town, base, Vector3(-0.8, 0, z0 - 6.2)), 5.0, rng)
	if rng.randf() < 0.65:
		var paint: Color = [Color(0.92, 0.91, 0.87), Color(0.25, 0.38, 0.3), Color(0.55, 0.15, 0.12)][rng.randi() % 3]
		var cz := z0 - (4.8 if line else 6.4)
		YardProps.adirondack(m, _ground(town, base, Vector3(-0.2, 0, cz), PI + 0.15), paint)
		YardProps.adirondack(m, _ground(town, base, Vector3(0.8, 0, cz), PI - 0.15), paint)
		m.cylinder("wall", _ground(town, base, Vector3(0.3, 0.25, cz - 0.1)), 0.18, 0.18, 0.5, 10, HarborTown.kc(paint, HarborTown.K_PAINT))
	if rng.randf() < 0.3:
		var hulls: Array[Color] = [Color(0.80, 0.72, 0.52), Color(0.36, 0.48, 0.40), Color(0.85, 0.85, 0.8)]
		YardProps.dory_on_horses(m, _ground(town, base, Vector3(-3.4, 0, z0 - 6.6)), hulls[rng.randi() % hulls.size()])
	if rng.randf() < 0.35:
		var foot := _ground(town, base, Vector3(3.4, 0, z0 - 6.0))
		town._shed(foot.origin, base.basis.get_euler().y, 2.4, 2.0, 2.1, HarborTown.kc(Color(0.56, 0.53, 0.49), HarborTown.K_SHAKE), false)
		var buoys: Array[Color] = [Color(0.85, 0.75, 0.2), Color(0.8, 0.2, 0.15), Color(0.9, 0.9, 0.85), Color(0.2, 0.5, 0.3)]
		for k in 4:
			m.cylinder("wall", foot * HarborTown.at(Vector3(-0.8 + 0.5 * k, 1.35 + 0.15 * (k % 2), 0.05)), 0.09, 0.09, 0.45, 8,
				HarborTown.kc(buoys[k], HarborTown.K_PAINT))
	elif rng.randf() < 0.5:
		town._trees.plant_broadleaf(_ground(town, base, Vector3(3.8, 0, z0 - 5.0)).origin, rng.randf_range(5.0, 6.5), Color(0.45, 0.5, 0.15), rng)
	# A split-rail fence along the foot of the yard.
	var rail := HarborTown.kc(Color(0.52, 0.48, 0.42), HarborTown.K_TIMBER)
	var fz := z0 - 8.2
	var prev := Vector3.ZERO
	for k in 5:
		var x := -5.8 + 2.9 * k
		var foot := _ground(town, base, Vector3(x, 0, fz)).origin
		m.cylinder("wall", HarborTown.at(foot + Vector3(0, 0.55, 0)), 0.06, 0.06, 1.1, 6, rail)
		if k > 0:
			for y: float in [0.45, 0.9]:
				m.bar("wall", prev + Vector3(0, y, 0), foot + Vector3(0, y, 0), 0.045, 5, rail)
		prev = foot
	var back := base * Vector3(0, 0, z0 - 4.2)
	var span := (base.basis * Vector3(12.0, 0, 8.6)).abs()
	town._keep_clear.append(Rect2(Vector2(back.x - span.x / 2.0, back.z - span.z / 2.0), Vector2(span.x, span.z)))


## Number 14, dressed to match: pumpkins, pots, window boxes, a bicycle
## at the fence, a garden and a bird bath out back, chairs to the water.
static func _cape(town: HarborTown, rng: RandomNumberGenerator) -> void:
	var m := town.m
	var base := town.cape.transform
	var d := CapeHouse.D
	for s: float in [-1.0, 1.0]:
		YardProps.pumpkin(m, base * HarborTown.at(Vector3(s * 1.05, 0, 1.45), rng.randf_range(-0.3, 0.3)), 0.18, s > 0.0, 0.4)
		YardProps.flower_pot(m, base * HarborTown.at(Vector3(s * 0.7, 0.6, 0.35)), Color(0.85, 0.55, 0.12), 0.8)
	YardProps.pumpkin(m, base * HarborTown.at(Vector3(-1.3, 0, 1.75)), 0.12, false, 0.0)
	for x: float in [-3.4, -1.8, 1.8, 3.4]:
		YardProps.window_box(m, base * HarborTown.at(Vector3(x, CapeHouse.F + 0.6, 0.0)), 0.9, rng)
	YardProps.bicycle(m, base * HarborTown.at(Vector3(3.6, 0, 3.05)), Color(0.62, 0.1, 0.08), -0.24)
	YardProps.milk_and_paper(m, base * HarborTown.at(Vector3(0.35, 0.6, 0.35)))
	YardProps.cat(m, base * HarborTown.at(Vector3(-0.4, 0.2, 0.9), 0.3), Color(0.7, 0.45, 0.2))
	YardProps.vegetable_bed(m, _ground(town, base, Vector3(-2.6, 0, -d - 5.4)), Vector2(3.0, 2.0), rng)
	YardProps.bird_bath(m, _ground(town, base, Vector3(2.6, 0, -d - 5.0)))
	YardProps.woodpile(m, _ground(town, base, Vector3(-4.2, 0, -d - 0.45)), 1.4)
	YardProps.adirondack(m, _ground(town, base, Vector3(0.0, 0, -d - 7.4), PI + 0.15), Color(0.25, 0.38, 0.3))
	YardProps.adirondack(m, _ground(town, base, Vector3(1.0, 0, -d - 7.4), PI - 0.15), Color(0.25, 0.38, 0.3))
	YardProps.leaf_pile(m, base * HarborTown.at(Vector3(-4.0, 0, 2.3)), rng)


## Wood smoke from a chimney: soft puffs rising, spreading, thinning,
## carried off by the wind (the weather leans them).
static func _smoke(town: HarborTown, top: Vector3) -> void:
	var smoke := GPUParticles3D.new()
	smoke.amount = 36
	smoke.lifetime = 9.0
	smoke.preprocess = 9.0
	smoke.local_coords = false
	smoke.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 30, 60))
	smoke.position = top
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(-0.3, 0.25, -0.3)
	pm.damping_min = 0.05
	pm.damping_max = 0.1
	pm.scale_min = 0.5
	pm.scale_max = 0.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 3.2))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.62, 0.6, 0.58, 0.0))
	fade.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	fade.add_point(0.08, Color(0.5, 0.48, 0.46, 0.32))
	fade.add_point(0.5, Color(0.6, 0.6, 0.6, 0.16))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	smoke.process_material = pm
	var puff := QuadMesh.new()
	puff.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.render_priority = 2
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var disc := GradientTexture2D.new()
	disc.gradient = soft
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(1.0, 0.5)
	disc.width = 64
	disc.height = 64
	mat.albedo_texture = disc
	puff.material = mat
	smoke.draw_pass_1 = puff
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.add_child(smoke)
	town.smoke.append(pm)
