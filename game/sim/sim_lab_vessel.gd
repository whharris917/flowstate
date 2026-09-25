class_name SimLabVessel
extends SimComponent
## A beaker, flask, sample vial or reagent bottle and what is in it.
## Mirrors sim/bench.py LabVessel.
##
## It has no ports: it is carried and poured by hand. Whatever it stands
## on acts on it: a hotplate sets heat_w and mix each scan, and the plant
## clears them when the vessel leaves the plate.

const GLASS_CP := 0.84        # J/(g K)
const H_SURFACE := 15.0       # W/(m2 K), still air plus radiation off a warm vessel
const GAS_ML_PER_MOL := 24465.0

## kind -> [reference capacity mL, diameter m, height m, glass g] at that
## capacity; another capacity scales the size by the cube root and the
## glass by the area.
const SHAPES := {
	"beaker": [250.0, 0.070, 0.095, 100.0],
	"flask": [250.0, 0.085, 0.145, 110.0],
	"vial": [20.0, 0.0275, 0.057, 12.0],
	"bottle": [1000.0, 0.101, 0.220, 420.0],
}

var kind := "beaker"
var capacity_ml := 250.0
var stock := ""
var diameter_m := 0.07
var height_m := 0.095
var tare_g := 100.0
var contents: SimMixture
var heat_w := 0.0
var mix := SimMixture.UNSTIRRED


func _init(name_: String, kind_: String = "beaker", capacity_ml_: float = 250.0,
		stock_: String = "") -> void:
	super(name_)
	assert(SHAPES.has(kind_), "unknown vessel kind %s" % kind_)
	kind = kind_
	stock = stock_
	if stock != "" and capacity_ml_ <= 0.0:
		capacity_ml_ = float(ChemLibrary.stock(stock).get("capacity_ml", 500.0))
	resize(capacity_ml_)
	contents = SimMixture.from_stock(stock) if stock != "" else SimMixture.new()
	add_observable("temp_c", &"temp_c")
	add_observable("volume_ml", &"volume_ml")
	add_observable("mass_g", &"mass_g")
	add_observable("gas_ml_s", &"gas_ml_s")
	add_observable("boil_g_s", &"boil_g_s")


var temp_c: float:
	get:
		return contents.temp_c

var volume_ml: float:
	get:
		return contents.volume_ml()

var mass_g: float:
	get:
		return contents.mass_g()

var gas_ml_s: float:
	get:
		return contents.gas_mol_s * GAS_ML_PER_MOL

var boil_g_s: float:
	get:
		return contents.boil_g_s


## Its size and so its shape and glass: the size scales the reference
## shape by the cube root, the glass by the area. What is in it stays.
func resize(capacity_ml_: float) -> void:
	capacity_ml = capacity_ml_
	var shape: Array = SHAPES[kind]
	var scale := pow(capacity_ml / float(shape[0]), 1.0 / 3.0)
	diameter_m = float(shape[1]) * scale
	height_m = float(shape[2]) * scale
	tare_g = float(shape[3]) * scale * scale


func room_ml() -> float:
	return maxf(capacity_ml - volume_ml, 0.0)


## Loss to the room through the wetted wall and the open top.
func ua_w_k() -> float:
	var area_top := PI * diameter_m * diameter_m / 4.0
	var fill := minf(volume_ml / maxf(capacity_ml, 1e-9), 1.0)
	var area_wall := PI * diameter_m * height_m * fill
	return H_SURFACE * (area_top + area_wall)


## The label a bottle carries, or "" for a vessel the player filled.
func label_text() -> String:
	if stock == "":
		return ""
	return str(ChemLibrary.stock(stock).get("label", stock))


func tick(dt: float) -> void:
	contents.step(dt, heat_w, mix, ua_w_k(), tare_g * GLASS_CP)


## Pour amount (mL of liquid, or g when the source holds only solid) from
## src into dst, as far as dst has room. An unstirred source decants: its
## settled solid stays behind. Returns what moved, in the amount's unit.
static func pour(src: SimLabVessel, dst: SimLabVessel, amount: float, stirred: bool) -> float:
	var liquid_ml := src.contents.liquid_ml()
	var part: SimMixture
	var want := 0.0
	if liquid_ml > 1e-6:
		want = minf(minf(amount, liquid_ml), dst.room_ml())
		var frac := want / liquid_ml
		part = src.contents.take(frac, frac if stirred else 0.0)
	else:
		var solid_g := src.contents.mass_g()
		if solid_g <= 1e-9:
			return 0.0
		var room_g := dst.room_ml() * 1.5   # a powder packs at roughly this density
		want = minf(minf(amount, solid_g), room_g)
		part = src.contents.take(0.0, want / solid_g)
	dst.contents.add(part)
	return want


## Whether the vessel holds nothing but solid, so a pour is weighed in
## grams rather than measured in millilitres.
func pours_by_weight() -> bool:
	return contents.liquid_ml() <= 1e-6 and contents.mass_g() > 1e-9


func state_dict() -> Dictionary:
	return {"contents": contents.to_dict()}


func apply_state(state: Dictionary) -> void:
	if state.has("contents"):
		contents = SimMixture.from_dict(state["contents"])
