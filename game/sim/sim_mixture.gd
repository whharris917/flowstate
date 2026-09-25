class_name SimMixture
extends RefCounted
## What a bench vessel holds: moles of each library species, split
## between the liquid (liquids and whatever is dissolved) and the solid
## (undissolved or crystallized), at one temperature. Mirrors
## sim/bench.py Mixture.
##
## Each scan it reacts (every reaction whose reactants are present, at
## its rate law, capped so nothing goes negative and a reversible one
## lands on its equilibrium rather than past it; a fast one as quickly
## as the stirring mixes; a gas product leaves at once), dissolves and
## crystallizes each solid toward its solubility, exchanges heat (the
## hotplate's, the room's, the heats of reaction and of solution), and
## boils: above the mixture's boiling point the surplus heat becomes
## vapour of the Raoult composition, which leaves. What leaves is kept
## in `vented`, so the mass always balances.

const AMBIENT_C := 21.0
const FAST_RATE := 20.0      # 1/s: a fast reaction completes as fast as it is mixed
const K_DISSOLVE := 0.08     # 1/s toward saturation, stirred
const K_CRYSTAL := 0.03      # 1/s toward saturation from above, just past it
const MAX_DRIVE := 20.0      # the most supersaturation speeds crystallizing
const UNSTIRRED := 0.1       # mixing with nothing stirring
const VIEW_PATH_CM := 5.0    # the depth of liquid a look through a vessel crosses

var liquid: PackedFloat64Array
var solid: PackedFloat64Array
var vented: PackedFloat64Array
var temp_c := AMBIENT_C
var gas_mol_s := 0.0     # gas made in the last step, per second
var boil_g_s := 0.0      # vapour boiled off in the last step, per second
var boiling := false


func _init(temp_c_: float = AMBIENT_C) -> void:
	ChemLibrary.ensure()
	var n := ChemLibrary.count()
	liquid.resize(n)
	solid.resize(n)
	vented.resize(n)
	temp_c = temp_c_


## ---- building ---------------------------------------------------------------

func add_grams(key: String, grams: float) -> void:
	var i := ChemLibrary.index_of(key)
	if i < 0:
		return
	var mol := grams / ChemLibrary.molar_mass[i]
	match ChemLibrary.phase[i]:
		ChemLibrary.Phase.SOLID:
			solid[i] += mol
		ChemLibrary.Phase.GAS:
			vented[i] += mol
		_:
			liquid[i] += mol


static func from_stock(stock_key: String, fill: float = 1.0) -> SimMixture:
	var m := SimMixture.new()
	var entry := ChemLibrary.stock(stock_key)
	var grams: Dictionary = entry.get("grams", {})
	for key: String in grams:
		m.add_grams(key, float(grams[key]) * fill)
	m.settle()
	return m


## Each solid species at its equilibrium split at once: a stock solution
## arrives dissolved, a stock powder dry.
func settle() -> void:
	for i in ChemLibrary.count():
		if ChemLibrary.phase[i] != ChemLibrary.Phase.SOLID:
			continue
		var total := liquid[i] + solid[i]
		liquid[i] = minf(total, capacity_mol(i))
		solid[i] = total - liquid[i]


## ---- what it is -------------------------------------------------------------

func mass_g() -> float:
	var g := 0.0
	for i in ChemLibrary.count():
		g += (liquid[i] + solid[i]) * ChemLibrary.molar_mass[i]
	return g


func liquid_ml() -> float:
	var ml := 0.0
	for i in ChemLibrary.count():
		if liquid[i] > 0.0:
			ml += liquid[i] * ChemLibrary.molar_mass[i] / ChemLibrary.density[i]
	return ml


func solid_ml() -> float:
	var ml := 0.0
	for i in ChemLibrary.count():
		if solid[i] > 0.0:
			ml += solid[i] * ChemLibrary.molar_mass[i] / ChemLibrary.density[i]
	return ml


func volume_ml() -> float:
	return liquid_ml() + solid_ml()


