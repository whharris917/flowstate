class_name SimBalance
## Material accounting by unit, from the records' own meters, so a
## screen can show it live for any unit. Fed is what crossed the plant
## boundary inward: headers, the transfer lock's condensate, and the
## steam drum's makeup (the known gap, counted rather than hidden). Out
## is what crossed it outward: drains, vials, dryer vapour, reactor
## boil-off and overflows. Held is what stands in vessels. Nothing here
## is an integral a display keeps for itself; every number is a record's
## own meter, so a screen, the probe and a saved game agree.
##
## Units are read off tag numbers: t_403 and supply_401 are Unit 400,
## r_301 and vf_310 are Unit 300; a name without a three-digit tag is
## the home loop.

const HOME := 0
## Records the naming rule would file wrongly: the home loop's drain
## was numbered before the units were, and two of Unit 300's headers
## are named for their service rather than their unit.
const UNIT_OVERRIDES := {"du_100": 0, "supply_bfw": 300, "supply_solv": 300}

static var _tag_rx: RegEx = null


static func unit_of(name_: String) -> int:
	if UNIT_OVERRIDES.has(name_):
		return int(UNIT_OVERRIDES[name_])
	if _tag_rx == null:
		_tag_rx = RegEx.new()
		_tag_rx.compile("(?<![0-9])([0-9]{3})(?![0-9])")
	var found := _tag_rx.search(name_)
	if found == null:
		return HOME
	@warning_ignore("integer_division")
	return (int(found.get_string(1)) / 100) * 100


static func unit_label(unit: int) -> String:
	return "HOME LOOP" if unit == HOME else "UNIT %d" % unit


## Whether a record holds or meters material for the balance.
static func counts(comp: SimComponent) -> bool:
	return comp is SimSource or comp is SimDrain or comp is SimTank or comp is SimReactor \
		or comp is SimCrystallizer or comp is SimVacuumLock or comp is SimSteamGen \
		or comp is SimDryer or comp is SimVialFiller or comp is SimCap 		or comp is SimCentrifuge or comp is SimStill 		or comp is SimVialCarrier or comp is SimFillNeedle or comp is SimVialTable


## Distinct units with at least one counted record, ascending.
static func units(sim: Simulation) -> Array[int]:
	var seen := {}
	for comp in sim.components:
		if counts(comp):
			seen[unit_of(comp.comp_name)] = true
	var out: Array[int] = []
	for u: Variant in seen:
		out.append(int(u))
	out.sort()
	return out


static func names_in(sim: Simulation, unit: int) -> Array[String]:
	var out: Array[String] = []
	for comp in sim.components:
		if counts(comp) and unit_of(comp.comp_name) == unit:
			out.append(comp.comp_name)
	return out


## {"fed", "out", "held"} in litres for the named records, now.
static func accounts(sim: Simulation, names: Array) -> Dictionary:
	var fed := 0.0
	var out := 0.0
	var held := 0.0
	for name_v: Variant in names:
		var comp := sim.get_component(str(name_v))
		if comp is SimSource:
			fed += (comp as SimSource).total_l
		elif comp is SimVacuumLock:
			# Fed: all it has condensed. Held: what is still in its chamber.
			var lock := comp as SimVacuumLock
			fed += lock.condensed_l
			held += lock.holdup_l
		elif comp is SimSteamGen:
			var sg := comp as SimSteamGen
			fed += sg.steam_total_l - sg.feedwater_total_l
		elif comp is SimTank:
			var t := comp as SimTank
			held += t.level_l
			out += t.overflowed_l
		elif comp is SimReactor:
			var r := comp as SimReactor
			held += r.volume_l
			out += r.boiled_off_l + r.overflowed_l
		elif comp is SimCrystallizer:
			var c := comp as SimCrystallizer
			held += c.volume_l
			out += c.overflowed_l
		elif comp is SimDrain:
			out += (comp as SimDrain).total_l
		elif comp is SimDryer:
			out += (comp as SimDryer).dried_l
			held += (comp as SimDryer).in_flight_l
		elif comp is SimCentrifuge:
			held += (comp as SimCentrifuge).in_flight_l
		elif comp is SimStill:
			held += (comp as SimStill).in_flight_l
		elif comp is SimVialFiller:
			out += (comp as SimVialFiller).filled_l
		elif comp is SimCap:
			# An open end spilling to the ground leaves the plant; what it
			# lands in an open vessel is that vessel's, held.
			out += (comp as SimCap).spilled_l
		elif comp is SimVialCarrier:
			# The liquid in the vials a track or a star wheel carries.
			held += (comp as SimVialCarrier).held_l
		elif comp is SimFillNeedle:
			out += (comp as SimFillNeedle).spilled_l
		elif comp is SimVialTable:
			# Filled vials leave the plant at the outfeed.
			out += (comp as SimVialTable).out_l
	return {"fed": fed, "out": out, "held": held}


