class_name CabinetSpec
## Shared geometry and module catalog for control cabinets: three DIN
## rails of SLOTS units each; every module type declares its width,
## look, and what it puts on the rail. The 3D interior and the 2D
## editor both position modules with the same slot math, so what you
## build straight-on is exactly what renders in the enclosure.

const RAILS := 3
const SLOTS := 12
const RAIL_Y: Array[float] = [1.55, 1.05, 0.55]   # cabinet-local rail heights
const RAIL_X0 := -0.53
const UNIT_W := 1.06 / 12.0
const MODULE_H := 0.24
const MODULE_D := 0.12
const DUCT_DROP := 0.22   # wires drop this far below a rail into the duct

const MODULES := {
	"psu": {"label": "PSU 24VDC", "units": 3, "color": Color(0.35, 0.55, 0.40)},
	"plc": {"label": "PLC CPU", "units": 3, "color": Color(0.15, 0.16, 0.20)},
	"card_di": {"label": "DI x8", "units": 2, "color": Color(0.20, 0.38, 0.30)},
	"card_do": {"label": "DO x8", "units": 2, "color": Color(0.42, 0.24, 0.22)},
	"card_ai": {"label": "AI x4", "units": 2, "color": Color(0.22, 0.30, 0.46)},
	"card_ao": {"label": "AO x4", "units": 2, "color": Color(0.46, 0.34, 0.18)},
	"relay": {"label": "Relay", "units": 1, "color": Color(0.85, 0.55, 0.15)},
	"tb8d": {"label": "TB x8 discrete", "units": 4, "color": Color(0.62, 0.63, 0.66)},
	"tb4a": {"label": "TB x4 analog", "units": 3, "color": Color(0.30, 0.40, 0.68)},
}

# How many channels each card backs on the PLC, per family.
const CARD_CHANNELS := {"card_di": 8, "card_do": 8, "card_ai": 4, "card_ao": 4}
const CARD_FAMILY := {"card_di": "di", "card_do": "do", "card_ai": "ai", "card_ao": "ao"}


static func units_of(type_id: String) -> int:
	return int((MODULES.get(type_id, {}) as Dictionary).get("units", 1))


## Cabinet-local center of a module (front face of the rail zone).
static func module_center(rail: int, slot: int, units: int) -> Vector3:
	return Vector3(RAIL_X0 + (slot + units / 2.0) * UNIT_W,
		RAIL_Y[rail] + 0.02, -0.30 + 0.10 + 0.06)


## Does a span of slots fit the rail and avoid existing modules?
static func span_free(modules: Array, rail: int, slot: int, units: int,
		ignore_id: String = "") -> bool:
	if rail < 0 or rail >= RAILS or slot < 0 or slot + units > SLOTS:
		return false
	for module_v: Variant in modules:
		var module := module_v as Dictionary
		if str(module.get("id")) == ignore_id or int(module["rail"]) != rail:
			continue
		var m_slot := int(module["slot"])
		var m_units := units_of(str(module["type"]))
		if slot < m_slot + m_units and m_slot < slot + units:
			return false
	return true
