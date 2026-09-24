class_name VialLine
## The filling line's one placement rule, run by the plant
## whenever a line part is placed, moved, resized or removed and on a
## load, and asked by the builder for a snapped ghost:
##
##   * a part's outfeed is linked to the infeed standing where it ends,
##     within LINK_GAP in plan and at the same height: a kernel item
##     wire, hidden, never saved, derived again each time;
##   * a device (a gate, an eye, a load cell, a needle, a capper) is
##     seated on the track whose centreline it stands over, at the
##     distance along it where it stands, or on the star-wheel station
##     it stands at;
##   * the vial size runs down the line from each magazine, so rails
##     and pockets are sized to what they carry.
##
## Nothing is tabulated per layout: move a part and the rule finds its
## neighbours again (the placement-derived-state rule).

const CARRIERS: Array[String] = ["vial_track", "star_wheel"]
const DEVICES: Array[String] = ["stop_gate", "photo_eye", "load_cell", "fill_needle", "capper"]
const ENDS: Array[String] = ["vial_magazine", "vial_table"]
const LINK_GAP := 0.10     # an outfeed and an infeed this close in plan are one handoff
const SEAT_GAP := 0.06     # a device this far off a track's centreline is still on it
const SNAP_REACH := 0.6    # the builder snaps a ghost within this of a track or an outfeed


static func is_line_type(type_id: String) -> bool:
	return CARRIERS.has(type_id) or DEVICES.has(type_id) or ENDS.has(type_id)


## Every handoff point of every line part, plant-local:
## [[name, port, point, is_output]].
static func _points(plant: Plant) -> Array:
	var out: Array = []
	for name_: String in plant.views:
		var view := plant.views[name_] as VialPartView
		if view == null:
			continue
		var record := plant.sim.get_component(name_)
		var points := view.item_points()
		for port: String in points:
			out.append([name_, port, plant.to_local(view.to_global(points[port] as Vector3)),
				record.outputs.has(port)])
	return out


static func sync(plant: Plant) -> void:
	var sim := plant.sim
	# ---- links: drop every item wire and find them again by position.
	var stale: Array = []
	for wire in sim.wires:
		if wire.src.kind == SimTypes.PortKind.ITEM:
			stale.append(wire)
	for wire: SimWire in stale:
		sim.disconnect_ports(sim.get_component(wire.src.owner_name), wire.src.port_name,
			sim.get_component(wire.dst.owner_name), wire.dst.port_name)
	var points := _points(plant)
	var used := {}
	var next := {}   # name -> [downstream names]
	for out_v: Variant in points:
		var out: Array = out_v
		if not bool(out[3]):
			continue
		var best: Array = []
		var best_d := LINK_GAP
		for in_v: Variant in points:
			var into: Array = in_v
			if bool(into[3]) or into[0] == out[0] or used.has("%s:%s" % [into[0], into[1]]):
				continue
			var a: Vector3 = out[2]
			var b: Vector3 = into[2]
			var d := Vector2(a.x - b.x, a.z - b.z).length()
			if d <= best_d and absf(a.y - b.y) < 0.1:
				best = into
				best_d = d
		if best.is_empty():
			continue
		used["%s:%s" % [best[0], best[1]]] = true
		sim.connect_ports(sim.get_component(str(out[0])), str(out[1]),
			sim.get_component(str(best[0])), str(best[1]))
		(next.get_or_add(str(out[0]), []) as Array).append(str(best[0]))
	# ---- seats: every device on the carrier it stands over.
	for name_: String in plant.views:
		var carrier := sim.get_component(name_) as SimVialCarrier
		if carrier != null:
			carrier.clear_mounts()
	for name_: String in plant.views:
		var device := sim.get_component(name_) as SimVialMount
		if device == null:
			continue
		var seat := seat_of(plant, (plant.views[name_] as Node3D).global_position)
		if not seat.is_empty():
			(sim.get_component(str(seat["host"])) as SimVialCarrier).mount(device, float(seat["s"]))
	# ---- the vial size down the line from each magazine.
	for name_: String in plant.views:
		var magazine := sim.get_component(name_) as SimVialMagazine
		if magazine == null:
			continue
		var queue: Array = [name_]
		var seen := {}
		while not queue.is_empty():
			var at := str(queue.pop_front())
			if seen.has(at):
				continue
			seen[at] = true
			var view := plant.views.get(at) as VialPartView
			if view != null:
				view.set_vial_ml(magazine.vial_ml)
			queue.append_array(next.get(at, []) as Array)
	for name_: String in plant.views:
		var device := sim.get_component(name_) as SimVialMount
		if device != null and device.host != "":
			var host_view := plant.views.get(device.host) as VialPartView
			var view := plant.views[name_] as VialPartView
			if host_view != null and view != null:
				view.set_vial_ml(host_view.vial_ml)


