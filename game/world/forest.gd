class_name Forest
extends Node3D
## A forest around the clearing (director, 2026-09-12: the grass ran
## featurelessly to the horizon; the plant should stand in a large
## clearing with trees in the near distance hiding the horizon from
## ground level). Two rings of procedural trees — conifers of stacked
## cones and broadleaves of clustered spheres on trunks — drawn with
## MultiMeshes so a few thousand cost almost nothing. Deterministic
## from a seed. Art only: no records, no collision, nothing simulated.

const TRUNK_COLOR := Color(0.20, 0.14, 0.09)
const CONIFER_COLOR := Color(0.05, 0.12, 0.05)
const BROADLEAF_COLOR := Color(0.08, 0.17, 0.06)

var _trunk_xforms: Array[Transform3D] = []
var _cone_xforms: Array[Transform3D] = []
var _cone_colors: Array[Color] = []
var _ball_xforms: Array[Transform3D] = []
var _ball_colors: Array[Color] = []


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


func _conifer(at: Vector3, h: float, yaw: float, rng: RandomNumberGenerator) -> void:
	# Proportions of a real spruce: a trunk a thirtieth of the height,
	# a crown about a third as wide as it is tall.
	var trunk_h := h * 0.25
	var trunk_r := h * 0.035
	_trunk_xforms.append(_xform(at + Vector3(0, trunk_h / 2.0, 0), yaw, Vector3(trunk_r, trunk_h, trunk_r)))
	var tint := CONIFER_COLOR.lightened(rng.randf_range(-0.03, 0.05))
	var base_r := h * rng.randf_range(0.12, 0.16)
	# Three cones, each narrower and higher, overlapping into one crown.
	for k in 3:
		var frac := 0.20 + 0.26 * k
		var cone_h := h * 0.40
		var cone_r := base_r * (1.0 - 0.28 * k)
		_cone_xforms.append(_xform(at + Vector3(0, h * frac + cone_h / 2.0, 0), yaw,
			Vector3(cone_r, cone_h, cone_r)))
		_cone_colors.append(tint)


func _broadleaf(at: Vector3, h: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var trunk_h := h * 0.48
	var trunk_r := h * 0.04
	_trunk_xforms.append(_xform(at + Vector3(0, trunk_h / 2.0, 0), yaw, Vector3(trunk_r, trunk_h, trunk_r)))
	var tint := BROADLEAF_COLOR.lightened(rng.randf_range(-0.03, 0.06))
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


## Build the three MultiMeshes from what plant_ring gathered.
func finish(cast_shadows: bool) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.7
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 8
	_multimesh(trunk, _trunk_xforms, [], ViewUtil.matte(TRUNK_COLOR), cast_shadows)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 10
	_multimesh(cone, _cone_xforms, _cone_colors, _leaf_material(), cast_shadows)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 7
	_multimesh(ball, _ball_xforms, _ball_colors, _leaf_material(), cast_shadows)


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
	add_child(inst)