## J/K of the contents.
func heat_capacity() -> float:
	var c := 0.0
	for i in ChemLibrary.count():
		c += (liquid[i] + solid[i]) * ChemLibrary.molar_mass[i] * ChemLibrary.cp[i]
	return c


func conc(i: int) -> float:
	var litres := liquid_ml() / 1000.0
	return liquid[i] / litres if litres > 1e-9 else 0.0


func _solvent_g() -> Vector2:
	var water := 0.0
	var organic := 0.0
	for i in ChemLibrary.count():
		if ChemLibrary.phase[i] != ChemLibrary.Phase.LIQUID or liquid[i] <= 0.0:
			continue
		var g := liquid[i] * ChemLibrary.molar_mass[i]
		if ChemLibrary.water_solvent[i] == 1:
			water += g
		else:
			organic += g
	return Vector2(water, organic)


## How much of solid species i the liquid can hold dissolved.
func capacity_mol(i: int) -> float:
	if ChemLibrary.phase[i] != ChemLibrary.Phase.SOLID:
		return INF
	var solvent := _solvent_g()
	var total := solvent.x + solvent.y
	if total <= 1e-9:
		return 0.0
	var grams := total * ChemLibrary.solubility(i, temp_c, solvent.x / total) / 100.0
	return grams / ChemLibrary.molar_mass[i]


func has_water() -> bool:
	var solvent := _solvent_g()
	return solvent.x > 0.01 * (solvent.x + solvent.y) and solvent.x > 1e-6


## By charge balance, or NAN with no water to speak of.
func ph() -> float:
	if not has_water():
		return NAN
	var litres := liquid_ml() / 1000.0
	var cations := 0.0
	var anions := 0.0
	var family_c := PackedFloat64Array()
	family_c.resize(ChemLibrary.family_keys.size())
	for i in ChemLibrary.count():
		if liquid[i] <= 0.0:
			continue
		var c := liquid[i] / litres
		cations += ChemLibrary.strong_cations[i] * c
		anions += ChemLibrary.strong_anions[i] * c
		var f := ChemLibrary.family[i]
		if f >= 0:
			family_c[f] += c
	var lo := -2.0
	var hi := 16.0
	for _k in 60:
		var mid := 0.5 * (lo + hi)
		var h := pow(10.0, -mid)
		var q := h - ChemLibrary.KW / h + cations - anions
		for f in family_c.size():
			if family_c[f] > 0.0:
				q += family_c[f] * ChemLibrary.family_charge(f, h)
		if q > 0.0:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## Where the liquid's vapour pressure reaches one atmosphere, or NAN when
## nothing in it boils.
func boiling_point() -> float:
	var total := 0.0
	for i in ChemLibrary.count():
		total += liquid[i]
	if total <= 1e-12:
		return NAN
	var parts: Array[Vector2] = []   # (mole fraction, species index)
	for i in ChemLibrary.count():
		if ChemLibrary.volatile(i) and liquid[i] > 0.0:
			parts.append(Vector2(liquid[i] / total, i))
	if parts.is_empty():
		return NAN
	if _pressure(parts, 400.0) < ChemLibrary.ATM_KPA:
		return NAN
	var lo := -50.0
	var hi := 400.0
	for _k in 50:
		var mid := 0.5 * (lo + hi)
		if _pressure(parts, mid) < ChemLibrary.ATM_KPA:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func _pressure(parts: Array[Vector2], t: float) -> float:
	var p := 0.0
	for part in parts:
		p += part.x * ChemLibrary.vapour_kpa(int(part.y), t)
	return p


