class_name TownCoast
extends MaineCoast
## The Maine coast with a harbour town on it: the same headland, cove,
## light and river, the graded site become a town on a hillside, and a
## road down to a waterfront at the head of the cove, where the wharf
## runs out into the harbour. HarborTown builds the buildings, Harbor
## the boats; this answers the ground and holds the town's plan.
##
## The ground under the town falls toward the harbour, rises west to the
## woods, and swells into a knoll at the east end of Main Street where
## the church stands, with a gentle roll through it all. The streets are
## centre lines drawn through control points: Main Street straight and
## climbing, Harbor Street bending down to the water, Elm and Water
## Streets curving along the hill, Water Street following the shore.
## Lots are laid along them, each turned to face its street, and every
## lot and building stands on a terrace graded flat at the height of
## its street front, so the houses step down the hill.
##
## The plan is made before the ground (in _init), since the ground,
## the trees and the rocks all need it.

const MAIN_Z := 12.0
const HARBOR_X := -14.0      # where Harbor Street crosses Main Street
# The harbour road: from the foot of Harbor Street down to the waterfront
# apron at the head of the cove, a metre over high water.
const RAMP_TOP := Vector3(-27.0, 0.0, 60.0)
const RAMP_FOOT := Vector3(-31.0, -4.4, 76.0)
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

# The streets: [name, control points, width, centre line, lift]. The
# country roads run out of town into the woods, west and north.
const STREET_PLAN: Array = [
	["main", [Vector2(-45.0, MAIN_Z), Vector2(75.0, MAIN_Z)], 9.0, true, 0.035],
	["harbor", [Vector2(-14.0, -40.0), Vector2(-13.0, -22.0), Vector2(-13.5, -4.0), Vector2(HARBOR_X, MAIN_Z),
		Vector2(-15.5, 28.0), Vector2(-19.0, 42.0), Vector2(-23.5, 53.0), Vector2(RAMP_TOP.x, RAMP_TOP.z)], 9.0, true, 0.03],
	["elm", [Vector2(-14.0, -24.0), Vector2(4.0, -27.0), Vector2(24.0, -26.0), Vector2(44.0, -22.5),
		Vector2(60.0, -21.0), Vector2(73.0, -24.0)], 7.0, false, 0.02],
	["water", [Vector2(-19.0, 42.0), Vector2(0.0, 45.5), Vector2(20.0, 47.5), Vector2(40.0, 46.5),
		Vector2(58.0, 46.5), Vector2(74.0, 42.0)], 7.0, false, 0.02],
	["west", [Vector2(-45.0, MAIN_Z), Vector2(-75.0, 10.0), Vector2(-110.0, 0.0), Vector2(-150.0, -24.0),
		Vector2(-190.0, -60.0), Vector2(-235.0, -112.0), Vector2(-270.0, -170.0)], 6.5, true, 0.05],
	["north", [Vector2(-14.0, -40.0), Vector2(-16.0, -80.0), Vector2(-25.0, -128.0), Vector2(-44.0, -185.0),
		Vector2(-70.0, -240.0)], 6.5, true, 0.05],
]
# Where the town's larger buildings stand, as ground rects [x0, z0, x1, z1]
# and the point whose ground height their terrace takes.
const BUILDINGS: Array = [
	[Vector2(-7.0, -9.5), Vector2(-2.0, 7.5)], [Vector2(3.0, -9.5), Vector2(12.0, 7.5)],
	[Vector2(12.0, -9.5), Vector2(25.0, 7.5)], [Vector2(25.0, -9.5), Vector2(34.0, 7.5)],
	[Vector2(34.0, -9.5), Vector2(45.0, 7.5)], [Vector2(45.0, -9.5), Vector2(52.5, 7.5)],
	[Vector2(-6.5, 16.5), Vector2(10.5, 27.0)], [Vector2(15.5, 16.5), Vector2(28.5, 29.5)],
	[Vector2(31.5, 16.5), Vector2(42.5, 29.5)], [Vector2(54.0, 16.5), Vector2(66.5, 42.0)],
]

