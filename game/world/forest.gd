class_name Forest
extends Node3D
## A forest around the clearing: the plant stands in a large clearing
## with trees in the near distance hiding the horizon from ground
## level. Two rings of procedural trees — conifers of stacked
## cones and broadleaves of clustered spheres on trunks — drawn with
## MultiMeshes so a few thousand cost almost nothing. Deterministic
## from a seed. Art only: no records, no collision, nothing simulated.

const TRUNK_COLOR := Color(0.20, 0.14, 0.09)
const SNAG_COLOR := Color(0.33, 0.31, 0.28)
const CONIFER_COLOR := Color(0.05, 0.12, 0.05)
const BROADLEAF_COLOR := Color(0.08, 0.17, 0.06)

var _trunk_xforms: Array[Transform3D] = []
var _trunk_colors: Array[Color] = []
var _cone_xforms: Array[Transform3D] = []
var _cone_colors: Array[Color] = []
var _ball_xforms: Array[Transform3D] = []
var _ball_colors: Array[Color] = []
## Every tree as planted, for a detailed finish: [foot, height, yaw,
## kind (0 conifer, 1 broadleaf), leaf colour].
var _plants: Array = []
var _snag_xforms: Array[Transform3D] = []


## Trees between r_in and r_out from centre, about one per `spacing`
## squared metres, `height` metres tall on average.
func plant_ring(center: Vector3, r_in: float, r_out: float, spacing: float,
		height: float, rng: RandomNumberGenerator) -> int:
	var count := int(PI * (r_out * r_out - r_in * r_in) / (spacing * spacing))
	for _i in count:
		# Uniform over the annulus: radius from the area, not the length.
		var r := sqrt(rng.randf_range(r_in * r_in, r_out * r_out))
		var a := rng.randf_range(0.0, TAU)
		var at := center + Vector3(r * cos(a), 0.0, r * sin(a))
		var h := height * rng.randf_range(0.7, 1.35)
		var yaw := rng.randf_range(0.0, TAU)
		if rng.randf() < 0.6:
			_conifer(at, h, yaw, rng)
		else:
			_broadleaf(at, h, yaw, rng)
	return count


## Low bushes between r_in and r_out: they close the gap between the
## trunks at the foot of the tree line, so the wood reads as solid.
func plant_bushes(center: Vector3, r_in: float, r_out: float, spacing: float,
		rng: RandomNumberGenerator) -> int:
	var count := int(PI * (r_out * r_out - r_in * r_in) / (spacing * spacing))
	for _i in count:
		var r := sqrt(rng.randf_range(r_in * r_in, r_out * r_out))
		var a := rng.randf_range(0.0, TAU)
		var at := center + Vector3(r * cos(a), 0.0, r * sin(a))
		var size := rng.randf_range(1.2, 2.6)
		var tint := BROADLEAF_COLOR.lightened(rng.randf_range(-0.02, 0.06))
		_ball_xforms.append(_xform(at + Vector3(0, size * 0.45, 0), rng.randf_range(0.0, TAU),
			Vector3(size, size * 0.7, size * rng.randf_range(0.8, 1.2))))
		_ball_colors.append(tint)
	return count


## Trees scattered over a rectangle wherever the ground will take one
## (a landscape): sampler.call(x, z) answers the ground
## height for a tree there, or -INF for none — water, ledge, the
## graded site. conifer_frac is the share of conifers; the Maine coast
## is spruce and fir nearly to the water, with a few grey snags where
## the salt has killed them.
func plant_scatter(min_xz: Vector2, max_xz: Vector2, spacing: float, height: float,
		conifer_frac: float, rng: RandomNumberGenerator, sampler: Callable) -> int:
	var count := int((max_xz.x - min_xz.x) * (max_xz.y - min_xz.y) / (spacing * spacing))
	var planted := 0
	for _i in count:
		var x := rng.randf_range(min_xz.x, max_xz.x)
		var z := rng.randf_range(min_xz.y, max_xz.y)
		var kind := rng.randf()
		var h := height * rng.randf_range(0.7, 1.35)
		var yaw := rng.randf_range(0.0, TAU)
		var y: float = sampler.call(x, z)
		if y == -INF:
			continue
		var at := Vector3(x, y, z)
		if kind < conifer_frac * 0.06:
			_snag(at, h * 0.6, yaw)
		elif kind < conifer_frac:
			_conifer(at, h, yaw, rng)
		else:
			_broadleaf(at, h, yaw, rng)
		planted += 1
	return planted