## The colour a look through the liquid shows: each coloured species by
## its absorbance across a vessel (Beer-Lambert over VIEW_PATH_CM), an
## indicator by the pH. Alpha is how much of the view it takes, easing
## toward full as the absorbance passes a few units.
func liquid_color() -> Color:
	var litres := liquid_ml() / 1000.0
	if litres <= 1e-9:
		return Color(0, 0, 0, 0)
	var tint := Color(0.92, 0.95, 0.97, 0.0)
	var strength := 0.0
	var reading := NAN
	for i in ChemLibrary.count():
		if liquid[i] <= 0.0:
			continue
		var c := ChemLibrary.color[i]
		var ind: Dictionary = ChemLibrary.indicator[i]
		if not ind.is_empty():
			if is_nan(reading):
				reading = ph()
			if is_nan(reading):
				continue
			var span: float = float(ind["to_ph"]) - float(ind["from_ph"])
			var on := clampf((reading - float(ind["from_ph"])) / span, 0.0, 1.0)
			var ic: Array = ind["color"]
			c = Color(float(ic[0]), float(ic[1]), float(ic[2]), float(ic[3]) * on)
		if c.a <= 0.0:
			continue
		var absorb := 1.0 - exp(-c.a * liquid[i] / litres * VIEW_PATH_CM / 3.0)
		tint = tint.lerp(Color(c.r, c.g, c.b), absorb / maxf(strength + absorb, 1e-9))
		strength = minf(strength + absorb, 1.0)
	tint.a = strength
	return tint


## The colour of what has settled or is suspended, weighted by volume.
func solid_color() -> Color:
	var total := 0.0
	var mixed := Color(0, 0, 0)
	for i in ChemLibrary.count():
		if solid[i] <= 0.0:
			continue
		var ml := solid[i] * ChemLibrary.molar_mass[i] / ChemLibrary.density[i]
		var c := ChemLibrary.solid_color[i]
		mixed += Color(c.r * ml, c.g * ml, c.b * ml)
		total += ml
	if total <= 0.0:
		return Color(0.95, 0.95, 0.94)
	return Color(mixed.r / total, mixed.g / total, mixed.b / total)


## ---- moving it --------------------------------------------------------------

## Remove those fractions of the liquid and the solid; return them.
func take(liquid_frac: float, solid_frac: float) -> SimMixture:
	var out := SimMixture.new(temp_c)
	var lf := clampf(liquid_frac, 0.0, 1.0)
	var sf := clampf(solid_frac, 0.0, 1.0)
	for i in ChemLibrary.count():
		out.liquid[i] = liquid[i] * lf
		out.solid[i] = solid[i] * sf
		liquid[i] -= out.liquid[i]
		solid[i] -= out.solid[i]
	return out


## Pour other in; the temperature is the heat-capacity blend.
func add(other: SimMixture) -> void:
	var c_self := heat_capacity()
	var c_other := other.heat_capacity()
	if c_self + c_other > 0.0:
		temp_c = (temp_c * c_self + other.temp_c * c_other) / (c_self + c_other)
	for i in ChemLibrary.count():
		liquid[i] += other.liquid[i]
		solid[i] += other.solid[i]


## ---- a scan -----------------------------------------------------------------

func step(dt: float, heat_w: float = 0.0, mix: float = UNSTIRRED, ua_w_k: float = 0.0,
		extra_cp_j_k: float = 0.0, ambient_c: float = AMBIENT_C) -> void:
	var reacted := _react(dt, mix)
	var heat_j := reacted.x + _dissolve(dt, mix)
	var c := heat_capacity() + extra_cp_j_k
	if c > 1e-9:
		temp_c += (heat_j + (heat_w - ua_w_k * (temp_c - ambient_c)) * dt) / c
	gas_mol_s = reacted.y / dt if dt > 0.0 else 0.0
	boil_g_s = _boil(c) / dt if dt > 0.0 else 0.0


