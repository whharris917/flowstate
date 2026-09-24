class_name RunClearance
extends RefCounted
## The one answer to "may a run pass here?": pipes must not intersect
## or travel through the volume of tanks or other equipment or
## geometry. The router's plain legs and grid search, the lanes' room,
## the risers' slides, the bridges, the square-turn legs, the lane
## cost and the intersection report all ask this and nothing else
## probes for solids. Positions are plant-local.
##
## The rule, in full:
##   1. Solid is world geometry, placed structure and equipment
##      volumes. Other runs are never solid; lanes and bridges see to
##      them.
##   2. A run's own two pieces of equipment (a shell-mounted instrument
##      counts as its vessel) are open to it within `reach` of the
##      fitting on each — the stub clearance plus half the footprint,
##      since a bottom outlet's line runs out from under its vessel —
##      and anywhere along a vertical leg, a drop down its flank.
##      A context may name more records as open: a bridge standing at
##      the crossed run's own fitting.
##   3. A run resting on what carries it — a cable on the floor, a tray
##      on its beam — is not passing through it: a surface just under
##      the run, facing up, does not block.
##   4. The probe is a sphere of the run's radius plus a margin, at the
##      run's own height. What it finds is cached by tenth-metre cell
##      and radius until the plant changes.

const MARGIN := 0.03
const STEP := 0.15          # sample spacing along a leg
const REST := 0.1           # how far under a run a carrying surface may be

var plant: Node3D
var _cells: Dictionary = {}     # key -> {"solid": [[owner, body]...], "runs": [[src, order]...]}
var _owners: Dictionary = {}    # body -> owner
var _shapes: Dictionary = {}    # radius class -> SphereShape3D
var last_block: String = ""     # who blocked last, for the routing debug


func _init(plant_: Node3D) -> void:
	plant = plant_


## The plant changed: everything is worth probing again.
func clear() -> void:
	_cells.clear()
	_owners.clear()


## What a run is, for the questions below: its two records, where its
## fittings are, how far each record is open, its radius, and any
## further records open to it.
func context(own: Array, from: Vector3, to: Vector3, radius: float, open: Array = []) -> Dictionary:
	var names: Array = []
	var ends: Array = []
	var reach: Array[float] = []
	var fittings: Array = [from, to]
	for i in own.size():
		var name_ := str(own[i])
		names.append(name_)
		ends.append(fittings[mini(i, 1)])
		reach.append(own_reach(name_))
		# A shell-mounted instrument's line leaves through its vessel: the
		# vessel is its own too, with the vessel's reach.
		var host := _host_of(name_)
		if host != "":
			names.append(host)
			ends.append(fittings[mini(i, 1)])
			reach.append(own_reach(host))
	return {"own": names, "ends": ends, "reach": reach, "radius": radius, "open": open}


## The vessel a shell-mounted instrument sits on, or "".
func _host_of(name_: String) -> String:
	var view: Node = plant.views.get(name_)
	if view == null or not view.has_meta("mount_frac"):
		return ""
	var host_key: Variant = plant.views.find_key(view.get_parent())
	return str(host_key) if host_key != null else ""


## How far from its fitting a run's own equipment is open to it on a
## level leg.
func own_reach(name_: String) -> float:
	var reach := PipeRoute.STUB_CLEAR
	var tank := plant.sim.get_component(name_) as SimTank
	if tank != null:
		return reach + tank.diameter_m * 0.5
	var footprint: Vector3 = PlantFactory.FOOTPRINTS.get(plant.equip_types.get(name_, ""), Vector3.ZERO)
	return reach + maxf(footprint.x, footprint.z) * 0.5


## ---- the questions --------------------------------------------------------

## The owner blocking a run at p, or null. `vertical` says the run is
## on a vertical leg there, where its own equipment is open to it.
func blocked_by(p: Vector3, ctx: Dictionary, vertical: bool) -> Variant:
	var radius: float = ctx["radius"]
	for entry: Array in owners_at(p, radius)["solid"]:
		var owner: Variant = entry[0]
		if owner is String:
			if (ctx["open"] as Array).has(owner):
				continue
			var own: Array = ctx["own"]
			var index := own.find(owner)
			if index >= 0 and (vertical or p.distance_to((ctx["ends"] as Array)[index]) < float((ctx["reach"] as Array)[index])):
				continue
		if not is_instance_valid(entry[1]):
			continue   # freed since the cell was probed: a fitting rebuilt at a new bore
		if _rests_on(p, entry[1], radius):
			continue
		last_block = str(owner)
		return owner
	return null


## The router's callable: blocked.call(p, own_open), own_open being
## the router's word for "on a vertical, or at a fitting".
func router_blocked(p: Vector3, own_open: bool, ctx: Dictionary) -> bool:
	return blocked_by(p, ctx, own_open) != null