## The historian tags behind accounts(), as [tag, factor] pairs per
## side, so a trend can replay the closure sample by sample.
static func tags(sim: Simulation, names: Array) -> Dictionary:
	var fed: Array = []
	var out: Array = []
	var held: Array = []
	for name_v: Variant in names:
		var n := str(name_v)
		var comp := sim.get_component(n)
		if comp is SimSource:
			fed.append([n + ".total_l", 1.0])
		elif comp is SimVacuumLock:
			fed.append([n + ".condensed_l", 1.0])
			held.append([n + ".holdup_l", 1.0])
		elif comp is SimSteamGen:
			fed.append([n + ".steam_total_l", 1.0])
			fed.append([n + ".feedwater_total_l", -1.0])
		elif comp is SimTank:
			held.append([(comp as SimTank).level.path(), 1.0])
			out.append([n + ".overflowed_l", 1.0])
		elif comp is SimReactor:
			held.append([n + ".volume_l", 1.0])
			out.append([n + ".boiled_off_l", 1.0])
			out.append([n + ".overflowed_l", 1.0])
		elif comp is SimCrystallizer:
			held.append([n + ".volume_l", 1.0])
			out.append([n + ".overflowed_l", 1.0])
		elif comp is SimDrain:
			out.append([n + ".total_l", 1.0])
		elif comp is SimDryer:
			out.append([n + ".dried_l", 1.0])
			held.append([n + ".in_flight_l", 1.0])
		elif comp is SimCentrifuge or comp is SimStill:
			held.append([n + ".in_flight_l", 1.0])
		elif comp is SimVialFiller:
			out.append([n + ".filled_l", 1.0])
		elif comp is SimCap or comp is SimFillNeedle:
			out.append([n + ".spilled_l", 1.0])
		elif comp is SimVialCarrier:
			held.append([n + ".held_l", 1.0])
		elif comp is SimVialTable:
			out.append([n + ".out_l", 1.0])
	return {"fed": fed, "out": out, "held": held}


## fed - out - (held - held0): what a closed balance keeps at zero.
static func residual(acc: Dictionary, held0: float) -> float:
	return float(acc["fed"]) - float(acc["out"]) - (float(acc["held"]) - held0)


## Percent of what was fed that is accounted for: the probe's number.
static func closure_pct(acc: Dictionary, held0: float) -> float:
	var fed := float(acc["fed"])
	if fed <= 1e-6:
		return 100.0
	return 100.0 * (float(acc["out"]) + float(acc["held"]) - held0) / fed


## The residual replayed from historian samples: (time, litres) pairs
## from t0 to the last sample, one every `stride` samples.
static func residual_points(historian: SimHistorian, tagset: Dictionary, held0: float,
		t0: float, stride: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if historian == null or historian.sample_count() < 2:
		return points
	var times := historian.time
	var start := times.size() - 1
	while start > 0 and times[start - 1] >= t0:
		start -= 1
	# Each tag's series and start index once, then plain array reads:
	# a historian call per tag per sample is tens of thousands of
	# script calls a redraw.
	var terms: Array = []   # [series, start_index, weight]
	for group: Array in [["fed", 1.0], ["out", -1.0], ["held", -1.0]]:
		for pair: Array in tagset[str(group[0])]:
			var tag := str(pair[0])
			terms.append([historian.series(tag), historian.start_index(tag), float(pair[1]) * float(group[1])])
	var i := start
	while i < times.size():
		var value := held0
		for term: Array in terms:
			var local: int = i - int(term[1])
			var series: PackedFloat64Array = term[0]
			if local >= 0 and local < series.size():
				value += series[local] * float(term[2])
		points.append(Vector2(times[i], value))
		i += maxi(stride, 1)
	return points


## A meter that did not exist yet had metered nothing.
static func _at(historian: SimHistorian, tag: String, index: int) -> float:
	var v := historian.value_at(tag, index)
	return 0.0 if is_nan(v) else v