## Returns (heat released J, gas made mol).
func _react(dt: float, mix: float) -> Vector2:
	var heat := 0.0
	var gas := 0.0
	var litres := liquid_ml() / 1000.0
	if litres <= 1e-9:
		return Vector2.ZERO
	var h := -1.0   # found once, and only when an acid-catalysed reaction can run
	for r: Dictionary in ChemLibrary.reactions:
		var reactants: Dictionary = r["reactants"]
		var products: Dictionary = r["products"]
		var forward := true
		for i: int in reactants:
			if _available(r, i) <= 0.0:
				forward = false
				break
		var backward := float(r["equilibrium"]) > 0.0
		if backward:
			for i: int in products:
				if liquid[i] <= 0.0:
					backward = false
					break
		if not forward and not backward:
			continue
		if float(r["h_order"]) != 0.0 and h < 0.0:
			var reading := ph()
			h = pow(10.0, -reading) if not is_nan(reading) else 0.0
		var extent := _extent(r, dt, mix, litres, maxf(h, 0.0))
		if extent == 0.0:
			continue
		var solids: Dictionary = r["solid_reactants"]
		for i: int in reactants:
			if solids.has(i):
				solid[i] = maxf(solid[i] - float(reactants[i]) * extent, 0.0)
			else:
				liquid[i] = maxf(liquid[i] - float(reactants[i]) * extent, 0.0)
		for i: int in products:
			var made := float(products[i]) * extent
			if ChemLibrary.phase[i] == ChemLibrary.Phase.GAS:
				vented[i] += made
				gas += made
			else:
				liquid[i] = maxf(liquid[i] + made, 0.0)
		heat += -float(r["dh"]) * 1000.0 * extent
	return Vector2(heat, gas)


func _available(r: Dictionary, i: int) -> float:
	return solid[i] if (r["solid_reactants"] as Dictionary).has(i) else liquid[i]


func _extent(r: Dictionary, dt: float, mix: float, litres: float, h: float) -> float:
	var reactants: Dictionary = r["reactants"]
	var products: Dictionary = r["products"]
	var forward_room := INF
	for i: int in reactants:
		forward_room = minf(forward_room, _available(r, i) / float(reactants[i]))
	if bool(r["fast"]):
		if forward_room <= 0.0:
			return 0.0
		return forward_room * (1.0 - exp(-FAST_RATE * mix * dt))
	var k := ChemLibrary.rate_constant(r, temp_c)
	var h_order := float(r["h_order"])
	var acid := pow(h, h_order) if h_order != 0.0 else 1.0
	var rate := k * acid
	var orders: Dictionary = r["orders"]
	for i: int in orders:
		rate *= pow(_available(r, i) / litres, float(orders[i]))
	var catalysts: Dictionary = r["catalysts"]
	for i: int in catalysts:
		rate *= pow(liquid[i] / litres, float(catalysts[i]))
	var multi := bool(r["multi"])
	if multi:
		rate *= mix
	var equilibrium := float(r["equilibrium"])
	if equilibrium <= 0.0:
		return minf(rate * litres * dt, forward_room * 0.999)
	# Reversible: the reverse rate from the equilibrium constant, and a
	# step that would cross equilibrium lands on it instead.
	var back := k * acid / equilibrium
	for i: int in products:
		back *= liquid[i] / litres
	if multi:
		back *= mix
	var extent := (rate - back) * litres * dt
	var reverse_room := INF
	for i: int in products:
		reverse_room = minf(reverse_room, liquid[i] / float(products[i]))
	extent = clampf(extent, -reverse_room * 0.999, forward_room * 0.999)
	var gap_now := _quotient_gap(r, 0.0, litres)
	var gap_new := _quotient_gap(r, extent, litres)
	if (gap_now > 0.0) != (gap_new > 0.0):
		var lo := 0.0
		var hi := extent
		for _k in 30:
			var mid := 0.5 * (lo + hi)
			if (_quotient_gap(r, mid, litres) > 0.0) == (gap_now > 0.0):
				lo = mid
			else:
				hi = mid
		extent = lo
	return extent


## log(Q / K) after advancing by extent; positive past equilibrium.
func _quotient_gap(r: Dictionary, extent: float, litres: float) -> float:
	var reactants: Dictionary = r["reactants"]
	var products: Dictionary = r["products"]
	var num := 0.0
	var den := 0.0
	for i: int in products:
		var c := (liquid[i] + float(products[i]) * extent) / litres
		if c <= 0.0:
			return -INF
		num += float(products[i]) * log(c)
	for i: int in reactants:
		var c := (_available(r, i) - float(reactants[i]) * extent) / litres
		if c <= 0.0:
			return INF
		den += float(reactants[i]) * log(c)
	return num - den - log(float(r["equilibrium"]))


