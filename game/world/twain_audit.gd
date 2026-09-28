extends Node
## The Mark Twain house's audit: builds the world, then checks the model
## against itself and prints every defect it finds with where it is, so
## the model can be corrected by a loop of audit, fix, audit.
##
## The drawn geometry (the meshes as built, not the player's solids) is
## turned into collision on layers of its own so it can be probed: walls,
## floors and roofs (the building), the furniture, and a box for each
## piece of furniture as recorded by the builder. Checks:
##   leak       a room's shell has a hole: a ray from inside reaches the
##              sky without passing a window's glass or an outside door
##   roof       from above, a ray reaches a room's interior through the roof
##   poke_out   a room's wall, floor, ceiling or furniture shows outside
##              the house or through its roof
##   poke_in    the outside (roof, eave, wall dressing) shows inside a room
##   clash      furniture runs into a wall, door, stair or fixture
##   overlap    two pieces of furniture run into each other
##   float      furniture that stands off the floor, sinks into it, or
##              stands off the wall it backs onto; a rug not on its floor;
##              a lamp that does not hang from its ceiling or hangs too low
##   door       a doorway the player cannot pass
##   reach      a room or part of one the player cannot walk to from the
##              front door
##   fight      two surfaces of different colour in the same plane (they
##              flicker)
## and the building's own sense (the rules any real house keeps, checked
## on what was built, not on what the code meant):
##   orphan     an opening in the list that no wall carries, or that two
##              walls carry
##   blind      an opening's frame on solid wall: no hole behind the sash
##   nowhere    a window or door with no room behind it (roof, void or
##              solid on the inside)
##   landing    a door with no floor on one side of its sill
##   rail       a railing with no floor under it
##   faces      an opening that looks straight into a wall or roof
##   straddle   a window or door across the partition between two rooms
## Run headless for the report, windowed for a picture of each finding:
##   godot --headless --path game res://world/twain_audit.tscn
##   godot --path game res://world/twain_audit.tscn
## The report is printed and written to user://twain_audit.json; the
## pictures to user://audit_tw_NN.png. FLOWSTATE_TW_AUDIT_ONLY=leak,clash
## limits the checks; FLOWSTATE_TW_AUDIT_SHOTS=n takes up to n pictures.

const L_ARCH := 1 << 19
const L_FURN := 1 << 20
const L_ITEM := 1 << 21
const L_DRESS := 1 << 22
## The building as seen: its walls and roofs with the openings' dressing.
const L_BUILT := L_ARCH | L_DRESS
const FT := TwainHouse.FT
const CELL := 0.2
## Rooms the walk is not expected to reach, and why.
const NOT_VISITED := {"basement": "no stair down is modelled", "pantry basement": "no stair down is modelled","servants' rooms": "the back stair from the kitchen is not modelled",
	"the office": "its door is kept shut", "south-east bath": "its door is kept shut", "the small room": "its door is kept shut"}

var world: TwainMap
var house: TwainHouse
var space: PhysicsDirectSpaceState3D
var issues: Array[Dictionary] = []
var item_bodies: Array[RID] = []
var only: PackedStringArray = []
var _t0 := 0


func _ready() -> void:
	MouseMode.probe = true
	OS.set_environment("FLOWSTATE_TW_AUDIT", "1")
	var o := OS.get_environment("FLOWSTATE_TW_AUDIT_ONLY")
	if o != "":
		only = o.split(",")
	world = (load("res://world/twain.tscn") as PackedScene).instantiate()
	add_child(world)
	_run()


func _want(check: String) -> bool:
	return only.is_empty() or only.has(check) or (check == "arch" and (only.has("blind") or only.has("rail")
		or only.has("nowhere") or only.has("landing") or only.has("orphan") or only.has("faces") or only.has("straddle")))


func _run() -> void:
	for i in 3:
		await get_tree().physics_frame
	house = world.house
	_bodies()
	for i in 3:
		await get_tree().physics_frame
	space = world.get_world_3d().direct_space_state
	for check: String in ["arch", "leak", "roof", "poke", "clash", "overlap", "float", "door", "reach", "fight"]:
		if not _want(check) and not (check == "poke" and (_want("poke_out") or _want("poke_in"))):
			continue
		_t0 = Time.get_ticks_msec()
		var before := issues.size()
		match check:
			"arch": _architecture()
			"leak": _leaks()
			"roof": _roof()
			"poke": _pokes()
			"clash": _clashes()
			"overlap": _overlaps()
			"float": _support()
			"door": _doors()
			"reach": _reach()
			"fight": _fights()
		print("[audit] %s: %d findings (%d ms)" % [check, issues.size() - before, Time.get_ticks_msec() - _t0])
	_report()
	var shots := int(OS.get_environment("FLOWSTATE_TW_AUDIT_SHOTS")) if OS.get_environment("FLOWSTATE_TW_AUDIT_SHOTS") != "" else 40
	if DisplayServer.get_name() != "headless" and shots > 0:
		await _pictures(shots)
	get_tree().quit()


## ---- the probe geometry ----------------------------------------------------

func _bodies() -> void:
	for group: String in ["outer", "inner", "furniture", "dress"]:
		var tm: TownMesh = house.meshes[group]
		for key: String in tm._surfaces:
			if key == "lamp" or key == "flame":
				continue
			var sf: TownMesh.Surface = tm._surfaces[key]
			var faces := PackedVector3Array()
			faces.resize(sf.i.size())
			for j in sf.i.size():
				faces[j] = sf.v[sf.i[j]]
			if faces.is_empty():
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(faces)
			var body := StaticBody3D.new()
			body.collision_layer = L_FURN if group == "furniture" else (L_DRESS if group == "dress" else L_ARCH)
			body.collision_mask = 0
			body.set_meta("group", group)
			body.set_meta("key", key)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			add_child(body)
	for i in house.items.size():
		var it: Dictionary = house.items[i]
		var body := StaticBody3D.new()
		body.collision_layer = L_ITEM
		body.collision_mask = 0
		body.transform = it["xf"]
		body.set_meta("item", i)
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = (it["size"] as Vector3).max(Vector3(0.02, 0.02, 0.02))
		cs.shape = b
		body.add_child(cs)
		add_child(body)
		item_bodies.append(body.get_rid())


## ---- helpers ---------------------------------------------------------------

