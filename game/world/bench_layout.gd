class_name BenchLayout
## The bench's one placement rule, run by the plant whenever a bench
## thing is placed, moved or removed and on a load, and asked by the
## builder for a snapped ghost:
##
##   * a vessel standing on a hotplate's plate (its centre within the
##     plate, its base at the plate's height) is the hotplate's load: the
##     hotplate heats and stirs it and its probe reads it;
##   * a vessel standing on a balance's pan is what the balance weighs;
##   * a vessel standing where a meter's electrode hangs has the
##     electrode in it.
##
## Nothing is kept per layout: move a thing and the rule finds what it
## stands on again (the placement-derived-state rule). Each link is one
## reference, from the instrument to the vessel, so nothing leaks.

const VESSELS: Array[String] = ["lab_beaker", "lab_flask", "lab_vial", "reagent_bottle"]
const TYPES: Array[String] = ["lab_beaker", "lab_flask", "lab_vial", "reagent_bottle",
	"hotplate", "lab_meter", "lab_balance"]
const SEAT_HEIGHT := 0.02   # a vessel's base this near a plate's surface stands on it
const FINE := 0.02          # bench things snap to this grid, not the floor's


static func is_bench_type(type_id: String) -> bool:
	return type_id in TYPES


static func sync(plant: Plant) -> void:
	var vessels: Array[LabVesselView] = []
	var plates: Array[HotplateView] = []
	var meters: Array[LabMeterView] = []
	var balances: Array[LabBalanceView] = []
	for name_: String in plant.views:
		var view: Variant = plant.views[name_]
		if view is LabVesselView:
			vessels.append(view)
		elif view is HotplateView:
			plates.append(view)
		elif view is LabMeterView:
			meters.append(view)
		elif view is LabBalanceView:
			balances.append(view)
	var heated := {}
	for plate in plates:
		var found := _standing_on(vessels, plate, BenchView.HOTPLATE_TOP, BenchView.HOTPLATE_PLATE,
			Vector3(0, 0, 0.03))
		plate.plate.load = found.vessel if found != null else null
		if found != null:
			heated[found] = true
	# A vessel off every plate is neither heated nor stirred.
	for vessel in vessels:
		if not heated.has(vessel):
			vessel.vessel.heat_w = 0.0
			vessel.vessel.mix = SimMixture.UNSTIRRED
	for balance in balances:
		var found := _standing_on(vessels, balance, BenchView.BALANCE_TOP, BenchView.BALANCE_PAN,
			Vector3(0, 0, 0.03))
		balance.balance.load = found.vessel if found != null else null
	for meter in meters:
		var tip := meter.global_transform * BenchView.METER_REACH
		var best: LabVesselView = null
		var best_d := BenchView.METER_CATCH
		for vessel in vessels:
			var gap := Vector2(vessel.global_position.x - tip.x, vessel.global_position.z - tip.z).length()
			var top := vessel.global_position.y + vessel.vessel.height_m
			if gap < best_d and top > tip.y and vessel.global_position.y < tip.y + 0.25:
				best = vessel
				best_d = gap
		meter.meter.target = best.vessel if best != null else null


## The vessel whose base stands on host's surface at `top` above its
## base, centred within `reach` of the surface's centre (offset in the
## host's space).
static func _standing_on(vessels: Array[LabVesselView], host: Node3D, top: float, reach: float,
		offset: Vector3) -> LabVesselView:
	var centre := host.global_transform * (offset + Vector3(0, top, 0))
	var best: LabVesselView = null
	var best_d := reach
	for vessel in vessels:
		var at := vessel.global_position
		if absf(at.y - centre.y) > SEAT_HEIGHT:
			continue
		var gap := Vector2(at.x - centre.x, at.z - centre.z).length()
		if gap <= best_d:
			best = vessel
			best_d = gap
	return best


## Where the builder puts a bench thing aimed at `point` (world, on a
## surface): a vessel aimed near a hotplate's plate or a balance's pan
## sits centred on it; anything else stands where it is aimed, on a fine
## grid. {"pos", "on"} or {"why"} when something is in the way.
## `moving` is a view being carried, left out of the search.
static func snap(plant: Plant, type_id: String, point: Vector3, radius: float,
		moving: Node3D = null) -> Dictionary:
	var pos := Vector3(snappedf(point.x, FINE), point.y, snappedf(point.z, FINE))
	var on := ""
	if type_id in VESSELS:
		for name_: String in plant.views:
			var view: Variant = plant.views[name_]
			if view == moving:
				continue
			var top := -1.0
			var reach := 0.0
			if view is HotplateView:
				top = BenchView.HOTPLATE_TOP
				reach = 0.13
			elif view is LabBalanceView:
				top = BenchView.BALANCE_TOP
				reach = 0.12
			if top < 0.0:
				continue
			var host := view as Node3D
			var centre := host.global_transform * Vector3(0, top, 0.03)
			if Vector2(point.x - centre.x, point.z - centre.z).length() < reach \
					and absf(point.y - host.global_position.y) < 0.3:
				pos = centre
				on = name_
				break
	# Nothing else may stand where it would.
	for name_: String in plant.views:
		var view: Variant = plant.views[name_]
		if view == moving or name_ == on or not view is BenchView:
			continue
		var other := view as BenchView
		if absf(other.global_position.y - pos.y) > 0.3:
			continue
		var gap := Vector2(other.global_position.x - pos.x, other.global_position.z - pos.z).length()
		if gap < other.radius() + radius - 0.01:
			return {"why": "too close to %s" % name_}
	return {"pos": pos, "on": on}


## The footprint's radius a bench type will have, before it exists.
static func radius_of(type_id: String, params: Dictionary = {}) -> float:
	match type_id:
		"hotplate":
			return 0.16
		"lab_meter":
			return 0.11
		"lab_balance":
			return 0.15
		"reagent_bottle":
			var stock := str(params.get("stock", "water"))
			var ml := float(ChemLibrary.stock(stock).get("capacity_ml", 1000.0))
			return 0.101 / 2.0 * pow(ml / 1000.0, 1.0 / 3.0)
		"lab_vial":
			return 0.014
		"lab_flask":
			return 0.085 / 2.0 * pow(float(params.get("capacity_ml", 250.0)) / 250.0, 1.0 / 3.0)
	return 0.070 / 2.0 * pow(float(params.get("capacity_ml", 250.0)) / 250.0, 1.0 / 3.0)
