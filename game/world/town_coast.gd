class_name TownCoast
extends MaineCoast
## The Maine coast with a harbour town on it: the same headland, cove,
## light and river, the graded site become the town's streets and lots,
## and a road cut down the slope to a waterfront at the head of the
## cove, where the wharf runs out into the harbour. HarborTown builds
## the buildings, Harbor the boats; this answers the ground.
##
## The town's plan lives here, since the ground, the trees and the
## rocks all need it: the streets as centre lines with a width, the
## harbour road's ramp and the waterfront apron as graded shapes.

const MAIN_Z := 12.0
const HARBOR_X := -14.0
const ELM_Z := -24.0
const WATER_Z := 44.0
# The harbour road leaves the site's south edge and runs down the slope
# to the waterfront apron at the head of the cove, 4.4 m under the
# town and a metre over high water.
const RAMP_TOP := Vector3(-14.0, 0.0, 60.0)
const RAMP_FOOT := Vector3(-42.0, -4.4, 78.0)
const RAMP_HALF := 3.8
const APRON := Vector2(-31.0, 79.0)
const APRON_HALF := Vector2(18.0, 4.5)
const APRON_Y := -4.4
# The wharf: from the apron's edge out into the cove to a T-head.
const WHARF_X := -30.0
const WHARF_FROM := 83.5
const WHARF_TO := 116.0
const HEAD_Z := Vector2(112.0, 120.0)
const HEAD_X := Vector2(-42.0, -18.0)
const DECK_Y := -3.9
const BUOY := Vector2(-5.0, 205.0)

# Streets: [points, width, centre line, kind]. The country roads run
# out of town into the woods, west and north, on the ground as it lies.
const STREETS: Array = [
	[[Vector2(-45.0, MAIN_Z), Vector2(75.0, MAIN_Z)], 9.0, true],
	[[Vector2(HARBOR_X, -40.0), Vector2(HARBOR_X, 60.0)], 9.0, true],
	[[Vector2(HARBOR_X, ELM_Z), Vector2(70.0, ELM_Z)], 7.0, false],
	[[Vector2(HARBOR_X, WATER_Z), Vector2(70.0, WATER_Z)], 7.0, false],
	[[Vector2(-45.0, MAIN_Z), Vector2(-75.0, 10.0), Vector2(-110.0, 0.0), Vector2(-150.0, -24.0),
		Vector2(-190.0, -60.0), Vector2(-235.0, -112.0), Vector2(-270.0, -170.0)], 6.5, true],
	[[Vector2(HARBOR_X, -40.0), Vector2(-16.0, -80.0), Vector2(-25.0, -128.0), Vector2(-44.0, -185.0),
		Vector2(-70.0, -240.0)], 6.5, true],
]


var beam_mat: ShaderMaterial


func _init() -> void:
	super()
	# The woods round the town are trees with leaves, and thicker.
	detailed_trees = true
	near_spacing = 4.6


## No starship over this coast.
func _build_heighliner() -> void:
	pass


## The light station as on the coast, and the lighthouse's beam made
## visible: a long cone turning with the lamp, as much of it seen as the
## air holds rain and fog and the night is dark (the weather sets it).
func _build_landmarks() -> void:
	super()
	var cone := CylinderMesh.new()
	cone.top_radius = 16.0
	cone.bottom_radius = 0.5
	cone.height = 300.0
	cone.radial_segments = 16
	cone.rings = 6
	cone.cap_top = false
	cone.cap_bottom = false
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = load("res://world/beam.gdshader")
	beam_mat.set_shader_parameter("beam_length", 300.0)
	beam_mat.render_priority = 1
	var shaft := MeshInstance3D.new()
	shaft.name = "BeamShaft"
	shaft.mesh = cone
	shaft.material_override = beam_mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0, -150.0))
	_beam.add_child(shaft)


## The ground: the coast's, with the harbour road's ramp laid in it
## and the waterfront apron graded flat.
func height_at(x: float, z: float) -> float:
	var h := super.height_at(x, z)
	var ramp := _ramp_at(x, z)
	if ramp.y > 0.0:
		h = lerpf(h, ramp.x, ramp.y)
	var w := _apron_weight(x, z)
	if w > 0.0:
		h = lerpf(h, APRON_Y, w)
	return h


## The ramp's height at (x, z) and how strongly it holds there.
func _ramp_at(x: float, z: float) -> Vector2:
	var a := Vector2(RAMP_TOP.x, RAMP_TOP.z)
	var b := Vector2(RAMP_FOOT.x, RAMP_FOOT.z)
	var ab := b - a
	var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var side := Vector2(x, z).distance_to(a + ab * t)
	var weight := 1.0 - smoothstep(RAMP_HALF + 0.5, RAMP_HALF + 7.0, side)
	# The top of the ramp meets the site at grade; past its ends it
	# lets go.
	var past := (Vector2(x, z) - a).dot(ab) / ab.length()
	weight *= smoothstep(-6.0, 0.0, past) * (1.0 - smoothstep(ab.length(), ab.length() + 6.0, past))
	return Vector2(lerpf(RAMP_TOP.y, RAMP_FOOT.y, t), weight)


func _apron_weight(x: float, z: float) -> float:
	var q := Vector2(absf(x - APRON.x), absf(z - APRON.y)) - APRON_HALF
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	return 1.0 - smoothstep(0.0, 5.0, outside)


func graded_at(x: float, z: float) -> float:
	return maxf(super.graded_at(x, z), maxf(_ramp_at(x, z).y, _apron_weight(x, z)))


func is_graded(x: float, z: float) -> bool:
	return super.is_graded(x, z) or _ramp_at(x, z).y > 0.0 or _apron_weight(x, z) > 0.0


## No tree in a street or at its edge, nor on the waterfront.
func tree_ground(x: float, z: float) -> float:
	if street_distance(x, z) < 5.0:
		return -INF
	return super.tree_ground(x, z)


## No boulder on a street, the waterfront, under the wharf or where the
## boats swing at their moorings.
func rock_blocked(x: float, z: float) -> bool:
	if x > -60.0 and x < 10.0 and z > 66.0 and z < 150.0:
		return true
	return street_distance(x, z) < 6.0


## How far (x, z) is from the edge of the nearest street (negative on it).
func street_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for street: Array in STREETS:
		var pts: Array = street[0]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t) - float(street[1]) / 2.0)
	return best
