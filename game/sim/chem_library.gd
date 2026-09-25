class_name ChemLibrary
extends RefCounted
## The bench chemistry library: species, reactions, acid families and
## the reagent stocks the hold supplies. Mirrors sim/chemistry.py; both
## read game/data/chemistry.json, which is hand-authored.
##
## Species are addressed by index in the file's order; save files carry
## keys. Properties sit in packed arrays for the mixture's inner loops.

const DATA := "res://data/chemistry.json"
const R := 8.314
const ATM_KPA := 101.325
const KW := 1.0e-14

enum Phase { LIQUID, SOLID, DISSOLVED, GAS }

static var _loaded := false
static var keys: PackedStringArray = []
static var names: PackedStringArray = []
static var formulas: PackedStringArray = []
static var notes: PackedStringArray = []
static var hazards: PackedStringArray = []
static var phase: PackedInt32Array = []
static var water_solvent: PackedByteArray = []   # 1: counts as water; 0: organic
static var molar_mass: PackedFloat64Array = []
static var density: PackedFloat64Array = []
static var cp: PackedFloat64Array = []
static var bp: PackedFloat64Array = []
static var mp: PackedFloat64Array = []
static var dh_vap: PackedFloat64Array = []
static var dh_solution: PackedFloat64Array = []
static var sol_water: Array[Vector2] = []     # g/100 g at 20 and 80 C
static var sol_organic: Array[Vector2] = []
static var family: PackedInt32Array = []      # index into families, -1 none
static var strong_cations: PackedFloat64Array = []
static var strong_anions: PackedFloat64Array = []
static var color: Array[Color] = []           # a = absorbance per mol/L; 0 colourless
static var solid_color: Array[Color] = []
static var indicator: Array[Dictionary] = []

static var family_keys: PackedStringArray = []
static var family_pka: Array[PackedFloat64Array] = []
static var family_z_base: PackedFloat64Array = []

## Each: {key, name, equation, reactants {i: nu}, products {i: nu}, fast,
## k25, ea, orders {i: order}, catalysts {i: order}, h_order,
## equilibrium (0 none), solid_reactants {i: true}, dh, multi}
static var reactions: Array[Dictionary] = []
## Each: {key, label, capacity_ml, grams {species key: g}}
static var stocks: Array[Dictionary] = []

static var _index: Dictionary = {}
static var _stock_index: Dictionary = {}


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var json := load(DATA) as JSON
	var data: Dictionary = json.data
	var fam: Dictionary = data["families"]
	for key: String in fam:
		family_keys.append(key)
		var entry: Dictionary = fam[key]
		family_pka.append(PackedFloat64Array(entry["pka"]))
		family_z_base.append(float(entry["z_base"]))
	for d: Dictionary in data["species"]:
		var i := keys.size()
		_index[str(d["key"])] = i
		keys.append(str(d["key"]))
		names.append(str(d["name"]))
		formulas.append(str(d.get("formula", "")))
		notes.append(str(d.get("notes", "")))
		hazards.append(str(d.get("hazard", "")))
		var ph_name := str(d["phase"])
		phase.append({"liquid": Phase.LIQUID, "solid": Phase.SOLID, "dissolved": Phase.DISSOLVED,
			"gas": Phase.GAS}[ph_name])
		water_solvent.append(1 if str(d.get("solvent", "organic")) == "water" else 0)
		molar_mass.append(float(d["molar_mass"]))
		density.append(float(d["density"]))
		cp.append(float(d.get("cp", 2.0)))
		bp.append(float(d.get("bp", 100.0)))
		mp.append(float(d.get("mp", 0.0)))
		dh_vap.append(float(d.get("dh_vap", 40.0)))
		dh_solution.append(float(d.get("dh_solution", 0.0)))
		var sol: Dictionary = d.get("solubility", {})
		var sw: Array = sol.get("water", [0.0, 0.0])
		var so: Array = sol.get("organic", [0.0, 0.0])
		sol_water.append(Vector2(float(sw[0]), float(sw[1])))
		sol_organic.append(Vector2(float(so[0]), float(so[1])))
		family.append(family_keys.find(str(d.get("family", ""))) if d.has("family") else -1)
		strong_cations.append(float(d.get("strong_cations", 0.0)))
		strong_anions.append(float(d.get("strong_anions", 0.0)))
		color.append(_color(d.get("color", null)))
		solid_color.append(_color(d.get("solid_color", null), Color(0.95, 0.95, 0.94, 1.0)))
		indicator.append(d.get("indicator", {}))
	for d: Dictionary in data["reactions"]:
		var r := {
			"key": str(d["key"]), "name": str(d["name"]), "equation": str(d.get("equation", "")),
			"reactants": _indexed(d["reactants"]), "products": _indexed(d["products"]),
			"fast": bool(d.get("fast", false)), "k25": float(d.get("k25", 0.0)),
			"ea": float(d.get("ea", 0.0)), "orders": _indexed(d.get("orders", {})),
			"catalysts": _indexed(d.get("catalysts", {})), "h_order": float(d.get("h_order", 0.0)),
			"equilibrium": float(d.get("equilibrium", 0.0)), "dh": float(d.get("dh", 0.0)),
			"solid_reactants": {},
		}
		for key: String in d.get("solid_reactants", []):
			(r["solid_reactants"] as Dictionary)[_index[key]] = true
		# Only reactions between separate substances wait on stirring.
		r["multi"] = (r["reactants"] as Dictionary).size() > 1 or not (r["catalysts"] as Dictionary).is_empty()
		reactions.append(r)
	for d: Dictionary in data["stocks"]:
		_stock_index[str(d["key"])] = stocks.size()
		stocks.append({"key": str(d["key"]), "label": str(d["label"]),
			"capacity_ml": float(d["capacity_ml"]), "grams": d["grams"]})


