class_name CourthousePlaces
extends RefCounted
## The named places in and round the courthouse and the walkable legs
## between them: the plazas, the porches and their steps, the halls,
## both stairs by their landings, the courtroom by the judge's door and
## the public's door, the gallery by its stairs. A route is the shortest
## chain of legs (Dijkstra), from the place nearest the walker; every leg
## is a straight walk the player's capsule can make, stairs by their
## ramps. In the courthouse's frame, y the floor's height.

const F1 := UnionCourthouse.F1
const F2 := UnionCourthouse.F2
const LAND := F1 + (F2 - F1) / 2.0
const GROUND := 0.13
const GAL := F2 + 3.9

const NODES := {
	# The square.
	"west_walk": Vector3(-29.4, GROUND, 0.0),
	# Eight points round the monument, clear of its railing's corners.
	"monument_w": Vector3(-26.6, GROUND, 0.0),
	"monument_nw": Vector3(-25.4, GROUND, -2.9),
	"monument_n": Vector3(-22.5, GROUND, -4.1),
	"monument_ne": Vector3(-19.6, GROUND, -2.9),
	"monument_e": Vector3(-18.4, GROUND, 0.0),
	"monument_se": Vector3(-19.6, GROUND, 2.9),
	"monument_s": Vector3(-22.5, GROUND, 4.1),
	"monument_sw": Vector3(-25.4, GROUND, 2.9),
	"west_steps": Vector3(-16.9, GROUND, 0.0),
	"west_porch": Vector3(-12.2, F1, 0.0),
	"east_porch": Vector3(12.2, F1, 0.0),
	"east_steps": Vector3(16.9, GROUND, 0.0),
	"east_plaza": Vector3(21.5, GROUND, 0.0),
	"east_walk": Vector3(29.4, GROUND, 0.0),
	"north_door_out": Vector3(0.0, GROUND, -25.6),
	"south_door_out": Vector3(0.0, GROUND, 25.6),
	# The ground floor.
	"west_hall": Vector3(-7.0, F1, 0.0),
	"crossing": Vector3(0.0, F1, 0.0),
	"east_hall": Vector3(7.0, F1, 0.0),
	"heritage_door": Vector3(-5.2, F1, -0.6),
	"heritage_room": Vector3(-4.2, F1, -4.6),
	"main_north": Vector3(0.0, F1, -6.8),
	"main_south": Vector3(0.0, F1, 6.8),
	"north_hall": Vector3(0.0, F1, -10.6),
	"bell": Vector3(-0.95, F1, -16.4),
	"north_end": Vector3(0.0, F1, -20.3),
	"south_hall": Vector3(0.0, F1, 10.6),
	"south_end": Vector3(0.0, F1, 20.3),
	# The north stair, up to the chambers and the judge's door.
	"north_stair_foot": Vector3(1.0, F1, -9.55),
	"north_landing_a": Vector3(7.0, LAND, -9.6),
	"north_landing_b": Vector3(7.0, LAND, -11.4),
	"north_stair_head": Vector3(0.6, F2, -11.4),
	"north_upstairs": Vector3(0.0, F2, -12.6),
	"chambers_door": Vector3(-1.4, F2, -12.0),
	"chambers": Vector3(-2.4, F2, -10.2),
	"judge_door": Vector3(-5.2, F2, -9.3),
	# The courtroom.
	"behind_bench": Vector3(-5.2, F2, -7.6),
	"courtroom": Vector3(-5.0, F2, -3.8),
	"well": Vector3(-0.7, F2, -3.8),
	"bar_gate": Vector3(0.0, F2, -0.3),
	# In front of the pews, and down the west wall past their ends.
	"front_aisle": Vector3(0.0, F2, 1.15),
	"front_aisle_w": Vector3(-8.7, F2, 1.15),
	"aisle": Vector3(0.0, F2, 2.6),
	"under_gallery": Vector3(0.0, F2, 6.0),
	"courtroom_door": Vector3(0.0, F2, 8.3),
	"gallery_stair_foot": Vector3(-8.7, F2, 5.8),
	"gallery_stair_start": Vector3(-8.7, F2, 7.7),
	"gallery_back": Vector3(-1.2, GAL, 7.7),
	"gallery": Vector3(0.0, F2 + 3.05, 3.9),
	# The south stair, down to the south hall.
	"south_upstairs": Vector3(0.3, F2, 11.0),
	"south_stair_head": Vector3(-0.6, F2, 11.4),
	"south_landing_b": Vector3(-7.0, LAND, 11.4),
	"south_landing_a": Vector3(-7.0, LAND, 9.6),
	"south_stair_foot": Vector3(-1.0, F1, 9.55),
}