func ray(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.hit_back_faces = true
	return space.intersect_ray(q)


## A world point in the survey's feet (x north, z east, y over the first floor).
static func survey(p: Vector3) -> Vector3:
	return Vector3(TwainHouse.OX - p.z / FT, TwainHouse.OZ + p.x / FT, (p.y - TwainHouse.FL) / FT)


static func where(p: Vector3) -> String:
	var s := survey(p)
	return "(%.1f, %.1f) ft, %.1f ft up" % [s.x, s.y, s.z]


## The top of a room at a plan point, in world metres.
func room_top(r: Dictionary, q: Vector2) -> float:
	var y1 := float(r["y1"])
	if y1 != TwainInterior.TO_ROOF:
		# The roof's underside is the ceiling where it comes lower.
		var roof := house.roof_y(q)
		return TwainHouse.h(minf(y1, roof) if roof > -100.0 else y1)
	return TwainHouse.h(minf(house.roof_y(q), TwainInterior.ATTIC))


## The room a world point stands in, or {}.
func room_at(p: Vector3, inset := 0.0) -> Dictionary:
	var s := survey(p)
	var q := Vector2(s.x, s.y)
	for r: Dictionary in house.rooms:
		var poly := r["poly"] as PackedVector2Array
		if not Geometry2D.is_point_in_polygon(q, poly):
			continue
		if inset > 0.0 and _edge_distance(q, poly) * FT < inset:
			continue
		if p.y >= TwainHouse.h(float(r["y0"])) - 0.05 and p.y <= room_top(r, q) + 0.05:
			return r
	return {}


static func _edge_distance(q: Vector2, poly: PackedVector2Array) -> float:
	var best := 1e9
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


func room_name(p: Vector3) -> String:
	var r := room_at(p)
	return str(r.get("name", "outside the rooms"))


## A finding: its check, what is wrong, where; and a camera for its picture
## (eye, target), or none.
func issue(check: String, text: String, at: Vector3, eye := Vector3.INF, count := 1) -> void:
	issues.append({"check": check, "text": text, "at": at, "where": where(at), "room": room_name(at), "eye": eye, "count": count})


## Findings merged by cell: {cell key: [first point, count, extra]}.
static func cell_key(p: Vector3, size := 0.6) -> Vector3i:
	return Vector3i(floori(p.x / size), floori(p.y / size), floori(p.z / size))


## A camera for a finding inside a room: at eye height, 1.5 to 3.5 m from
## p, where the player could stand, with nothing between it and p; the
## best of sixteen bearings.
func eye_toward(p: Vector3, r: Dictionary) -> Vector3:
	if r.is_empty():
		return Vector3.INF
	var floor_y := TwainHouse.h(float(r["y0"]))
	var best := Vector3.INF
	var best_score := -1e9
	for i in 16:
		var a := TAU * i / 16.0
		for dist: float in [3.0, 2.2, 1.5]:
			var e := Vector3(p.x + cos(a) * dist, floor_y + 1.6, p.z + sin(a) * dist)
			if room_at(Vector3(e.x, floor_y + 0.5, e.z), 0.4).get("name", "") != r["name"]:
				continue
			if not _capsule_clear(Vector3(e.x, floor_y + 1.05, e.z), 0.3, 1.5):
				continue
			var hit := ray(e, p, L_BUILT | L_FURN)
			var clear := hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.25
			var score := dist + (10.0 if clear else 0.0)
			if score > best_score:
				best_score = score
				best = e
			break
	return best


## Sample points on a room's floor plan, inset from its walls (world).
func room_samples(r: Dictionary, step: float, inset: float) -> Array[Vector3]:
	var poly := r["poly"] as PackedVector2Array
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for q: Vector2 in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var out: Array[Vector3] = []
	var s := step / FT
	var x := lo.x + s / 2.0
	while x < hi.x:
		var z := lo.y + s / 2.0
		while z < hi.y:
			var q := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(q, poly) and _edge_distance(q, poly) * FT >= inset:
				out.append(TwainHouse.w(x, z, float(r["y0"])))
			z += s
		x += s
	return out


## ---- arch: the building's own sense ---------------------------------------

const OUTSIDE_KINDS := ["win", "door", "french", "open", "shut"]
const DOOR_KINDS := ["door", "french", "open", "shut"]


func _architecture() -> void:
	var t := TwainHouse.T * FT
	# Every opening carried by exactly one wall.
	var seen := {}
	for d: Dictionary in house.dressed:
		seen[int(d["id"])] = int(seen.get(int(d["id"]), 0)) + 1
	for o: Dictionary in house.ops:
		if not OUTSIDE_KINDS.has(str(o["kind"])):
			continue
		var count := int(seen.get(int(o["id"]), 0))
		if count != 1:
			var q := o["at"] as Vector2
			var p := TwainHouse.w(q.x, q.y, (float(o["sill"]) + float(o["head"])) / 2.0)
			issue("orphan", "the %s is carried by %d walls" % [str(o["kind"]), count], p)
	for d: Dictionary in house.dressed:
		var kind := str(d["kind"])
		var c := d["c"] as Vector3
		var n := d["n"] as Vector3
		var side := Vector3(n.z, 0, -n.x).normalized()
		var wd := float(d["w"])
		var y0 := float(d["y0"])
		var yt := float(d["yt"])
		var mid := Vector3(c.x, (y0 + yt) / 2.0, c.z)
		var eye := mid + n * 3.0 + Vector3(0, 0.3, 0)
		# A hole behind the dressing: rays through a grid over the opening,
		# looking only at the walls and rooms.
		var blocked := 0
		var blocker := ""
		for i in 3:
			for j in 3:
				var off := side * wd * (i - 1) * 0.28 + Vector3(0, lerpf(y0, yt, 0.22 + 0.28 * j) - mid.y, 0)
				var hit := ray(mid + off + n * 0.3, mid + off - n * (t + 0.25), L_ARCH)
				if not hit.is_empty():
					blocked += 1
					var body := hit["collider"] as Node
					blocker = "%s %s %.2f m in, at %s" % [str(body.get_meta("group")), str(body.get_meta("key")),
						0.3 - (hit["position"] as Vector3 - (mid + off)).dot(n), where(hit["position"] as Vector3)]
		if blocked >= 6:
			issue("blind", "the %s's frame is on solid wall (%d of 9 rays stopped; %s)" % [kind, blocked, blocker], mid, eye)
			continue
		# Open air in front of it.
		var front := ray(mid + n * 0.05, mid + n * 0.5, L_ARCH)
		if not front.is_empty():
			var body := front["collider"] as Node
			issue("faces", "the %s looks straight into %s %s" % [kind, str(body.get_meta("group")), str(body.get_meta("key"))], mid, eye)
		# One room behind it, not a partition's two.
		var la := room_at(mid - n * (t + 0.45) - side * wd * 0.35)
		var ra := room_at(mid - n * (t + 0.45) + side * wd * 0.35)
		if not la.is_empty() and not ra.is_empty() and la["name"] != ra["name"]:
			issue("straddle", "the %s straddles the wall between %s and %s" % [kind, la["name"], ra["name"]], mid, eye)
		# A room behind it: the space just inside the wall.
		var inside := mid - n * (t + 0.45)
		var low := Vector3(c.x, y0 + 0.3, c.z) - n * (t + 0.45)
		var attic := false
		for dy: float in [0.8, 1.6, 2.4]:
			if not room_at(inside - Vector3(0, dy, 0)).is_empty() and not ray(inside, inside + Vector3(0, 3.0, 0), L_ARCH).is_empty():
				attic = true
		if room_at(inside).is_empty() and room_at(low).is_empty() and not attic:
			var what := "void"
			var up := ray(inside, inside + Vector3(0, 0.6, 0), L_ARCH)
			if not up.is_empty():
				what = "the roof"
			issue("nowhere", "the %s opens onto %s, not a room" % [kind, what], mid, eye)
		# A door's sill has a floor on each side.
		if DOOR_KINDS.has(kind):
			for sd: float in [1.0, -1.0]:
				if sd > 0.0 and y0 < TwainHouse.h(1.0):
					continue    # at the ground: steps and lawn, not in the house
				var foot := Vector3(c.x, y0, c.z) + n * sd * (0.35 + (0.0 if sd > 0.0 else t))
				var hit := ray(foot + Vector3(0, 0.5, 0), foot - Vector3(0, 0.45, 0), L_ARCH)
				var ok := not hit.is_empty() and absf((hit["position"] as Vector3).y - y0) < 0.35 \
					and (hit["normal"] as Vector3).y > 0.7
				if not ok:
					issue("landing", "the %s has no floor %s its sill" % [kind, "outside" if sd > 0.0 else "inside"], foot, eye)
	# Every railing stands on a floor.
	print("[audit] %d railings" % house.rails.size())
	for r: Array in house.rails:
		var a := r[0] as Vector3
		var b := r[1] as Vector3
		var d := (b - a)
		var across := Vector3(d.z, 0, -d.x).normalized()
		var bad := 0
		for k in 3:
			var p := a.lerp(b, (k + 0.5) / 3.0)
			var ok := false
			for sd: float in [1.0, -1.0]:
				var q := p + across * sd * 0.12
				var hit := ray(q + Vector3(0, 0.02, 0), q - Vector3(0, 0.25, 0), L_ARCH)
				if not hit.is_empty() and absf((hit["normal"] as Vector3).y) > 0.9 and (hit["position"] as Vector3).y > q.y - 0.15:
					ok = true
			if not ok:
				bad += 1
		if bad >= 2:
			var m := (a + b) / 2.0
			issue("rail", "a railing %.1f m long stands on no floor" % a.distance_to(b), m + Vector3(0, 0.5, 0),
				m + across * 3.0 + Vector3(0, 1.2, 0))


## ---- leak: holes in a room's shell -------------------------------------------

func _through_door(o: Vector3, d: Vector3) -> bool:
	for door: Dictionary in house.doors:
		if not bool(door["outside"]):
			continue
		var n := door["normal"] as Vector3
		var den := d.dot(n)
		if absf(den) < 1e-4:
			continue
		var t := ((door["center"] as Vector3) - o).dot(n) / den
		if t <= 0.0:
			continue
		var p := o + d * t
		var rel := p - (door["center"] as Vector3)
		if absf(rel.dot(door["along"] as Vector3)) < float(door["width"]) / 2.0 and p.y > float(door["y0"]) and p.y < float(door["y1"]):
			return true
	return false


func _leaks() -> void:
	var dirs: Array[Vector3] = []
	for i in 16:
		var a := TAU * i / 16.0
		dirs.append(Vector3(cos(a), 0, sin(a)))
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		dirs.append(Vector3(cos(a), 1.0, sin(a)).normalized())
	dirs.append(Vector3.UP)
	for r: Dictionary in house.rooms:
		var found := {}
		for base: Vector3 in room_samples(r, 0.9, 0.35):
			var o := base + Vector3(0, 1.5, 0)
			var so := survey(o)
			if room_top(r, Vector2(so.x, so.y)) < o.y + 0.3:
				continue
			for d: Vector3 in dirs:
				if not ray(o, o + d * 80.0, L_BUILT).is_empty():
					continue
				if _through_door(o, d):
					continue
				# Where the ray leaves the room: the hole.
				var p := o
				var t := 0.0
				while t < 40.0:
					t += 0.05
					p = o + d * t
					var s := survey(p)
					var q := Vector2(s.x, s.y)
					if not Geometry2D.is_point_in_polygon(q, r["poly"] as PackedVector2Array) or p.y > room_top(r, q):
						break
				var key := cell_key(p, 0.8)
				if not found.has(key):
					found[key] = [p, o, 0]
				found[key][2] += 1
		for key: Vector3i in found:
			var f: Array = found[key]
			issue("leak", "%s: the sky shows through a gap in the %s (%d rays)" % [r["name"], _surface_word(f[0] as Vector3, r), int(f[2])],
				f[0], f[1], int(f[2]))


func _surface_word(p: Vector3, r: Dictionary) -> String:
	var s := survey(p)
	if p.y > room_top(r, Vector2(s.x, s.y)) - 0.1:
		return "ceiling"
	return "wall"


## ---- roof: the interior seen from the sky ---------------------------------------

func _footprints() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = [TwainHouse.perimeter()]
	var wing := PackedVector2Array(TwainHouse.WING_PLAN)
	out.append(wing)
	var pantry := PackedVector2Array()
	for i in 10:
		pantry.append(TwainHouse._arc_point(TwainHouse.PANTRY_C, TwainHouse.PANTRY_R, 180.0 + 90.0 * i / 9.0))
	pantry.append(Vector2(113.0, 22.3))
	pantry.append(Vector2(113.0, TwainHouse.MZ0))
	out.append(pantry)
	var cons := PackedVector2Array([Vector2(TwainHouse.MX0, TwainHouse.MZ0 + 0.2)])
	for i in 13:
		cons.append(TwainHouse._arc_point(TwainHouse.CONS_C, TwainHouse.CONS_R, -90.0 - 180.0 * i / 12.0))
	cons.append(Vector2(TwainHouse.MX0, 55.5))
	out.append(cons)
	return out


func _in_footprint(q: Vector2, grow := 0.0) -> bool:
	for poly: PackedVector2Array in _footprints():
		if Geometry2D.is_point_in_polygon(q, poly):
			return true
		if grow > 0.0 and _edge_distance(q, poly) < grow:
			return true
	return false


func _roof() -> void:
	var found := {}
	var step := 0.5 / FT
	var x := 15.0
	while x < 160.0:
		var z := 15.0
		while z < 100.0:
			var q := Vector2(x, z)
			if _in_footprint(q):
				var top := TwainHouse.w(x, z, 70.0)
				var hit := ray(top, TwainHouse.w(x, z, -3.0), L_BUILT)
				var bad := ""
				if hit.is_empty():
					bad = "nothing at all"
				elif str((hit["collider"] as Node).get_meta("group")) == "inner":
					bad = "a room's %s" % str((hit["collider"] as Node).get_meta("key"))
				if bad != "":
					var p: Vector3 = hit["position"] if not hit.is_empty() else TwainHouse.w(x, z, 0.0)
					var key := cell_key(p, 1.0)
					if not found.has(key):
						found[key] = [p, bad, 0]
					found[key][2] += 1
			z += step
		x += step
	for key: Vector3i in found:
		var f: Array = found[key]
		var p := f[0] as Vector3
		issue("roof", "from the sky the roof shows %s" % f[1], p, p + Vector3(4, 10, 4), int(f[2]))


## ---- poke: inside showing out, outside showing in ---------------------------------

## Points over a surface: its corners, its middle, and a grid over a large one.
static func _samples(a: Vector3, b: Vector3, c: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = [(a + b + c) / 3.0, (a + b) / 2.0, (b + c) / 2.0, (c + a) / 2.0]
	var edge := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
	var n := int(edge / 0.4)
	if n >= 2:
		for i in n + 1:
			for j in n + 1 - i:
				var u := float(i) / n
				var v := float(j) / n
				out.append(a + (b - a) * u + (c - a) * v)
	return out


func _inside_envelope(p: Vector3) -> bool:
	var s := survey(p)
	var q := Vector2(s.x, s.y)
	if not _in_footprint(q, 0.3):
		return false
	# Under the main roof: no higher than its underside.
	var in_rect := Geometry2D.is_point_in_polygon(q, house.roof_rect)
	var in_tower := false
	for t: PackedVector2Array in TwainHouse.tower_plans():
		if Geometry2D.is_point_in_polygon(q, t):
			in_tower = true
	if in_rect and not in_tower and s.z > house.roof_y(q) + 0.3:
		return false
	return true


func _pokes() -> void:
	var out_found := {}
	var in_found := {}
	for group: String in ["inner", "furniture", "outer"]:
		var tm: TownMesh = house.meshes[group]
		for key: String in tm._surfaces:
			if key == "lamp" or key == "flame":
				continue
			var sf: TownMesh.Surface = tm._surfaces[key]
			for t in range(0, sf.i.size(), 3):
				var a := sf.v[sf.i[t]]
				var b := sf.v[sf.i[t + 1]]
				var c := sf.v[sf.i[t + 2]]
				# The roof's plastered underside is a room's ceiling.
				if group == "outer" and sf.n[sf.i[t]].y < -0.3:
					continue
				for p: Vector3 in _samples(a, b, c):
					if group != "outer":
						if _want("poke_out") or _want("poke"):
							if not _inside_envelope(p):
								var k := cell_key(p, 0.6)
								if not out_found.has(k):
									out_found[k] = [p, group, key, 0]
								out_found[k][3] += 1
					elif (_want("poke_in") or _want("poke")) and key != "glass":
						var r := room_at(p, 0.12)
						if not r.is_empty():
							var s := survey(p)
							# The roof's plastered underside is the room's ceiling.
							if p.y > TwainHouse.h(float(r["y0"])) + 0.05 and p.y < room_top(r, Vector2(s.x, s.y)) - 0.2:
								var k := cell_key(p, 0.6)
								if not in_found.has(k):
									in_found[k] = [p, r, key, 0]
								in_found[k][3] += 1
	for k: Vector3i in out_found:
		var f: Array = out_found[k]
		var p := f[0] as Vector3
		var eye := p + Vector3(p.x, 0, p.z).normalized() * 5.0 + Vector3(0, 1.0, 0)
		issue("poke_out", "the %s's %s shows outside the house" % [f[1], f[2]], p, eye, int(f[3]))
	for k: Vector3i in in_found:
		var f: Array = in_found[k]
		var p := f[0] as Vector3
		issue("poke_in", "%s: the outside's %s shows inside the room" % [(f[1] as Dictionary)["name"], f[2]], p,
			eye_toward(p, f[1]), int(f[3]))


## ---- clash, overlap: furniture ---------------------------------------------------

func _box_query(it: Dictionary, shrink: Vector3, mask: int, exclude: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var b := BoxShape3D.new()
	b.size = ((it["size"] as Vector3) - shrink * 2.0).max(Vector3(0.01, 0.01, 0.01))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = b
	var xf := it["xf"] as Transform3D
	# Lift a floor piece's box off the floor it stands on.
	if str(it["kind"]) == "floor":
		xf.origin += Vector3(0, shrink.y, 0)
	q.transform = xf
	q.collision_mask = mask
	q.exclude = exclude
	return q


func _label(i: int) -> String:
	var it: Dictionary = house.items[i]
	var s := survey((it["xf"] as Transform3D).origin)
	return "the %s at (%.1f, %.1f)" % [it["name"], s.x, s.y]


func _clashes() -> void:
	for i in house.items.size():
		var it: Dictionary = house.items[i]
		if str(it["kind"]) == "rug" or str(it["kind"]) == "door":
			continue
		# A piece's back may touch its wall, a lamp its ceiling.
		var q := _box_query(it, Vector3(0.03, 0.03, 0.03), L_BUILT, [])
		if bool(it["backed"]):
			var sz := it["size"] as Vector3
			var b := BoxShape3D.new()
			b.size = (sz - Vector3(0.06, 0.06, 0.06 + 0.04)).max(Vector3(0.01, 0.01, 0.01))
			q.shape = b
			q.transform.origin += (it["xf"] as Transform3D).basis.z * 0.02
		elif str(it["kind"]) == "hanging":
			var sz := it["size"] as Vector3
			var b := BoxShape3D.new()
			# Its stem and canopy pass the ceiling's ribs: only the arms count.
			b.size = (sz - Vector3(0.06, 0.4, 0.06)).max(Vector3(0.01, 0.01, 0.01))
			q.shape = b
			q.transform.origin -= Vector3(0, 0.2, 0)
		var hits := space.collide_shape(q, 8)
		if hits.is_empty():
			continue
		var what := {}
		for r: Dictionary in space.intersect_shape(q, 8):
			var node := r["collider"] as Node
			what["%s %s" % [node.get_meta("group"), node.get_meta("key")]] = true
		var p: Vector3 = hits[1] if hits.size() > 1 else (it["xf"] as Transform3D).origin
		print("[audit]   contacts: ", hits.slice(0, 8).map(func(v: Vector3) -> String: return where(v)))
		issue("clash", "%s runs into the %s (%s)" % [_label(i), ", ".join(PackedStringArray(what.keys())), "building"], p,
			eye_toward(p, room_at((it["xf"] as Transform3D).origin)))


func _overlaps() -> void:
	var seen := {}
	for i in house.items.size():
		var it: Dictionary = house.items[i]
		if str(it["kind"]) == "rug":
			continue
		var q := _box_query(it, Vector3(0.02, 0.02, 0.02), L_ITEM, [item_bodies[i]])
		for r: Dictionary in space.intersect_shape(q, 16):
			var j := int((r["collider"] as Node).get_meta("item"))
			if str(house.items[j]["kind"]) == "rug":
				continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			if seen.has(key):
				continue
			seen[key] = true
			var p := ((it["xf"] as Transform3D).origin + (house.items[j]["xf"] as Transform3D).origin) / 2.0
			issue("overlap", "%s and %s run into each other" % [_label(i), _label(j)], p, eye_toward(p, room_at(p)))


## ---- float: support ------------------------------------------------------------

func _support() -> void:
	for i in house.items.size():
		var it: Dictionary = house.items[i]
		var xf := it["xf"] as Transform3D
		var sz := it["size"] as Vector3
		var kind := str(it["kind"])
		var bottom := xf.origin - xf.basis.y * sz.y / 2.0
		match kind:
			"floor", "rug":
				var gaps: Array[float] = []
				for c: Vector2 in [Vector2(0, 0), Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)]:
					var p := bottom + xf.basis.x * sz.x * c.x + xf.basis.z * sz.z * c.y
					var hit := ray(p + Vector3(0, 0.25, 0), p - Vector3(0, 0.6, 0), L_BUILT)
					gaps.append(99.0 if hit.is_empty() else p.y - (hit["position"] as Vector3).y)
				var worst: float = gaps.max()
				var least: float = gaps.min()
				if worst > 0.05:
					issue("float", "%s stands %.0f cm off the floor at a corner" % [_label(i), minf(worst, 60.0) * 100.0], bottom,
						eye_toward(bottom, room_at(bottom + Vector3(0, 0.3, 0))))
				elif least < -0.03:
					issue("float", "%s sinks %.0f cm into what is under it" % [_label(i), -least * 100.0], bottom,
						eye_toward(bottom, room_at(bottom + Vector3(0, 0.3, 0))))
				if kind == "rug" and room_at(bottom + Vector3(0, 0.1, 0)).is_empty():
					issue("float", "%s lies outside any room" % _label(i), bottom)
			"hanging":
				var top := xf.origin + Vector3(0, sz.y / 2.0, 0)
				var up := ray(top - Vector3(0, 0.15, 0), top + Vector3(0, 0.6, 0), L_BUILT)
				if up.is_empty() or (up["position"] as Vector3).y - top.y > 0.1:
					issue("float", "%s does not reach its ceiling" % _label(i), top, eye_toward(top, room_at(top - Vector3(0, 0.5, 0))))
				var low := xf.origin - Vector3(0, sz.y / 2.0, 0)
				var floor_hit := ray(low, low - Vector3(0, 6.0, 0), L_BUILT | L_FURN)
				if not floor_hit.is_empty() and low.y - (floor_hit["position"] as Vector3).y < 1.95:
					var under: bool = (floor_hit["collider"] as Node).get_meta("group") == "furniture"
					if not under:
						issue("float", "%s hangs %.2f m over the floor, too low to walk under" % [_label(i), low.y - (floor_hit["position"] as Vector3).y],
							low, eye_toward(low, room_at(low)))
		if bool(it["backed"]):
			var back := xf.origin - xf.basis.z * sz.z / 2.0
			var offs: Array[float] = []
			for c: Vector2 in [Vector2(0, 0), Vector2(-0.4, -0.3), Vector2(0.4, -0.3), Vector2(0.4, 0.3), Vector2(-0.4, 0.3)]:
				var p := back + xf.basis.x * sz.x * c.x + xf.basis.y * sz.y * c.y
				var hit := ray(p + xf.basis.z * 0.02, p - xf.basis.z * 0.5, L_BUILT)
				offs.append(0.5 if hit.is_empty() else p.distance_to(hit["position"] as Vector3))
			if offs.max() > 0.08:
				issue("float", "%s stands %.0f cm off the wall behind it" % [_label(i), offs.max() * 100.0], back,
					eye_toward(back, room_at(xf.origin)))


## ---- door: can the player pass ---------------------------------------------------

func _capsule_clear(center: Vector3, radius := 0.3, height := 1.5) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = 1
	return space.intersect_shape(q, 1).is_empty()


func _doors() -> void:
	for d: Dictionary in house.doors:
		if not bool(d.get("open", true)):
			continue
		var c := d["center"] as Vector3
		var n := d["normal"] as Vector3
		var base := Vector3(c.x, float(d["y0"]), c.z)
		for off: float in [-0.5, 0.0, 0.5]:
			var p := base + n * off + Vector3(0, 0.3 + 0.75, 0)
			if not _capsule_clear(p, 0.3, 1.5):
				issue("door", "the doorway at %s is blocked %s" % [where(base), "in the opening" if off == 0.0 else "just beside it"],
					base + n * off, base + n * (2.0 if off >= 0.0 else -2.0) + Vector3(0, 1.6, 0))
				break


## ---- reach: walk everywhere from the front door ---------------------------------

func _floor_at(x: float, z: float, y_from: float, y_to: float) -> float:
	var hit := ray(Vector3(x, y_from, z), Vector3(x, y_to, z), 1)
	return -1000.0 if hit.is_empty() else (hit["position"] as Vector3).y


func _reach() -> void:
	# The walk up the veranda steps to the front door.
	var start := TwainHouse.w(90.5, 99.0, TwainHouse.GRADE)
	var sy := _floor_at(start.x, start.z, 3.0, -1.0)
	var open := [[floori(start.x / CELL), floori(start.z / CELL), sy]]
	var seen := {}
	seen[Vector3i(open[0][0], open[0][1], roundi(sy / 0.25))] = sy
	var lo := TwainHouse.w(160.0, 10.0)
	var hi := TwainHouse.w(15.0, 120.0)
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var n := 0
	while not open.is_empty() and n < 400000:
		var cur: Array = open.pop_back()
		n += 1
		for s: Vector2i in steps:
			var i := int(cur[0]) + s.x
			var j := int(cur[1]) + s.y
			var x := (i + 0.5) * CELL
			var z := (j + 0.5) * CELL
			if x < minf(lo.x, hi.x) or x > maxf(lo.x, hi.x) or z < minf(lo.z, hi.z) or z > maxf(lo.z, hi.z):
				continue
			var y0 := float(cur[2])
			var y := _floor_at(x, z, y0 + 0.5, y0 - 0.5)
			if y < -100.0 or absf(y - y0) > 0.3:
				continue
			var key := Vector3i(i, j, roundi(y / 0.25))
			if seen.has(key):
				continue
			if not _capsule_clear(Vector3(x, y + 0.32 + 0.75, z), 0.3, 1.5):
				continue
			seen[key] = y
			open.append([i, j, y])
	# Each room: the free places the walk never came to. The servants' rooms
	# over the kitchen are reached by a back stair the model does not have.
	for r: Dictionary in house.rooms:
		if NOT_VISITED.has(r["name"]):
			continue
		var free := 0
		var got := 0
		var missed: Array[Vector3] = []
		for p: Vector3 in room_samples(r, CELL, 0.36):
			var fy := _floor_at(p.x, p.z, p.y + 0.5, p.y - 0.5)
			if fy < -100.0 or absf(fy - p.y) > 0.12 or not _capsule_clear(Vector3(p.x, fy + 0.32 + 0.75, p.z), 0.3, 1.5):
				continue
			free += 1
			var i := floori(p.x / CELL)
			var j := floori(p.z / CELL)
			var hit := false
			for dy in [-1, 0, 1]:
				if seen.has(Vector3i(i, j, roundi(fy / 0.25) + dy)):
					hit = true
			if hit:
				got += 1
			else:
				missed.append(Vector3(p.x, fy, p.z))
		if free == 0:
			issue("reach", "%s has no floor the player can stand on" % r["name"], TwainHouse.w(0, 0), Vector3.INF)
		elif got == 0:
			issue("reach", "%s cannot be walked to from the front door" % r["name"], missed[0], eye_toward(missed[0], r), free)
		else:
			# The largest connected patch cut off; small gaps between chairs
			# and the like are not worth a finding.
			var patch := _largest_patch(missed)
			if patch.size() * CELL * CELL < 1.0:
				continue
			missed = patch
			var p := missed[0]
			issue("reach", "%s: %.1f m² of floor cannot be walked to (cut off by furniture or a wall)" % [r["name"], missed.size() * CELL * CELL],
				p, eye_toward(p, r), missed.size())
	print("[audit] reach: walked %d places" % seen.size())
	_reach_maps(seen)


## The largest group of neighbouring places among `pts` (on the CELL grid).
func _largest_patch(pts: Array[Vector3]) -> Array[Vector3]:
	var by := {}
	for p: Vector3 in pts:
		by[Vector2i(floori(p.x / CELL), floori(p.z / CELL))] = p
	var seen := {}
	var best: Array[Vector3] = []
	for key: Vector2i in by:
		if seen.has(key):
			continue
		var group: Array[Vector3] = []
		var stack: Array[Vector2i] = [key]
		seen[key] = true
		while not stack.is_empty():
			var k0: Vector2i = stack.pop_back()
			group.append(by[k0])
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var k1 := k0 + d
				if by.has(k1) and not seen.has(k1):
					seen[k1] = true
					stack.append(k1)
		if group.size() > best.size():
			best = group
	return best


## A map of each floor seen from above, a pixel to a place: grey where
## the player can stand, green where the walk from the front door came,
## red where it could stand but never came, dark where furniture or a
## wall stands; written to user://audit_tw_reach_<floor>.png.
func _reach_maps(seen: Dictionary) -> void:
	var lo := TwainHouse.w(160.0, 15.0)
	var hi := TwainHouse.w(15.0, 120.0)
	var i0 := floori(minf(lo.x, hi.x) / CELL)
	var i1 := floori(maxf(lo.x, hi.x) / CELL)
	var j0 := floori(minf(lo.z, hi.z) / CELL)
	var j1 := floori(maxf(lo.z, hi.z) / CELL)
	var scale := 4
	for fl: Array in [["first", 0.0], ["second", TwainHouse.F2], ["third", TwainHouse.F3]]:
		var fy := TwainHouse.h(float(fl[1]))
		var img := Image.create((i1 - i0 + 1) * scale, (j1 - j0 + 1) * scale, false, Image.FORMAT_RGB8)
		img.fill(Color(0.1, 0.12, 0.15))
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var x := (i + 0.5) * CELL
				var z := (j + 0.5) * CELL
				var y := _floor_at(x, z, fy + 0.6, fy - 0.6)
				var col := Color(0.1, 0.12, 0.15)
				if y > -100.0 and absf(y - fy) > 0.12:
					col = Color(0.35, 0.3, 0.28)
				elif y > -100.0:
					if seen.has(Vector3i(i, j, roundi(y / 0.25))) or seen.has(Vector3i(i, j, roundi(y / 0.25) - 1)) or seen.has(Vector3i(i, j, roundi(y / 0.25) + 1)):
						col = Color(0.3, 0.75, 0.35)
					elif _capsule_clear(Vector3(x, y + 0.32 + 0.75, z), 0.3, 1.5):
						col = Color(0.85, 0.2, 0.15)
					else:
						col = Color(0.35, 0.3, 0.28)
				img.fill_rect(Rect2i((i - i0) * scale, (j - j0) * scale, scale, scale), col)
		img.save_png("user://audit_tw_reach_%s.png" % fl[0])
	# The same, with the rooms, furniture and doors, for tools/twain_plan.py.
	var geo := {"rooms": [], "items": [], "doors": [], "cells": []}
	for r: Dictionary in house.rooms:
		var pts: Array = []
		for q: Vector2 in r["poly"]:
			pts.append([q.x, q.y])
		geo["rooms"].append({"name": r["name"], "y0": r["y0"], "poly": pts})
	for i in house.items.size():
		var it: Dictionary = house.items[i]
		var xf := it["xf"] as Transform3D
		var sz := it["size"] as Vector3
		var corners: Array = []
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := xf.origin + xf.basis.x * sz.x / 2.0 * c.x + xf.basis.z * sz.z / 2.0 * c.y
			var s := survey(p)
			corners.append([s.x, s.y])
		var bottom := survey(xf.origin - Vector3(0, sz.y / 2.0, 0))
		geo["items"].append({"name": it["name"], "kind": it["kind"], "y": bottom.z, "corners": corners})
	for d: Dictionary in house.doors:
		var s := survey(d["center"] as Vector3)
		var a := survey((d["center"] as Vector3) + (d["along"] as Vector3) * float(d["width"]) / 2.0)
		var b := survey((d["center"] as Vector3) - (d["along"] as Vector3) * float(d["width"]) / 2.0)
		geo["doors"].append({"y": (float(d["y0"]) - TwainHouse.FL) / FT, "a": [a.x, a.y], "b": [b.x, b.y], "open": d.get("open", true)})
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var x := (i + 0.5) * CELL
			var z := (j + 0.5) * CELL
			for fl: float in [0.0, TwainHouse.F2, TwainHouse.F3]:
				var fy := TwainHouse.h(fl)
				var y := _floor_at(x, z, fy + 0.6, fy - 0.6)
				if y < -100.0:
					continue
				var state := 2
				if absf(y - fy) > 0.12:
					geo["cells"].append([snappedf(survey(Vector3(x, y, z)).x, 0.01), snappedf(survey(Vector3(x, y, z)).y, 0.01), fl, 2])
					continue
				if seen.has(Vector3i(i, j, roundi(y / 0.25))) or seen.has(Vector3i(i, j, roundi(y / 0.25) - 1)) or seen.has(Vector3i(i, j, roundi(y / 0.25) + 1)):
					state = 0
				elif _capsule_clear(Vector3(x, y + 0.32 + 0.75, z), 0.3, 1.5):
					state = 1
				var s := survey(Vector3(x, y, z))
				geo["cells"].append([snappedf(s.x, 0.01), snappedf(s.y, 0.01), fl, state])
	var f := FileAccess.open("user://twain_audit_geom.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(geo))
	f.close()


## ---- fight: coplanar faces of different colour ------------------------------------

func _fights() -> void:
	var buckets := {}
	var tris: Array = []
	for group: String in ["outer", "inner", "furniture", "dress"]:
		var tm: TownMesh = house.meshes[group]
		for key: String in tm._surfaces:
			if key == "lamp" or key == "flame" or key == "glass":
				continue
			var sf: TownMesh.Surface = tm._surfaces[key]
			for t in range(0, sf.i.size(), 3):
				var a := sf.v[sf.i[t]]
				var b := sf.v[sf.i[t + 1]]
				var c := sf.v[sf.i[t + 2]]
				var area := (b - a).cross(c - a).length() / 2.0
				var nn := sf.n[sf.i[t]]
				# Under the lawn nothing is seen.
				if area < 0.002 or maxf(a.y, maxf(b.y, c.y)) < 0.02:
					continue
				# Faces that look the same way: a face against the back of another
				# is never seen. The mesh's own normal says which way it looks.
				nn = nn.normalized()
				var d := nn.dot(a)
				var bk := [roundi(nn.x * 40.0), roundi(nn.y * 40.0), roundi(nn.z * 40.0), roundi(d / 0.003)]
				var col := sf.c[sf.i[t]]
				var idx := tris.size()
				tris.append([a, b, c, nn, col, key])
				var kk := "%d,%d,%d,%d" % bk
				if not buckets.has(kk):
					buckets[kk] = []
				buckets[kk].append(idx)
	var found := {}
	for kk: String in buckets:
		var parts := kk.split(",")
		var list: Array = buckets[kk].duplicate()
		# The neighbouring plane, a hair further along.
		var next := "%s,%s,%s,%d" % [parts[0], parts[1], parts[2], int(parts[3]) + 1]
		if buckets.has(next):
			list.append_array(buckets[next])
		if list.size() < 2:
			continue
		var cols := {}
		for idx: int in list:
			cols[str(tris[idx][4]) + str(tris[idx][5])] = true
		if cols.size() < 2:
			continue
		var n: Vector3 = tris[list[0]][3]
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u)
		# Each face into the half-metre patches its bounds cover.
		var patches := {}
		var flat := {}
		for idx: int in list:
			var t3: Array = tris[idx]
			var p2 := PackedVector2Array([Vector2((t3[0] as Vector3).dot(u), (t3[0] as Vector3).dot(v)),
				Vector2((t3[1] as Vector3).dot(u), (t3[1] as Vector3).dot(v)), Vector2((t3[2] as Vector3).dot(u), (t3[2] as Vector3).dot(v))])
			flat[idx] = p2
			var r := Rect2(p2[0], Vector2.ZERO).expand(p2[1]).expand(p2[2]).grow(-0.01)
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				continue
			for pi in range(floori(r.position.x / 0.5), floori(r.end.x / 0.5) + 1):
				for pj in range(floori(r.position.y / 0.5), floori(r.end.y / 0.5) + 1):
					var pk := Vector2i(pi, pj)
					if not patches.has(pk):
						patches[pk] = []
					patches[pk].append(idx)
		var done := {}
		for pk: Vector2i in patches:
			var here: Array = patches[pk]
			if here.size() < 2:
				continue
			for ai in here.size():
				var ia: int = here[ai]
				for bi in range(ai + 1, here.size()):
					var ib: int = here[bi]
					if tris[ia][4] == tris[ib][4] and tris[ia][5] == tris[ib][5]:
						continue
					var pair := Vector2i(mini(ia, ib), maxi(ia, ib))
					if done.has(pair):
						continue
					done[pair] = true
					var inter := Geometry2D.intersect_polygons(flat[ia], flat[ib])
					var area := 0.0
					for poly: PackedVector2Array in inter:
						area += absf(TwainHouse.signed_area(poly)) / 2.0
					if area < 0.01:
						continue
					# Where the two overlap, and whether anything stands right in
					# front of it: a face pressed against another is never seen.
					var seen_pts := 0
					var at := Vector3.ZERO
					for poly: PackedVector2Array in inter:
						var cen := Vector2.ZERO
						for q: Vector2 in poly:
							cen += q
						cen /= poly.size()
						var p3 := n * (tris[ia][0] as Vector3).dot(n) + u * cen.x + v * cen.y
						if _visible_face(p3, n) and _eye_place(p3 + n * 0.3):
							seen_pts += 1
							at = p3
					if seen_pts == 0:
						continue
					var key := cell_key(at, 0.8)
					if not found.has(key) or float(found[key][4]) < area:
						found[key] = [at, tris[ia][5], tris[ib][5], n, area, [tris[ia], tris[ib]]]
	var keys := found.keys()
	keys.sort_custom(func(ka: Vector3i, kb: Vector3i) -> bool: return float(found[ka][4]) > float(found[kb][4]))
	for key: Vector3i in keys:
		var f: Array = found[key]
		if float(f[4]) < 0.01:
			continue
		if OS.get_environment("FLOWSTATE_TW_AUDIT_DEBUG") != "":
			for tr: Array in f[5]:
				print("[audit]   face %s col %s: %s | %s | %s  (%.3f %.3f %.3f)" % [tr[5], str(tr[4]), where(tr[0]), where(tr[1]), where(tr[2]), (tr[0] as Vector3).x, (tr[0] as Vector3).y, (tr[0] as Vector3).z])
		var p := f[0] as Vector3
		var r := room_at(p + (f[3] as Vector3) * 0.1)
		if r.is_empty():
			r = room_at(p - (f[3] as Vector3) * 0.1)
		var eye := eye_toward(p, r) if not r.is_empty() else p + (f[3] as Vector3) * 3.0 + Vector3(0, 0.5, 0)
		issue("fight", "two surfaces (%s, %s) lie in one plane over %.2f m²; they flicker" % [f[1], f[2], float(f[4])], p, eye)


## Whether a face at p looking along n can be seen: the point just in
## front of it is not enclosed (rays from it in the six directions meet the
## backs of surfaces in at least five), and from it a clear 0.8 m opens in
## at least one of five directions round n, so an eye could stand there.
func _visible_face(p: Vector3, n: Vector3) -> bool:
	var o := p + n * 0.004
	var backs := 0
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var hit := ray(o, o + d * 30.0, L_BUILT | L_FURN)
		if not hit.is_empty() and (hit["normal"] as Vector3).dot(d) > 0.0:
			backs += 1
	if backs >= 5:
		return false
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	for d: Vector3 in [n, (n + u * 0.7).normalized(), (n - u * 0.7).normalized(), (n + v * 0.7).normalized(), (n - v * 0.7).normalized()]:
		var hit := ray(o, o + d * 0.8, L_BUILT | L_FURN)
		if hit.is_empty():
			return true
	return false


## Whether an eye could be at p: in a room, or outside the house.
func _eye_place(p: Vector3) -> bool:
	if not room_at(p).is_empty():
		return true
	var s := survey(p)
	return not _in_footprint(Vector2(s.x, s.y)) or p.y > TwainHouse.h(house.roof_y(Vector2(s.x, s.y)))


## ---- the report --------------------------------------------------------------------

func _report() -> void:
	var by := {}
	for it: Dictionary in issues:
		by[it["check"]] = int(by.get(it["check"], 0)) + 1
	print("[audit] %d findings: %s" % [issues.size(), str(by)])
	var n := 0
	for it: Dictionary in issues:
		n += 1
		print("[audit] %03d %-8s %s — %s, in %s" % [n, it["check"], it["text"], it["where"], it["room"]])
	var out: Array = []
	for it: Dictionary in issues:
		var at := it["at"] as Vector3
		var eye := it["eye"] as Vector3
		out.append({"check": it["check"], "text": it["text"], "where": it["where"], "room": it["room"], "count": it["count"],
			"at": [at.x, at.y, at.z], "eye": [] if eye == Vector3.INF else [eye.x, eye.y, eye.z]})
	var f := FileAccess.open("user://twain_audit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()


## A picture of each finding (the first `limit`), from its camera.
func _pictures(limit: int) -> void:
	var player := world.player
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	world.set_time_of_day(11.0)
	player._fov_target = 70.0
	player.camera.fov = 70.0
	var n := 0
	for it: Dictionary in issues:
		n += 1
		if n > limit:
			break
		var eye := it["eye"] as Vector3
		if eye == Vector3.INF:
			continue
		var at := it["at"] as Vector3
		var d := at - eye
		player.global_position = eye - Vector3(0, 1.6, 0)
		player.velocity = Vector3.ZERO
		player.rotation.y = atan2(-d.x, -d.z)
		player.camera.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
		await get_tree().create_timer(0.6).timeout
		player.global_position = eye - Vector3(0, 1.6, 0)
		player.velocity = Vector3.ZERO
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://audit_tw_%03d.png" % n)
	print("[audit] pictures written to user://audit_tw_NNN.png")