## The carrier a device standing here is on, and where along it:
## {"host", "s", "rot"} or {} when it stands over none.
static func seat_of(plant: Plant, world: Vector3) -> Dictionary:
	var best := {}
	var best_d := SEAT_GAP
	for name_: String in plant.views:
		var view = plant.views[name_]
		if view is VialTrackView:
			var track := view as VialTrackView
			var local := track.to_local(world)
			var half := track.track.length_m / 2.0
			if absf(local.y) > 0.3 or local.x < -half or local.x > half:
				continue
			if absf(local.z) <= best_d:
				best_d = absf(local.z)
				best = {"host": name_, "s": local.x + half, "rot": track.global_rotation.y}
		elif view is StarWheelView:
			var wheel := view as StarWheelView
			var local := wheel.to_local(world)
			if absf(local.y) > 0.3:
				continue
			for k in wheel.wheel.pockets:
				var p := StarWheelView.station_point(wheel.wheel.pitch_radius_m, wheel.wheel.pockets, float(k))
				var d := Vector2(local.x - p.x, local.z - p.z).length()
				if d <= best_d:
					best_d = d
					var outward := atan2(p.x, p.z)   # the device's +z looks out from the wheel
					best = {"host": name_, "s": float(k), "rot": wheel.global_rotation.y + outward}
	return best


## Where the builder puts a line part's ghost aimed at `aim` (world):
## a device on the nearest track or station, a carrier or a table with
## its infeed on the nearest free outfeed. {"pos", "rot", "note"}, or
## {"why"} for a device aimed at nothing it can stand on, or {} to place
## freely.
static func snap(plant: Plant, type_id: String, aim: Vector3) -> Dictionary:
	if DEVICES.has(type_id):
		var best := {}
		var best_d := SNAP_REACH
		for name_: String in plant.views:
			var view = plant.views[name_]
			if view is VialTrackView:
				var track := view as VialTrackView
				var local := track.to_local(aim)
				var half := track.track.length_m / 2.0
				var x := clampf(local.x, -half, half)
				var d := Vector2(local.x - x, local.z).length()
				if d < best_d:
					best_d = d
					var at := track.to_global(Vector3(snappedf(x + half, 0.005) - half, 0, 0))
					best = {"pos": at, "rot": track.global_rotation.y,
						"note": "on %s at %.3f m" % [name_, x + half]}
			elif view is StarWheelView:
				var wheel := view as StarWheelView
				var local := wheel.to_local(aim)
				for k in wheel.wheel.pockets:
					var p := StarWheelView.station_point(wheel.wheel.pitch_radius_m, wheel.wheel.pockets, float(k))
					var d := Vector2(local.x - p.x, local.z - p.z).length()
					if d < best_d:
						best_d = d
						best = {"pos": wheel.to_global(Vector3(p.x, 0, p.z)),
							"rot": wheel.global_rotation.y + atan2(p.x, p.z),
							"note": "on %s at station %d" % [name_, k]}
		if best.is_empty():
			return {"why": "a %s stands over a vial track or a star wheel — aim at one" % PlantFactory.label_for(type_id).to_lower()}
		return best
	if not (CARRIERS.has(type_id) or type_id == "vial_table"):
		return {}
	# A carrier or a table: its infeed on the nearest outfeed nothing takes.
	var taken := {}
	for wire in plant.sim.wires:
		if wire.src.kind == SimTypes.PortKind.ITEM:
			taken[wire.src.path()] = true
	var best := {}
	var best_d := SNAP_REACH
	for name_: String in plant.views:
		var view := plant.views[name_] as VialPartView
		if view == null:
			continue
		var record := plant.sim.get_component(name_)
		for port: String in view.item_points():
			if not record.outputs.has(port) or taken.has("%s.%s" % [name_, port]):
				continue
			var local_pt: Vector3 = view.item_points()[port]
			var world := view.to_global(local_pt)
			var d := Vector2(world.x - aim.x, world.z - aim.z).length()
			if d >= best_d:
				continue
			# The way the vial is travelling as it leaves: along the part's
			# own +x, or outward from a star wheel.
			var dir := view.global_basis.x
			if view is StarWheelView:
				dir = (view.global_basis * Vector3(local_pt.x, 0, local_pt.z)).normalized()
			var rot := atan2(-dir.z, dir.x)
			var infeed := _infeed_local(type_id)
			var floor_at := Vector3(world.x, view.global_position.y, world.z)
			best_d = d
			best = {"pos": floor_at - Basis.from_euler(Vector3(0, rot, 0)) * Vector3(infeed.x, 0, infeed.z),
				"rot": rot, "note": "fed from %s" % name_}
	return best


## Where a new part of this type takes its vials, in its own space, at
## its default size.
static func _infeed_local(type_id: String) -> Vector3:
	match type_id:
		"vial_track":
			return Vector3(-1.0, VialPartView.DECK, 0)
		"star_wheel":
			return StarWheelView.station_point(0.12, 6, 0.0)
		"vial_table":
			return Vector3(-VialTableView.RADIUS - 0.05, VialPartView.DECK, 0)
	return Vector3.ZERO