## Every place a path passes through something, sampled every STEP,
## one entry per owner: [{owner, at, seg}]. Empty means clear.
func hits(path: Array, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var length := a.distance_to(b)
		if length < 0.005:
			continue
		var vertical := absf(b.y - a.y) > maxf(absf(b.x - a.x), absf(b.z - a.z))
		var steps := maxi(1, ceili(length / STEP))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / steps)
			var owner: Variant = blocked_by(p, ctx, vertical)
			if owner == null:
				continue
			var key := str(owner)
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"owner": owner, "at": p, "seg": i})
	return out


## Is one straight clear? The lanes' room, a riser's slide, a bridge's
## deck and ramps, a square-turn leg.
func leg_clear(a: Vector3, b: Vector3, ctx: Dictionary) -> bool:
	return hits([a, b], ctx).is_empty()


## Does a run from some other source, laid before `order`, already pass
## here? Runs from the same record are bundle-mates: they detour
## together and the lanes part them.
func busy(p: Vector3, own_sources: Array, order: int) -> bool:
	for entry: Array in owners_at(p, 0.07)["runs"]:
		if int(entry[1]) < order and not own_sources.has(entry[0]):
			return true
	return false


## ---- the geometry ---------------------------------------------------------

## What the probe finds at p: solids as [owner, body], and the runs
## laid where their waypoints put them (a searched run is itself
## steering, and two steering round each other never settle).
func owners_at(p: Vector3, radius: float) -> Dictionary:
	var key := Vector4i(roundi(p.x * 10.0), roundi(p.y * 10.0), roundi(p.z * 10.0), roundi(radius * 100.0))
	if _cells.has(key):
		return _cells[key]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape(radius)
	query.transform = Transform3D(Basis(), plant.to_global(p))
	query.collision_mask = 1 | 4 | 8
	var solid: Array = []
	var runs_here: Array = []
	for found: Dictionary in plant.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var collider: Object = found["collider"]
		if not (collider is Node):
			continue
		var body := collider as Node
		if body.has_meta("handle") or body.has_meta("port_name"):
			continue
		if body.has_meta("run"):
			var run_view: Variant = body.get_meta("run")
			if run_view is PipeView and (run_view as PipeView).style() == "cable":
				continue   # a loose cable on the floor is in nobody's way
			if run_view is Node and bool(run_view.get_meta("searched", false)):
				continue
			runs_here.append([str(run_view.get_meta("src", "")) if run_view is Node else "",
				int(run_view.get_meta("order", -1)) if run_view is Node else -1])
			continue
		solid.append([owner_of(body), body])
	var cell := {"solid": solid, "runs": runs_here}
	_cells[key] = cell
	return cell


func _shape(radius: float) -> SphereShape3D:
	var key := roundi(radius * 100.0)
	if not _shapes.has(key):
		var shape := SphereShape3D.new()
		shape.radius = radius + MARGIN
		_shapes[key] = shape
	return _shapes[key]


## A surface just under the run, facing up, carries it. For a placed
## thing — structure, equipment — it must be that thing's own surface,
## or a structure whose top is flush with it (the next floor slab over,
## at a joint); for world geometry any carrying surface will do, since
## the floor and the slab on it are coplanar bodies and a run rests on
## both.
func _rests_on(p: Vector3, body: Object, radius: float) -> bool:
	var from := plant.to_global(p)
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * (radius + REST), 1 | 4)
	var hit := plant.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y <= 0.7:
		return false
	if hit["collider"] == body:
		return true
	if body is StructureView:
		return absf(_top_of(body as StructureView) - (hit["position"] as Vector3).y) < 0.01
	return not (owner_of(body as Node) is String)


## The height of a structure's highest collision box, world-space.
func _top_of(body: StructureView) -> float:
	var top := -INF
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			continue
		top = maxf(top, shape.global_position.y + (shape.shape as BoxShape3D).size.y / 2.0)
	return top


## The record a collider belongs to — its view may be tagged on the
## body or be an ancestor, a shell-mounted instrument counting as its
## vessel — or "structure:<name>" for placed structure, or the body
## itself for world geometry.
func owner_of(body: Node) -> Variant:
	if _owners.has(body):
		return _owners[body]
	var owner: Variant = body
	var node: Node = body.get_meta("view") if body.has_meta("view") else body
	while node != null and node != plant:
		var found_key: Variant = plant.views.find_key(node)
		if found_key != null and not node.has_meta("mount_frac"):
			owner = found_key
			break
		for structure_name: String in plant.structures:
			if plant.structures[structure_name]["node"] == node:
				owner = "structure:" + structure_name
				break
		if owner is String:
			break
		node = node.get_parent()
	_owners[body] = owner
	return owner
