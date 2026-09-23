class_name SimVialTable
extends SimComponent
## The outfeed: a turntable that gathers finished vials. Where vials
## leave the plant, and the batch record of what was in them -- how many,
## how full, how pure, how many went out uncapped. Mirrors sim/vials.py
## VialTable.

const KEEP := 60   # the last vials, for the view and the record

var count: int = 0
var capped_count: int = 0
var out_l: float = 0.0
var product_l: float = 0.0
var min_ml: float = 0.0
var max_ml: float = 0.0
var recent: Array[SimVial] = []
var infeed: SimInputPort


func _init(name_: String) -> void:
	super(name_)
	infeed = add_input("infeed", SimTypes.PortKind.ITEM)
	add_observable("count", &"count")
	add_observable("capped_count", &"capped_count")
	add_observable("out_l", &"out_l")
	add_observable("mean_ml", &"mean_ml")


var mean_ml: float:
	get:
		return out_l * 1000.0 / count if count > 0 else 0.0


func item_accepts(_port_name: String, _vial: SimVial) -> bool:
	return true


func item_put(_port_name: String, vial: SimVial) -> void:
	var ml := vial.volume_l * 1000.0
	min_ml = ml if count == 0 else minf(min_ml, ml)
	max_ml = ml if count == 0 else maxf(max_ml, ml)
	count += 1
	if vial.capped:
		capped_count += 1
	out_l += vial.volume_l
	product_l += vial.volume_l * vial.contents.frac(SimSpecies.PRODUCT)
	recent.append(vial)
	if recent.size() > KEEP:
		recent.pop_front()


func tick(_dt: float) -> void:
	pass


func state_dict() -> Dictionary:
	var saved: Array = []
	for vial in recent:
		saved.append(vial.to_dict())
	return {"count": count, "capped_count": capped_count, "out_l": out_l, "product_l": product_l,
		"min_ml": min_ml, "max_ml": max_ml, "recent": saved}


func apply_state(state: Dictionary) -> void:
	count = int(state.get("count", count))
	capped_count = int(state.get("capped_count", capped_count))
	out_l = float(state.get("out_l", out_l))
	product_l = float(state.get("product_l", product_l))
	min_ml = float(state.get("min_ml", min_ml))
	max_ml = float(state.get("max_ml", max_ml))
	recent.clear()
	for data: Dictionary in state.get("recent", []):
		recent.append(SimVial.from_dict(data))