var beam_mat: ShaderMaterial
## The streets as dense centre lines: {name, pts, width, line, lift, lo, hi (bounds)}.
var streets: Array[Dictionary] = []
## The residential lots: {front (Vector2), face (unit Vector2 toward the
## street), yaw, street, side, depth (room behind the front), row}.
var lots: Array[Dictionary] = []
## Graded terraces: {c, along (unit), half (along, across), y}.
var pads: Array[Dictionary] = []
var ramp_top_y := 0.0
# The terraces packed flat for the ground's hot loop, seven numbers
# each: centre x, z, across x, z, half along, half across, height.
var _pad_data := PackedFloat32Array()
# Which terraces reach each 10 m cell of the town's ground, so a point
# asks only its neighbours.
const PAD_GRID_LO := Vector2(-60.0, -55.0)
const PAD_GRID_N := Vector2(15, 14)
var _pad_cells: Array = []


func _init() -> void:
	super()
	# The woods round the town are trees with leaves, and thicker.
	detailed_trees = true
	near_spacing = 4.6
	_plan_streets()
	_plan_lots()
	_plan_pads()
	ramp_top_y = relief(RAMP_TOP.x, RAMP_TOP.z)


## ---- the plan ------------------------------------------------------------------

## The ground the town was built on before anyone graded it: falling to
## the harbour, rising west, a knoll at the east end, a roll through it.
static func relief(x: float, z: float) -> float:
	var r := -0.07 * (z - MAIN_Z)
	r += 1.8 * (1.0 - smoothstep(-45.0, -12.0, x))
	r += 2.6 * smoothstep(38.0, 66.0, x) * (1.0 - smoothstep(22.0, 50.0, z))
	r += 0.6 * sin(x * 0.07 + 0.5) * cos(z * 0.05)
	return r


## Every street drawn through its control points as a smooth curve,
## sampled every two metres.
func _plan_streets() -> void:
	for plan: Array in STREET_PLAN:
		var ctrl: Array = plan[1]
		var pts := PackedVector2Array()
		for i in ctrl.size() - 1:
			var p0: Vector2 = ctrl[maxi(i - 1, 0)]
			var p1: Vector2 = ctrl[i]
			var p2: Vector2 = ctrl[i + 1]
			var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
			var n := maxi(int(p1.distance_to(p2) / 2.0), 1)
			for j in n:
				var t := float(j) / n
				var t2 := t * t
				var t3 := t2 * t
				pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
		pts.append(ctrl[ctrl.size() - 1])
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		# A coarser copy, every eight metres, for measuring distances:
		# asked of every tree and rock, it must be quick.
		var coarse := PackedVector2Array()
		for k in range(0, pts.size(), 4):
			coarse.append(pts[k])
		if coarse[coarse.size() - 1] != pts[pts.size() - 1]:
			coarse.append(pts[pts.size() - 1])
		streets.append({"name": plan[0], "pts": pts, "coarse": coarse, "width": plan[2], "line": plan[3], "lift": plan[4], "lo": lo, "hi": hi})


func street(name_: String) -> Dictionary:
	for s in streets:
		if s["name"] == name_:
			return s
	return {}


## The point, the direction and the left-hand normal s metres along a street.
static func along(st: Dictionary, s: float) -> Array:
	var pts: PackedVector2Array = st["pts"]
	var walked := 0.0
	for k in pts.size() - 1:
		var seg := pts[k].distance_to(pts[k + 1])
		if walked + seg >= s or k == pts.size() - 2:
			var t := clampf((s - walked) / maxf(seg, 1e-4), 0.0, 1.0)
			var d := (pts[k + 1] - pts[k]).normalized()
			return [pts[k].lerp(pts[k + 1], t), d, Vector2(-d.y, d.x)]
		walked += seg
	return [pts[pts.size() - 1], Vector2(1, 0), Vector2(0, 1)]


static func length_of(st: Dictionary) -> float:
	var pts: PackedVector2Array = st["pts"]
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	return total