static func _indexed(by_key: Dictionary) -> Dictionary:
	var out := {}
	for key: String in by_key:
		out[_index[key]] = float(by_key[key])
	return out


static func _color(value: Variant, fallback: Color = Color(0, 0, 0, 0)) -> Color:
	if value == null:
		return fallback
	var a: Array = value
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)


static func count() -> int:
	ensure()
	return keys.size()


static func index_of(key: String) -> int:
	ensure()
	return int(_index.get(key, -1))


static func stock(key: String) -> Dictionary:
	ensure()
	return stocks[int(_stock_index[key])] if _stock_index.has(key) else {}


static func stock_keys() -> PackedStringArray:
	ensure()
	var out := PackedStringArray()
	for s: Dictionary in stocks:
		out.append(str(s["key"]))
	return out


## Only a liquid boils off; a dissolved gas or salt stays.
static func volatile(i: int) -> bool:
	return phase[i] == Phase.LIQUID


static func vapour_kpa(i: int, temp_c: float) -> float:
	var t := temp_c + 273.15
	var tb := bp[i] + 273.15
	return ATM_KPA * exp(-dh_vap[i] * 1000.0 / R * (1.0 / t - 1.0 / tb))


static func _interp(pair: Vector2, temp_c: float) -> float:
	var a := log(maxf(pair.x, 1e-9))
	var b := log(maxf(pair.y, 1e-9))
	var f := (clampf(temp_c, 0.0, 100.0) - 20.0) / 60.0
	return exp(a + (b - a) * f)


## Grams per 100 g of solvent that is water_frac water by mass, the rest
## organic: log-linear in temperature and in the solvent's make-up.
static func solubility(i: int, temp_c: float, water_frac: float) -> float:
	var lw := log(_interp(sol_water[i], temp_c))
	var lo := log(_interp(sol_organic[i], temp_c))
	return exp(water_frac * lw + (1.0 - water_frac) * lo)


static func rate_constant(r: Dictionary, temp_c: float) -> float:
	var t := temp_c + 273.15
	return float(r["k25"]) * exp(-float(r["ea"]) * 1000.0 / R * (1.0 / t - 1.0 / 298.15))


## Mean charge of an acid family at hydrogen ion concentration h: the
## form holding j protons carries charge z_base + j.
static func family_charge(f: int, h: float) -> float:
	var pka := family_pka[f]
	var n := pka.size()
	var weight := 1.0
	var total := 1.0
	var charged := family_z_base[f]
	for j in range(1, n + 1):
		weight *= h / pow(10.0, -pka[n - j])
		total += weight
		charged += (family_z_base[f] + j) * weight
	return charged / total
