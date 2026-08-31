class_name SimSpecies
## The species this plant handles, and the few physical properties the
## unit operations actually consult. Mirrors sim/species.py.
##
## Deliberately shallow: a heat capacity for energy balances, a boiling
## point for the still and the bubble-point clamp, and a linear
## solubility curve for the crystallizer. No activity model, no VLE.
##
## Species are addressed by *index*, not by name, so a stream can carry
## its composition as a fixed-size PackedFloat32Array instead of a
## Dictionary — no allocation per lookup and no string hashing in the
## tick loop.

const COUNT := 6

const WATER := 0
const SOLVENT := 1
const REAGENT_A := 2
const REAGENT_B := 3
const PRODUCT := 4
const IMPURITY := 5

## Which species suspended solids are made of. One crystallizing
## species keeps the phase split to a single number on the stream.
const SOLID := PRODUCT

static var KEYS := PackedStringArray([
	"water", "solvent", "reagent_a", "reagent_b", "product", "impurity",
])

static var LABELS := PackedStringArray([
	"Water", "Solvent", "Reagent A", "Reagent B", "Product", "Impurity",
])

static var CP_KJ_PER_KG_K := PackedFloat32Array([4.18, 1.70, 2.10, 2.00, 2.20, 2.00])

## The impurity is a heavy on purpose: if it boiled off easily the
## reactor would strip itself clean and the selectivity trade would
## vanish. It has to be separated, not evaporated.
static var BOIL_C := PackedFloat32Array([100.0, 111.0, 205.0, 220.0, 320.0, 280.0])

static var SOL_G_PER_L_20 := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 40.0, 300.0])
static var SOL_SLOPE_G_PER_L_K := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 6.0, 4.0])

static var _index_by_key: Dictionary = {}


static func index_of(key: String) -> int:
	if _index_by_key.is_empty():
		for i in COUNT:
			_index_by_key[KEYS[i]] = i
	return int(_index_by_key.get(key, -1))


static func key_of(index: int) -> String:
	return KEYS[index] if index >= 0 and index < COUNT else ""


static func label_of(index: int) -> String:
	return LABELS[index] if index >= 0 and index < COUNT else ""


static func cp_of(index: int) -> float:
	return CP_KJ_PER_KG_K[index]


static func boil_of(index: int) -> float:
	return BOIL_C[index]


## Linear solubility curve, floored at zero:
##     S(T) = S20 + m * (T - 20)
## Crude on purpose. It gives the crystallizer an honest, legible
## driving force without pretending to be a real solubility model.
static func solubility_g_per_l(index: int, temp_c: float) -> float:
	return maxf(SOL_G_PER_L_20[index] + SOL_SLOPE_G_PER_L_K[index] * (temp_c - 20.0), 0.0)