## Lots down both sides of the residential streets, a house to every
## twelve or thirteen metres, each where its house, its front yard and
## a little behind it fit clear of the streets, the town's larger
## buildings and the lots already laid.
func _plan_lots() -> void:
	# [street, side (+1 left of travel), from, to, spacing, setback, row]
	var runs: Array = [
		["water", 1, 6.0, 100.0, 12.6, 4.0, "harbour"],
		["water", -1, 6.0, 100.0, 12.6, 3.0, "water_north"],
		["main", 1, 4.0, 26.0, 11.5, 3.5, "main_west"],
		["main", -1, 4.0, 26.0, 11.5, 3.5, "main_west"],
		["harbor", 1, 4.0, 110.0, 12.5, 4.0, "harbor_west"],
		["harbor", -1, 4.0, 110.0, 12.5, 4.0, "harbor_east"],
		["elm", 1, 12.0, 95.0, 13.0, 3.0, "elm_south"],
		["elm", -1, 12.0, 95.0, 13.0, 3.5, "elm_north"],
	]
	for run: Array in runs:
		var st := street(run[0])
		var side: int = run[1]
		var s: float = run[2]
		var end := minf(float(run[3]), length_of(st) - 4.0)
		while s <= end:
			var a := along(st, s)
			var c: Vector2 = a[0]
			var n: Vector2 = a[2]
			var front := c + n * side * (float(st["width"]) / 2.0 + float(run[5]))
			var face := -n * side
			var depth := _room_behind(front, face, run[0])
			if depth >= 6.5 and not _near_lot(front):
				lots.append({"front": front, "face": face, "yaw": atan2(face.x, face.y), "street": run[0],
					"side": side, "depth": depth, "row": run[6], "setback": run[5]})
				s += float(run[4])
			else:
				s += 1.5


## How deep a house may stand behind a front (up to 11 m): the ground
## behind it clear of streets, buildings and the site's edge.
func _room_behind(front: Vector2, face: Vector2, own: String) -> float:
	var along_ := Vector2(face.y, -face.x)
	var harbour := front.y > 48.0
	var depth := 0.0
	while depth < 11.0:
		var ok := true
		for f: float in [-5.6, 0.0, 5.6]:
			var p := front + along_ * f - face * (depth + 0.5)
			if street_distance(p.x, p.y) < 0.6 or not _in_town(p, harbour) or _in_building(p):
				ok = false
		# The front yard too: from the house to the road's edge.
		if depth == 0.0:
			for f: float in [-5.6, 5.6]:
				var p := front + along_ * f + face * 1.5
				if _in_building(p) or not _in_town(p, harbour) or street_distance(p.x, p.y, own) < 0.3:
					ok = false
		if not ok:
			break
		depth += 0.5
	return depth


func _in_town(p: Vector2, harbour: bool) -> bool:
	return p.x > -45.0 and p.x < 75.0 and p.y > -40.0 and p.y < (70.0 if harbour else 60.0)


func _in_building(p: Vector2) -> bool:
	for b: Array in BUILDINGS:
		var lo: Vector2 = b[0]
		var hi: Vector2 = b[1]
		if p.x > lo.x - 1.0 and p.x < hi.x + 1.0 and p.y > lo.y - 1.0 and p.y < hi.y + 1.0:
			return true
	return false


func _near_lot(front: Vector2) -> bool:
	for lot in lots:
		if (lot["front"] as Vector2).distance_to(front) < 11.8:
			return true
	# A house's body behind another's front yard, across a corner.
	for lot in lots:
		var body: Vector2 = (lot["front"] as Vector2) - (lot["face"] as Vector2) * 5.0
		if body.distance_to(front) < 8.0:
			return true
	return false


