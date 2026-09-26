class_name CourthouseAffordances
extends RefCounted
## What the courthouse and its square offer an actor: every doorway,
## stair, seat and notable thing, each with a name, a short description
## a visitor could see for himself, where it is and what can be done with
## it. Doors are gone through, stairs climbed to any share of their
## height, seats sat on, things looked at and approached. Actors perceive
## the ones in their line of sight; the stage walks them to one by name.
##
## Each: {id, kind: door|stairs|seat|thing|window, desc, at, verbs}, and
## a seat's facing (yaw, radians, 0 north, pi/2 west), the floor spot to
## approach it from and how many it seats (spots, gap metres apart along
## it), a stair's path from its foot to its head.

const F1 := UnionCourthouse.F1
const F2 := UnionCourthouse.F2
const LAND := F1 + (F2 - F1) / 2.0
const GAL := F2 + 3.9
const IZ := UnionCourthouse.MZ - UnionCourthouse.T
const IX := UnionCourthouse.MX - UnionCourthouse.T

static var _all: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _all.is_empty():
		_build()
	return _all


static func find(id: String) -> Dictionary:
	for a in all():
		if a["id"] == id:
			return a
	return {}


static func _add(id: String, kind: String, desc: String, at: Vector3, verbs: Array, extra := {}) -> void:
	var a := {"id": id, "kind": kind, "desc": desc, "at": at, "verbs": verbs}
	a.merge(extra)
	_all.append(a)


static func _seat(id: String, desc: String, at: Vector3, yaw: float, approach: Vector3, spots := 1, gap := 0.55) -> void:
	if spots > 1:
		desc += "; seats %d" % spots
	_add(id, "seat", desc, at, ["sit", "look_at"], {"yaw": yaw, "approach": approach, "spots": spots, "gap": gap})


static func _stairs(id: String, desc: String, path: Array[Vector3]) -> void:
	_add(id, "stairs", desc, path[0], ["climb", "look_at"], {"path": path})