## A dead spruce: a bare grey trunk, tapered, with two broken limbs.
func _snag(at: Vector3, h: float, yaw: float) -> void:
	var trunk_r := h * 0.03
	_snag_xforms.append(_xform(at + Vector3(0, h / 2.0, 0), yaw, Vector3(trunk_r, h, trunk_r)))
	_trunk_xforms.append(_xform(at + Vector3(0, h / 2.0, 0), yaw, Vector3(trunk_r, h, trunk_r)))
	_trunk_colors.append(SNAG_COLOR)
	for k in 2:
		var a := yaw + 1.2 + 2.4 * k
		var limb := h * 0.12
		var tilt := Basis.from_euler(Vector3(0, a, 0)) * Basis.from_euler(Vector3(0, 0, -1.1))
		_trunk_xforms.append(Transform3D(tilt.scaled(Vector3(trunk_r * 0.5, limb, trunk_r * 0.5)),
			at + Vector3(cos(a) * limb * 0.4, h * (0.5 + 0.2 * k), -sin(a) * limb * 0.4)))
		_trunk_colors.append(SNAG_COLOR.darkened(0.1))


func _conifer(at: Vector3, h: float, yaw: float, rng: RandomNumberGenerator) -> void:
	# Proportions of a real spruce: a trunk a thirtieth of the height,
	# a crown about a third as wide as it is tall.
	var trunk_h := h * 0.25
	var trunk_r := h * 0.035
	_trunk_xforms.append(_xform(at + Vector3(0, trunk_h / 2.0, 0), yaw, Vector3(trunk_r, trunk_h, trunk_r)))
	_trunk_colors.append(TRUNK_COLOR)
	var tint := CONIFER_COLOR.lightened(rng.randf_range(-0.03, 0.05))
	_plants.append([at, h, yaw, 0, tint])
	var base_r := h * rng.randf_range(0.12, 0.16)
	# Three cones, each narrower and higher, overlapping into one crown.
	for k in 3:
		var frac := 0.20 + 0.26 * k
		var cone_h := h * 0.40
		var cone_r := base_r * (1.0 - 0.28 * k)
		_cone_xforms.append(_xform(at + Vector3(0, h * frac + cone_h / 2.0, 0), yaw,
			Vector3(cone_r, cone_h, cone_r)))
		_cone_colors.append(tint)


## One tree or plant of a named kind (TreeKit's: "oak", "birch",
## "pine", "shrub", "hydrangea", "hedge"...), h tall, leaf its colour;
## stretch scales a hedge to its length and depth.
func plant_species(at: Vector3, h: float, species: String, leaf: Color, rng: RandomNumberGenerator,
		yaw := -1.0, stretch := Vector3.ONE) -> void:
	_plants.append([at, h, yaw if yaw >= 0.0 else rng.randf_range(0.0, TAU), species, leaf, stretch])


## One spruce where it is wanted.
func plant_conifer(at: Vector3, h: float, rng: RandomNumberGenerator) -> void:
	_conifer(at, h, rng.randf_range(0.0, TAU), rng)


## One broadleaf where it is wanted, in a leaf colour of its own: a
## street tree, a maple turning in a yard.
func plant_broadleaf(at: Vector3, h: float, leaf: Color, rng: RandomNumberGenerator) -> void:
	_broadleaf(at, h, rng.randf_range(0.0, TAU), rng, leaf)


func _broadleaf(at: Vector3, h: float, yaw: float, rng: RandomNumberGenerator,
		leaf: Color = BROADLEAF_COLOR) -> void:
	var trunk_h := h * 0.48
	var trunk_r := h * 0.04
	_trunk_xforms.append(_xform(at + Vector3(0, trunk_h / 2.0, 0), yaw, Vector3(trunk_r, trunk_h, trunk_r)))
	_trunk_colors.append(TRUNK_COLOR)
	var tint := leaf.lightened(rng.randf_range(-0.03, 0.06))
	_plants.append([at, h, yaw, 1, tint])
	var crown_r := h * rng.randf_range(0.17, 0.22)
	# A crown of four lobes: one on top, three around it.
	_ball_xforms.append(_xform(at + Vector3(0, h * 0.72, 0), yaw, Vector3(crown_r, crown_r * 0.9, crown_r)))
	_ball_colors.append(tint)
	for k in 3:
		var a := yaw + TAU / 3.0 * k
		var lobe := crown_r * rng.randf_range(0.6, 0.8)
		_ball_xforms.append(_xform(at + Vector3(cos(a) * crown_r * 0.55, h * 0.60, sin(a) * crown_r * 0.55),
			yaw, Vector3(lobe, lobe * 0.85, lobe)))
		_ball_colors.append(tint.lightened(rng.randf_range(-0.05, 0.05)))


func _xform(at: Vector3, yaw: float, scale: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0, yaw, 0)).scaled(scale), at)