const LEGS := [
	["west_walk", "monument_w"], ["monument_w", "monument_nw"], ["monument_nw", "monument_n"],
	["monument_n", "monument_ne"], ["monument_ne", "monument_e"], ["monument_e", "monument_se"],
	["monument_se", "monument_s"], ["monument_s", "monument_sw"], ["monument_sw", "monument_w"],
	["monument_e", "west_steps"],
	["west_steps", "west_porch"], ["west_porch", "west_hall"], ["west_hall", "crossing"],
	["crossing", "east_hall"], ["east_hall", "east_porch"], ["east_porch", "east_steps"],
	["east_steps", "east_plaza"], ["east_plaza", "east_walk"],
	["west_hall", "heritage_door"], ["heritage_door", "heritage_room"],
	["crossing", "main_north"], ["main_north", "north_hall"], ["north_hall", "bell"], ["bell", "north_end"],
	["north_end", "north_door_out"],
	["crossing", "main_south"], ["main_south", "south_hall"], ["south_hall", "south_end"],
	["south_end", "south_door_out"],
	["north_hall", "north_stair_foot"], ["north_stair_foot", "north_landing_a"],
	["north_landing_a", "north_landing_b"], ["north_landing_b", "north_stair_head"],
	["north_stair_head", "north_upstairs"], ["north_upstairs", "chambers_door"], ["chambers_door", "chambers"],
	["chambers", "judge_door"], ["judge_door", "behind_bench"], ["behind_bench", "courtroom"],
	["courtroom", "well"], ["well", "bar_gate"], ["bar_gate", "front_aisle"], ["front_aisle", "aisle"],
	["front_aisle", "front_aisle_w"], ["front_aisle_w", "gallery_stair_foot"], ["aisle", "under_gallery"],
	["under_gallery", "courtroom_door"], ["courtroom_door", "south_upstairs"],
	["south_upstairs", "south_stair_head"], ["south_stair_head", "south_landing_b"],
	["south_landing_b", "south_landing_a"], ["south_landing_a", "south_stair_foot"],
	["south_stair_foot", "south_hall"],
	["gallery_stair_foot", "gallery_stair_start"],
	["gallery_stair_start", "gallery_back"], ["gallery_back", "gallery"],
]

## Other names people use for a place.
const ALIASES := {
	"monument": "monument_e", "square": "west_walk", "west_plaza": "monument_e", "porch": "west_porch",
	"west_door": "west_porch", "east_door": "east_porch", "hall": "crossing", "downstairs": "crossing",
	"upstairs": "north_upstairs", "court": "courtroom", "courtroom_center": "well", "bench": "behind_bench",
	"judge": "behind_bench", "balcony": "gallery", "heritage": "heritage_room", "bell_display": "bell",
	"north_stair": "north_stair_foot", "south_stair": "south_stair_foot", "pews": "aisle",
}


static func resolve(name: String) -> String:
	var n := name.strip_edges().to_lower().replace(" ", "_")
	if NODES.has(n):
		return n
	return str(ALIASES.get(n, ""))


## The place nearest a point, weighting height heavily so a walker on
## the stairs or upstairs finds a place on his own floor.
static func nearest(p: Vector3) -> String:
	var best := ""
	var best_d := INF
	for n: String in NODES:
		var q: Vector3 = NODES[n]
		var d := Vector2(q.x - p.x, q.z - p.z).length() + 4.0 * absf(q.y - p.y)
		if d < best_d:
			best_d = d
			best = n
	return best


## The places from a to b along the legs, a and b included; empty when
## no way joins them.
static func route(a: String, b: String) -> Array[String]:
	var dist := {a: 0.0}
	var prev := {}
	var open: Array[String] = [a]
	var done := {}
	while not open.is_empty():
		var cur := open[0]
		for n in open:
			if float(dist[n]) < float(dist[cur]):
				cur = n
		open.erase(cur)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == b:
			break
		for leg: Array in LEGS:
			var other := ""
			if leg[0] == cur:
				other = leg[1]
			elif leg[1] == cur:
				other = leg[0]
			if other == "" or done.has(other):
				continue
			var d := float(dist[cur]) + (NODES[cur] as Vector3).distance_to(NODES[other] as Vector3)
			if not dist.has(other) or d < float(dist[other]):
				dist[other] = d
				prev[other] = cur
				open.append(other)
	var out: Array[String] = []
	if not dist.has(b):
		return out
	var n := b
	while true:
		out.push_front(n)
		if n == a:
			break
		n = prev[n]
	return out
