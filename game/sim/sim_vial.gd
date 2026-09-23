class_name SimVial
## One vial: glass of a standard size and whatever has been put in it
## (2026-09-22, the filling line). Pure data; the carrier holding it
## decides where it is. Mirrors sim/vials.py Vial.

## Standard tubular vials: nominal mL -> [outer diameter m, height m,
## brimful mL, glass mass g]. ISO 8362 R-sizes, rounded.
const SIZES := {
	2: [0.016, 0.035, 4.0, 3.5],
	10: [0.024, 0.045, 13.5, 8.0],
	20: [0.030, 0.055, 26.0, 13.0],
	50: [0.042, 0.073, 62.0, 30.0],
}

var serial: String
var nominal_ml: int
var diameter_m: float
var height_m: float
var brim_l: float
var tare_g: float
var contents: SimStream = SimStream.empty()   # its flow_lps holds the volume, L
var capped: bool = false


## The standard size nearest a nominal volume.
static func size_of(ml: float) -> int:
	var best := 10
	for key: int in SIZES:
		if absf(key - ml) < absf(best - ml):
			best = key
	return best


func _init(serial_: String = "", ml: float = 10.0) -> void:
	serial = serial_
	nominal_ml = size_of(ml)
	var row: Array = SIZES[nominal_ml]
	diameter_m = row[0]
	height_m = row[1]
	brim_l = float(row[2]) / 1000.0
	tare_g = row[3]


var volume_l: float:
	get:
		return contents.flow_lps


var room_l: float:
	get:
		return maxf(brim_l - volume_l, 0.0)


## Glass plus liquid, on the 1 kg/L basis the species table uses.
var mass_g: float:
	get:
		return tare_g + volume_l * 1000.0


## Pour litres of that stream in; returns what ran over the lip.
func add(stream: SimStream, litres: float) -> float:
	var taken := minf(maxf(litres, 0.0), room_l)
	if taken > 0.0:
		contents = SimStream.mix(contents, stream.with_flow(taken))
	return maxf(litres, 0.0) - taken


func to_dict() -> Dictionary:
	return {"serial": serial, "ml": nominal_ml, "capped": capped, "contents": contents.to_dict()}


static func from_dict(data: Dictionary) -> SimVial:
	var vial := SimVial.new(str(data.get("serial", "")), float(data.get("ml", 10)))
	vial.capped = bool(data.get("capped", false))
	if data.has("contents"):
		vial.contents = SimStream.from_dict(data["contents"])
	return vial