func _dissolve(dt: float, mix: float) -> float:
	var heat := 0.0
	var stirred := clampf(mix, 0.0, 1.0)
	for i in ChemLibrary.count():
		if ChemLibrary.phase[i] != ChemLibrary.Phase.SOLID:
			continue
		if liquid[i] <= 0.0 and solid[i] <= 0.0:
			continue
		var cap := capacity_mol(i)
		var d := liquid[i]
		var moved := 0.0
		if solid[i] > 0.0 and d < cap:
			moved = minf(solid[i], (cap - d) * (1.0 - exp(-K_DISSOLVE * stirred * dt)))
		elif d > cap:
			# The further past saturation, the faster it comes out: an
			# insoluble salt drops at once, a cooled solution slowly.
			var drive := 1.0 + log(d / cap) if cap > 0.0 else MAX_DRIVE
			moved = -(d - cap) * (1.0 - exp(-K_CRYSTAL * minf(drive, MAX_DRIVE) * dt))
		else:
			continue
		liquid[i] += moved
		solid[i] -= moved
		if solid[i] < 1e-15:
			solid[i] = 0.0
		heat += -ChemLibrary.dh_solution[i] * 1000.0 * moved
	return heat


## Boil off what is above the boiling point; returns grams.
func _boil(c: float) -> float:
	boiling = false
	# An ideal mixture boils no lower than its lightest part does.
	var lightest := INF
	for i in ChemLibrary.count():
		if ChemLibrary.volatile(i) and liquid[i] > 0.0:
			lightest = minf(lightest, ChemLibrary.bp[i])
	if temp_c <= lightest:
		return 0.0
	var tb := boiling_point()
	if is_nan(tb) or temp_c <= tb:
		return 0.0
	var total := 0.0
	for i in ChemLibrary.count():
		total += liquid[i]
	var pressures := {}
	var p_sum := 0.0
	for i in ChemLibrary.count():
		if ChemLibrary.volatile(i) and liquid[i] > 0.0:
			var p := liquid[i] / total * ChemLibrary.vapour_kpa(i, tb)
			pressures[i] = p
			p_sum += p
	if p_sum <= 0.0:
		return 0.0
	var latent := 0.0
	for i: int in pressures:
		latent += float(pressures[i]) / p_sum * ChemLibrary.dh_vap[i] * 1000.0
	var moles := (temp_c - tb) * c / latent
	var grams := 0.0
	for i: int in pressures:
		var gone := minf(moles * float(pressures[i]) / p_sum, liquid[i])
		liquid[i] -= gone
		vented[i] += gone
		grams += gone * ChemLibrary.molar_mass[i]
	temp_c = tb
	boiling = grams > 0.0
	return grams


## ---- save -------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {"temp_c": temp_c, "liquid": {}, "solid": {}, "vented": {}}
	for i in ChemLibrary.count():
		var key := ChemLibrary.keys[i]
		if liquid[i] != 0.0:
			(out["liquid"] as Dictionary)[key] = liquid[i]
		if solid[i] != 0.0:
			(out["solid"] as Dictionary)[key] = solid[i]
		if vented[i] != 0.0:
			(out["vented"] as Dictionary)[key] = vented[i]
	return out


static func from_dict(d: Dictionary) -> SimMixture:
	var m := SimMixture.new(float(d.get("temp_c", AMBIENT_C)))
	for pool: String in ["liquid", "solid", "vented"]:
		var values: Dictionary = d.get(pool, {})
		for key: String in values:
			var i := ChemLibrary.index_of(key)
			if i < 0:
				continue
			match pool:
				"liquid":
					m.liquid[i] = float(values[key])
				"solid":
					m.solid[i] = float(values[key])
				_:
					m.vented[i] = float(values[key])
	return m