static func _build() -> void:
	# Outside.
	_add("monument", "thing", "a tall granite monument inside an iron railing", Vector3(-22.5, 0.13, 0), ["approach", "look_at"])
	_add("clock_tower", "thing", "the clock tower on the roof, a clock on each face", Vector3(0, 30.4, 0), ["look_at"])
	_add("west_porch", "thing", "a porch of white arches before the west doors", Vector3(-12.0, UnionCourthouse.F1, 0), ["approach", "look_at"])
	_add("east_porch", "thing", "a porch of white arches before the east doors", Vector3(12.0, UnionCourthouse.F1, 0), ["approach", "look_at"])
	_stairs("west_porch_steps", "granite steps up to the west porch", [Vector3(-16.8, 0.0, 0), Vector3(-12.3, F1, 0)])
	_stairs("east_porch_steps", "granite steps up to the east porch", [Vector3(16.8, 0.0, 0), Vector3(12.3, F1, 0)])
	_stairs("north_steps", "granite steps up to the north door", [Vector3(0, 0.0, -25.5), Vector3(0, F1, -22.4)])
	_stairs("south_steps", "granite steps up to the south door", [Vector3(0, 0.0, 25.5), Vector3(0, F1, 22.4)])
	var k := 0
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			k += 1
			_seat("park_bench_%d" % k, "a wooden park bench on iron legs", Vector3(s * 22.0, 0.0, e * 7.4 + e * 0.05),
				0.0 if e > 0.0 else PI, Vector3(s * 22.0, 0.0, e * 7.4 - e * 0.8), 3, 0.62)
	# The doors.
	_add("west_doors", "door", "the building's west doors, standing open", Vector3(-10.0, F1, 0), ["go_through", "look_at"])
	_add("east_doors", "door", "the building's east doors, standing open", Vector3(10.0, F1, 0), ["go_through", "look_at"])
	_add("north_doors", "door", "a doorway in the north end, under a stone hood dated 1886", Vector3(0, F1, -21.9), ["go_through", "look_at"])
	_add("south_doors", "door", "a doorway in the south end, under a stone hood dated 1886", Vector3(0, F1, 21.9), ["go_through", "look_at"])
	_add("heritage_room_door", "door", "a door with HERITAGE ROOM lettered over it", Vector3(-5.2, F1, -1.5), ["go_through", "look_at"])
	_add("office_door_ne", "door", "an office door off the cross hall", Vector3(5.2, F1, -1.5), ["go_through", "look_at"])
	_add("office_door_sw", "door", "an office door off the cross hall", Vector3(-5.2, F1, 1.5), ["go_through", "look_at"])
	_add("office_door_se", "door", "an office door off the cross hall", Vector3(5.2, F1, 1.5), ["go_through", "look_at"])
	_add("north_arch", "door", "a wide round arch at the end of the hall", Vector3(0, F1, -8.65), ["go_through", "look_at"])
	_add("south_arch", "door", "a wide round arch at the end of the hall", Vector3(0, F1, 8.65), ["go_through", "look_at"])
	_add("chambers_door", "door", "a door off the upstairs hall", Vector3(-1.4, F2, -12.0), ["go_through", "look_at"])
	_add("judges_door", "door", "a door in the wall behind the judge's bench", Vector3(-5.2, F2, -8.65), ["go_through", "look_at"])
	_add("courtroom_doors", "door", "the courtroom's double doors", Vector3(0, F2, 8.65), ["go_through", "look_at"])
	# The stairs.
	_stairs("north_stairs", "a wooden staircase with turned balusters, turning at a landing",
		[Vector3(1.0, F1, -9.55), Vector3(6.3, LAND, -9.55), Vector3(7.2, LAND, -10.5), Vector3(6.3, LAND, -11.4), Vector3(0.9, F2, -11.4)])
	_stairs("south_stairs", "a wooden staircase with turned balusters, turning at a landing",
		[Vector3(-1.0, F1, 9.55), Vector3(-6.3, LAND, 9.55), Vector3(-7.2, LAND, 10.5), Vector3(-6.3, LAND, 11.4), Vector3(-0.9, F2, 11.4)])
	_stairs("gallery_stairs_west", "a narrow stair up to the gallery", [Vector3(-8.7, F2, 7.7), Vector3(-2.2, GAL, 7.7)])
	_stairs("gallery_stairs_east", "a narrow stair up to the gallery", [Vector3(8.7, F2, 7.7), Vector3(2.2, GAL, 7.7)])
	# Downstairs.
	_add("bell", "thing", "a big bronze bell hung on a panelled pedestal", Vector3(0, F1, -16.4), ["approach", "look_at"])
	_add("plaque", "thing", "a bronze plaque listing county commissioners", Vector3(-1.3, F1 + 1.8, -16.9), ["approach", "look_at"])
	_add("notice_board", "thing", "a notice board with papers pinned to it", Vector3(1.3, F1 + 1.65, -18.6), ["approach", "look_at"])
	_add("map", "thing", "a framed old map of the county", Vector3(-7.6, F1 + 1.7, 1.42), ["approach", "look_at"])
	_add("display_cases", "thing", "glass display cases of old things: a ledger, a gavel, papers", Vector3(-7.8, F1 + 0.8, -1.1), ["approach", "look_at"])
	for e: float in [-1.0, 1.0]:
		_seat("hall_bench_%s" % ("north" if e < 0.0 else "south"), "a slatted wooden bench against the hall wall",
			Vector3(-1.05, F1, e * 6.3), -PI / 2.0, Vector3(-0.4, F1, e * 6.3), 3, 0.55)
	# The courtroom.
	_add("judges_bench", "thing", "a raised panelled bench, a tall navy leather chair behind it", Vector3(0, F2 + 0.6, -IZ + 2.1), ["approach", "look_at"])
	_seat("judges_chair", "the judge's tall navy leather chair", Vector3(0, F2 + 0.55, -IZ + 0.75), PI, Vector3(-2.4, F2 + 0.55, -IZ + 0.7))
	_add("witness_stand", "thing", "a panelled witness box with a chair in it", Vector3(4.3, F2 + 0.3, -IZ + 1.7), ["approach", "look_at"])
	_seat("witness_chair", "the chair in the witness box", Vector3(4.3, F2 + 0.3, -IZ + 1.5), PI, Vector3(5.6, F2, -IZ + 1.4))
	_add("jury_box", "thing", "the jury box: two rows of chairs behind a panelled rail", Vector3(7.4, F2, -3.4), ["approach", "look_at"])
	var jx := IX - 1.6
	for row in 2:
		for j in 6:
			_seat("jury_chair_%d" % (row * 6 + j + 1), "a juror's chair", Vector3(jx + 0.2 + row * 0.95, F2 + 0.15 + 0.3 * row, -5.6 + j * 0.88),
				PI / 2.0, Vector3(jx - 0.9, F2, -5.6 + j * 0.88))
	_add("clerks_desk", "thing", "the clerk's panelled desk below the bench", Vector3(0, F2, -IZ + 3.0), ["approach", "look_at"])
	_add("lectern", "thing", "a lectern between the counsel tables", Vector3(0, F2, -2.9), ["approach", "look_at"])
	for s: float in [-1.0, 1.0]:
		var side := "west" if s < 0.0 else "east"
		_add("counsel_table_" + side, "thing", "a long counsel table with chairs", Vector3(s * 2.6, F2, -1.7), ["approach", "look_at"])
		_seat("counsel_chair_" + side, "a chair at the counsel table", Vector3(s * 2.6, F2, -0.95), 0.0, Vector3(s * 2.6, F2, -0.3))
	_add("bar_gate", "door", "a little gate in the rail between the public and the court", Vector3(0, F2, 0.6), ["go_through", "look_at"])
	for row in 6:
		var pz := 1.9 + row * 0.92
		for s: float in [-1.0, 1.0]:
			_seat("pew_%d_%s" % [row + 1, "west" if s < 0.0 else "east"], "a public pew, row %d" % (row + 1),
				Vector3(s * 4.7, F2, pz + 0.04), 0.0, Vector3(s * 0.7, F2, pz + 0.1), 6, 1.05)
	_add("gallery", "thing", "a gallery over the back of the courtroom, a brass rail along its front", Vector3(0, F2 + 3.0, 3.6), ["approach", "look_at"])
	for t in 4:
		for s: float in [-1.0, 1.0]:
			var gy := F2 + 3.0 + 0.3 * t
			var gz := 3.4 + 0.95 * t + 0.37
			_seat("gallery_pew_%d_%s" % [t + 1, "west" if s < 0.0 else "east"], "a pew in the gallery, row %d" % (t + 1),
				Vector3(s * 4.9, gy, gz), 0.0, Vector3(s * 0.8, gy, gz), 6, 1.2)
	_add("frieze", "thing", "a frieze of green garlands and gilt bows round the top of the walls", Vector3(0, 12.9, -IZ), ["look_at"])
	_add("charter", "thing", "a framed document hung in an arched niche behind the bench", Vector3(0, F2 + 2.7, -IZ), ["approach", "look_at"])
	for s: float in [-1.0, 1.0]:
		for u: float in [-2.9, 0.0, 2.9]:
			_add("courtroom_window_%s_%d" % ["west" if s < 0.0 else "east", int(u / 2.9) + 2], "window",
				"a tall arched window, wooden blinds over its top", Vector3(s * (UnionCourthouse.PX - UnionCourthouse.T), F2 + 2.2, u),
				["approach", "look_out", "look_at"])
