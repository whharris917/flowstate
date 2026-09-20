class_name Milestones
extends RefCounted
## The campaign ladder (director, 2026-09-11: the general gameplay of
## Satisfactory). A milestone is something the plant itself proves,
## read off live records and their own totalizers — never a flag the
## player can set — and each one completed unlocks build-menu types,
## tier by tier along the GDD's history of industrial control.
## Structure, routing and signs are never gated: the frame can always
## be built. Trackers that need memory (litres a pump has moved, how
## long a loop has held setpoint) are integrated here from sim time
## and saved with the plant.
## The briefs are player-facing prose: drafts for the director's
## editorial review, like the library pages.

## Tier 0 by hand: vessels, headers, sewers, and a valve you turn yourself.
const BASE_TYPES: Array[String] = ["tank", "source", "drain", "block_valve", "tee_split", "tee_mix", "cap"]

const LADDER: Array[Dictionary] = [
	{
		"id": "first_water", "tier": "TIER 0 — MANUAL", "title": "First water",
		"brief": "A header, a vessel, a sewer, and a valve you turn by hand. Put a line between them and let pressure do the work: nothing in this plant is ever told how fast to flow.",
		"requires": [
			{"kind": "placed", "type": "source", "n": 1, "label": "a supply header placed"},
			{"kind": "placed", "type": "tank", "n": 1, "label": "a tank placed"},
			{"kind": "placed", "type": "drain", "n": 1, "label": "a drain placed"},
			{"kind": "header_total", "target": 200.0, "label": "drawn from headers", "unit": "L"},
			{"kind": "sewer_total", "target": 100.0, "label": "sent to the sewer", "unit": "L"},
		],
		"unlocks": ["mains", "psu", "pump"],
	},
	{
		"id": "lift", "tier": "TIER 0 — POWER", "title": "Lift",
		"brief": "Gravity only runs downhill. A feeder, a supply and a pump put head into the line; a tank on a deck is where that head goes.",
		"requires": [
			{"kind": "pumped", "target": 300.0, "label": "moved by a pump", "unit": "L"},
			{"kind": "raised_tank", "elev": 2.5, "target": 200.0, "label": "held in a tank 2.5 m up", "unit": "L"},
		],
		"unlocks": ["float_switch", "relay", "orifice", "needle_valve", "ball_valve", "rotameter", "regulator"],
	},
	{
		"id": "hands_off", "tier": "TIER 1 — HARDWIRED RELAY", "title": "Hands off",
		"brief": "You cannot stand at the switch forever. A float switch on the shell and a relay on the pump make the first decision you never have to make again.",
		"requires": [
			{"kind": "relay_cycles", "target": 5.0, "label": "relay cycles", "unit": ""},
		],
		"unlocks": ["cabinet", "junction_box", "control_station", "gauge_flow", "gauge_level",
			"solenoid_valve", "metering_pump"],
	},
	{
		"id": "sequence", "tier": "TIER 3 — PLC", "title": "Sequence",
		"brief": "Relays sprawl. A cabinet with a PLC replaces the panel with a program: rungs you can read, timers you can trust.",
		"requires": [
			{"kind": "plc_scans", "rungs": 3, "target": 1200.0, "label": "scans of a program with 3 rungs", "unit": ""},
		],
		"unlocks": ["controller", "valve", "gauge_press", "gauge_temp", "gauge_dp"],
	},
	{
		"id": "hold_the_line", "tier": "TIER 4 — ANALOG & PID", "title": "Hold the line",
		"brief": "On-off control oscillates. A transmitter, a control valve and a PID in AUTO hold a value instead of chasing it.",
		"requires": [
			{"kind": "pid_hold", "target": 60.0, "label": "a loop in AUTO within 3 % of setpoint", "unit": "s"},
		],
		"unlocks": ["hmi_trend", "hx", "steamgen", "reactor", "crystallizer"],
	},
	{
		"id": "make_something", "tier": "TIER 4 — REACTION", "title": "Make something",
		"brief": "Reagents, heat and an agitator. The reactor makes product and, at the same time, impurity; how much of each is yours to decide.",
		"requires": [
			{"kind": "reactor_product", "temp": 60.0, "frac": 0.10, "target": 200.0, "label": "held at 60 °C with 10 % product", "unit": "L"},
		],
		"unlocks": ["centrifuge", "dryer", "still", "column", "vaclock", "vialfill", "gauge_conc"],
	},
	{
		"id": "batch_record", "tier": "TIER 5 — FILL-FINISH", "title": "Batch record",
		"brief": "A vial is only a vial if what went in is what the label says. Separate, dry, fill, and prove it.",
		"requires": [
			{"kind": "vials", "target": 100.0, "label": "vials filled", "unit": ""},
			{"kind": "fill_purity", "target": 95.0, "label": "purity of what went into them", "unit": "%"},
		],
		"unlocks": [],
	},
]