## Build the three MultiMeshes from what the planters gathered. A far
## wood (low_detail) draws its cones and crowns with fewer sides: a
## tree three hundred metres off in the haze is a silhouette.
func finish(cast_shadows: bool, low_detail: bool = false, detailed: bool = false) -> void:
	if detailed:
		_finish_detailed(cast_shadows)
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.7
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 5 if low_detail else 8
	_multimesh(trunk, _trunk_xforms, _trunk_colors, _leaf_material(), cast_shadows)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6 if low_detail else 10
	_multimesh(cone, _cone_xforms, _cone_colors, _leaf_material(), cast_shadows)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 7 if low_detail else 12
	ball.rings = 4 if low_detail else 7
	_multimesh(ball, _ball_xforms, _ball_colors, _leaf_material(), cast_shadows)


## Trees with leaves (TreeKit): each planted tree an instance of a
## spruce or a broadleaf mesh, a variant picked by where it stands, its
## leaf colour its own; a few broadleaves are elms. The dead snags stay
## bare trunks.
func _finish_detailed(cast_shadows: bool) -> void:
	var groups: Dictionary = {}
	for plant: Array in _plants:
		var at: Vector3 = plant[0]
		var variant := absi(int(at.x * 7.0 + at.z * 13.0)) % TreeKit.VARIANTS
		var kind := "spruce"
		var pick := absi(int(at.x * 3.0 - at.z * 5.0)) % 10
		if plant[3] is String:
			kind = plant[3]
		elif int(plant[3]) == 1:
			# The broadleaves: maples mostly, oaks, birches, an elm.
			var kinds: Array[String] = ["maple", "maple", "maple", "maple", "oak", "oak", "birch", "birch", "elm", "maple"]
			kind = kinds[pick]
		elif pick < 2:
			kind = "pine"
		if kind == "elm" or kind == "hedge":
			variant = 0
		# A broadleaf of the wood turns by its kind: maples red to orange
		# to yellow, oaks russet, birches gold, elms a tired yellow.
		if plant[3] is int and int(plant[3]) == 1 and _default_leaf(plant[4]):
			plant[4] = _autumn(kind, pick)
		var key := "%s%d" % [kind, variant]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(plant)
	for key: String in groups:
		var plants: Array = groups[key]
		var kind := key.substr(0, key.length() - 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = TreeKit.mesh(kind, int(key.substr(key.length() - 1)))
		mm.instance_count = plants.size()
		for i in plants.size():
			var plant: Array = plants[i]
			var s := float(plant[1]) / TreeKit.REF_H
			var stretch: Vector3 = plant[5] if plant.size() > 5 else Vector3.ONE
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(plant[2])) * Basis.from_scale(stretch * s), plant[0]))
			mm.set_instance_custom_data(i, plant[4])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Trees_" + key
		inst.multimesh = mm
		# Shrubs and hedges are too low for their shadows to be missed.
		var casts := cast_shadows and not (kind in ["shrub", "hydrangea", "hedge"])
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts 			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if casts:
			inst.add_to_group("foliage_shadows")
		add_child(inst)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.7
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 6
	var snag_colors: Array[Color] = []
	for _x in _snag_xforms:
		snag_colors.append(SNAG_COLOR)
	_multimesh(trunk, _snag_xforms, snag_colors, _leaf_material(), cast_shadows)


## Whether a broadleaf still wears the wood's summer green (planted
## by the scatter, not given a colour of its own).
static func _default_leaf(c: Color) -> bool:
	return absf(c.r - BROADLEAF_COLOR.r) < 0.08 and absf(c.g - BROADLEAF_COLOR.g) < 0.08 and absf(c.b - BROADLEAF_COLOR.b) < 0.08


static func _autumn(kind: String, pick: int) -> Color:
	match kind:
		"oak":
			return [Color(0.48, 0.26, 0.1), Color(0.4, 0.22, 0.08), Color(0.36, 0.3, 0.12)][pick % 3]
		"birch":
			return [Color(0.82, 0.66, 0.15), Color(0.72, 0.6, 0.12)][pick % 2]
		"elm":
			return Color(0.6, 0.55, 0.16)
	return [Color(0.78, 0.2, 0.06), Color(0.8, 0.38, 0.07), Color(0.82, 0.6, 0.12), Color(0.6, 0.12, 0.06), Color(0.3, 0.36, 0.1)][pick % 5]


func _leaf_material() -> StandardMaterial3D:
	var mat := ViewUtil.matte(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	# The tints are picked as screen colours: without this they are
	# read as linear and every canopy comes out mint.
	mat.vertex_color_is_srgb = true
	# Foliage has no gloss: a smooth sphere at a grazing sun otherwise
	# throws a broad white highlight and the tree reads as white.
	mat.roughness = 1.0
	mat.metallic_specular = 0.05
	return mat


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color],
		mat: Material, cast_shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cast_shadows:
		inst.add_to_group("foliage_shadows")  # the graphics option "Tree shadows" switches these
	add_child(inst)