## The terraces: every lot graded flat from its road edge to a little
## behind its house, and every larger building's plot, each at the
## height of the ground at its street front.
func _plan_pads() -> void:
	for lot in lots:
		var front: Vector2 = lot["front"]
		var face: Vector2 = lot["face"]
		var setback: float = lot["setback"]
		var back := minf(float(lot["depth"]), 11.0) + 2.0
		var c := front + face * (setback - (setback + back) / 2.0)
		pads.append({"c": c, "across": face, "half": Vector2(6.2, (setback + back) / 2.0), "y": relief(front.x, front.y)})
	for b: Array in BUILDINGS:
		var lo: Vector2 = b[0]
		var hi: Vector2 = b[1]
		var front := Vector2((lo.x + hi.x) / 2.0, hi.y if hi.y < MAIN_Z else lo.y)
		pads.append({"c": (lo + hi) / 2.0, "across": Vector2(0, 1), "half": (hi - lo) / 2.0, "y": relief(front.x, front.y)})
	for pad in pads:
		var c: Vector2 = pad["c"]
		var across: Vector2 = pad["across"]
		var half: Vector2 = pad["half"]
		_pad_data.append_array(PackedFloat32Array([c.x, c.y, across.x, across.y, half.x, half.y, float(pad["y"])]))
	_pad_cells.resize(PAD_GRID_N.x * PAD_GRID_N.y)
	for k in _pad_cells.size():
		_pad_cells[k] = PackedInt32Array()
	for i in pads.size():
		var c: Vector2 = pads[i]["c"]
		var half: Vector2 = pads[i]["half"]
		var reach := half.x + half.y + 3.0
		for gx in PAD_GRID_N.x:
			for gz in PAD_GRID_N.y:
				var lo := PAD_GRID_LO + Vector2(gx, gz) * 10.0
				if c.x + reach < lo.x or c.x - reach > lo.x + 10.0 or c.y + reach < lo.y or c.y - reach > lo.y + 10.0:
					continue
				var cell: PackedInt32Array = _pad_cells[gz * PAD_GRID_N.x + gx]
				cell.append(i * 7)
				_pad_cells[gz * PAD_GRID_N.x + gx] = cell


## How strongly a terrace holds (x, z), and at what height.
func _pad_at(x: float, z: float) -> Vector2:
	var best_y := 0.0
	var best_w := 0.0
	var gx := int((x - PAD_GRID_LO.x) / 10.0)
	var gz := int((z - PAD_GRID_LO.y) / 10.0)
	if x < PAD_GRID_LO.x or z < PAD_GRID_LO.y or gx >= PAD_GRID_N.x or gz >= PAD_GRID_N.y:
		return Vector2.ZERO
	var d := _pad_data
	var cell: PackedInt32Array = _pad_cells[gz * PAD_GRID_N.x + gx]
	for i in cell:
		var dx := x - d[i]
		var dz := z - d[i + 1]
		var reach := d[i + 4] + d[i + 5] + 3.0
		if absf(dx) > reach or absf(dz) > reach:
			continue
		var qa := absf(dx * d[i + 3] - dz * d[i + 2]) - d[i + 4]
		var qc := absf(dx * d[i + 2] + dz * d[i + 3]) - d[i + 5]
		var outside := Vector2(maxf(qa, 0.0), maxf(qc, 0.0)).length() + minf(maxf(qa, qc), 0.0)
		if outside >= 3.0:
			continue
		var w := 1.0 - smoothstep(0.0, 3.0, outside)
		if w > best_w:
			best_w = w
			best_y = d[i + 6]
	return Vector2(best_y, best_w)


## ---- the landmarks -------------------------------------------------------------

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


## ---- the ground ----------------------------------------------------------------

## The ground: the coast's, the town's hillside on its site, each
## terrace graded flat, the harbour road's ramp laid in it and the
## waterfront apron graded flat.
func height_at(x: float, z: float) -> float:
	var h := super.height_at(x, z)
	var site := _flat_weight(x, z, _flats[0])
	if site > 0.0:
		h += relief(x, z) * site
		var pad := _pad_at(x, z)
		if pad.y > 0.0:
			h = lerpf(h, pad.x, pad.y * site)
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
	var past := (Vector2(x, z) - a).dot(ab) / ab.length()
	weight *= smoothstep(-6.0, 0.0, past) * (1.0 - smoothstep(ab.length(), ab.length() + 6.0, past))
	return Vector2(lerpf(ramp_top_y, RAMP_FOOT.y, t), weight)


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


## How far (x, z) is from the edge of the nearest street (negative on
## it); except names a street to leave out.
func street_distance(x: float, z: float, except := "") -> float:
	var p := Vector2(x, z)
	var best := INF
	for st in streets:
		if st["name"] == except:
			continue
		var lo: Vector2 = st["lo"]
		var hi: Vector2 = st["hi"]
		var reach := float(st["width"]) / 2.0 + minf(best, 30.0)
		if p.x < lo.x - reach or p.x > hi.x + reach or p.y < lo.y - reach or p.y > hi.y + reach:
			continue
		var pts: PackedVector2Array = st["coarse"]
		var half := float(st["width"]) / 2.0
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t) - half)
	return best