var done: Array[String] = []
var pumped_l := 0.0
var pid_hold_s := 0.0
var _last_time := -1.0


## Is a build-menu type available? Structure is always; the rest
## follows the ladder.
func unlocked(type_id: String) -> bool:
	if type_id in BASE_TYPES or StructureFactory.SIZES.has(type_id):
		return true
	for milestone: Dictionary in LADDER:
		if done.has(str(milestone["id"])) and type_id in (milestone["unlocks"] as Array):
			return true
	return false


## The milestone being worked on, or {} when the ladder is complete.
func current() -> Dictionary:
	for milestone: Dictionary in LADDER:
		if not done.has(str(milestone["id"])):
			return milestone
	return {}


## Advance the trackers from sim time and check the current milestone.
## Returns the milestone just completed, or {}.
func tick(plant: Plant) -> Dictionary:
	var now := plant.sim.time
	var dt := 0.0 if _last_time < 0.0 else maxf(now - _last_time, 0.0)
	_last_time = now
	if dt > 0.0:
		var in_band := false
		for record in plant.sim.components:
			if record is SimPump:
				var pump := record as SimPump
				if pump.running:
					pumped_l += absf(pump.flow_lps) * dt
			elif record is SimPID:
				var pid := record as SimPID
				if pid.mode == "auto" and absf(pid.pv.value - pid.sp) <= maxf(0.03 * absf(pid.sp), 0.01):
					in_band = true
		pid_hold_s = pid_hold_s + dt if in_band else 0.0
	var milestone := current()
	if milestone.is_empty():
		return {}
	for req: Dictionary in milestone["requires"]:
		if not bool(progress(plant, req)["done"]):
			return {}
	done.append(str(milestone["id"]))
	return milestone


## One requirement's live standing: {label, value, target, unit, done}.
func progress(plant: Plant, req: Dictionary) -> Dictionary:
	var value := 0.0
	var target := float(req.get("target", req.get("n", 1)))
	match str(req["kind"]):
		"placed":
			for name_: String in plant.equip_types:
				if str(plant.equip_types[name_]) == str(req["type"]):
					value += 1.0
		"header_total":
			for record in plant.sim.components:
				if record is SimSource:
					value += (record as SimSource).total_l
		"sewer_total":
			for record in plant.sim.components:
				if record is SimDrain:
					value += (record as SimDrain).total_l
		"pumped":
			value = pumped_l
		"raised_tank":
			for record in plant.sim.components:
				if record is SimTank and (record as SimTank).elevation_m >= float(req["elev"]):
					value = maxf(value, (record as SimTank).level_l)
		"relay_cycles":
			for record in plant.sim.components:
				if record is SimRelay:
					value = maxf(value, float((record as SimRelay).cycles))
		"plc_scans":
			for record in plant.sim.components:
				if record is SimPLC:
					var plc := record as SimPLC
					if plc.program.size() >= int(req["rungs"]) and plc.power.value > 0.5:
						value = maxf(value, float(plc.scans))
		"pid_hold":
			value = pid_hold_s
		"reactor_product":
			for record in plant.sim.components:
				if record is SimReactor:
					var reactor := record as SimReactor
					if reactor.temp_c >= float(req["temp"]) \
							and reactor.contents.frac(SimSpecies.PRODUCT) >= float(req["frac"]):
						value = maxf(value, reactor.volume_l)
		"vials":
			for record in plant.sim.components:
				if record is SimVialFiller:
					value = maxf(value, float((record as SimVialFiller).vials_done))
		"fill_purity":
			for record in plant.sim.components:
				if record is SimVialFiller:
					var filler := record as SimVialFiller
					if filler.filled_l > 0.0:
						value = maxf(value, 100.0 * filler.product_filled_l / filler.filled_l)
	return {"label": str(req["label"]), "value": value, "target": target,
		"unit": str(req.get("unit", "")), "done": value >= target - 1e-9}


func state_dict() -> Dictionary:
	return {"done": done.duplicate(), "pumped_l": pumped_l, "pid_hold_s": pid_hold_s}


func apply_state(state: Dictionary) -> void:
	done.clear()
	for id_v: Variant in state.get("done", []):
		done.append(str(id_v))
	pumped_l = float(state.get("pumped_l", 0.0))
	pid_hold_s = float(state.get("pid_hold_s", 0.0))
	_last_time = -1.0
