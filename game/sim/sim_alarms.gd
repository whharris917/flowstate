class_name SimAlarms
extends RefCounted
## Alarm scanning (Tier 5, 2026-09-11): the conditions a plant would
## annunciate, read off the records' own state and nothing else. An
## alarm is active while its condition holds; the scanner remembers
## when each came in, so the HUD can show its age and a new one can
## ring. A few conditions need memory — a valve that was told to open
## and has not reported open within twice its stroke, a loop that has
## sat on an output limit — and that memory lives here, keyed by
## record name, not on the records.

const VALVE_GRACE := 2.0      # strokes a valve gets before it has failed to travel
const SATURATED_S := 30.0     # a loop pinned at a limit this long is not controlling
const STARVED_S := 10.0       # a spinning bowl drawing nothing this long

var active: Dictionary = {}   # key -> {"tag", "text", "since"}
var new_keys: Array[String] = []   # alarms that came in on the last scan

var _valve_cmd: Dictionary = {}    # name -> {"open": bool, "at": float}
var _pid_limit_since: Dictionary = {}
var _fuge_dry_since: Dictionary = {}
var _tank_overflowed: Dictionary = {}


## Scan every record and return the active alarms, oldest first.
func scan(sim: Simulation) -> Array[Dictionary]:
	var now := sim.time
	var seen := {}
	for record in sim.components:
		if record is SimPump:
			var pump := record as SimPump
			if pump.running and pump.flow_lps <= 1e-6:
				if pump.cavitating:
					_raise(seen, pump.comp_name, "CAVITATING", now)
				elif pump.head_pa >= SimHydraulics.static_head_pa(pump.head_m) - 1.0:
					_raise(seen, pump.comp_name, "DEAD-HEADED", now)
		elif record is SimReactor:
			if (record as SimReactor).boiling:
				_raise(seen, record.comp_name, "BOILING · venting", now)
		elif record is SimTank:
			var tank := record as SimTank
			var was: float = _tank_overflowed.get(tank.comp_name, tank.overflowed_l)
			if tank.overflowed_l > was + 1e-9:
				_raise(seen, tank.comp_name, "OVERFLOWING", now)
			_tank_overflowed[tank.comp_name] = tank.overflowed_l
		elif record is SimCap:
			var cap := record as SimCap
			if cap.open and cap.spill_lps() > 1e-3:
				_raise(seen, cap.comp_name, "SPILLING · open end", now)
		elif record is SimVialFiller:
			var filler := record as SimVialFiller
			if filler.is_on and filler.starved:
				_raise(seen, filler.comp_name, "STARVED · no feed", now)
		elif record is SimBlockValve:
			var xv := record as SimBlockValve
			var cmd := xv.commanded_open
			var memo: Dictionary = _valve_cmd.get(xv.comp_name, {"open": cmd, "at": now})
			if bool(memo["open"]) != cmd:
				memo = {"open": cmd, "at": now}
			_valve_cmd[xv.comp_name] = memo
			var landed := xv.limit_open if cmd else xv.limit_closed
			if not landed and now - float(memo["at"]) > VALVE_GRACE * xv.stroke_s:
				_raise(seen, xv.comp_name, "FAILED TO %s" % ("OPEN" if cmd else "CLOSE"), now)
		elif record is SimPLC:
			var plc := record as SimPLC
			if not plc.program.is_empty() and plc.power.value <= 0.5:
				_raise(seen, plc.comp_name, "UNPOWERED · program loaded", now)
		elif record is SimPID:
			var pid := record as SimPID
			var pinned := pid.mode == "auto" and (pid.output <= pid.out_min + 1e-9
				or pid.output >= pid.out_max - 1e-9)
			if pinned:
				var since: float = _pid_limit_since.get(pid.comp_name, now)
				_pid_limit_since[pid.comp_name] = since
				if now - since >= SATURATED_S:
					_raise(seen, pid.comp_name, "OUTPUT AT %s LIMIT" % (
						"LOW" if pid.output <= pid.out_min + 1e-9 else "HIGH"), now)
			else:
				_pid_limit_since.erase(pid.comp_name)
		elif record is SimCentrifuge:
			var fuge := record as SimCentrifuge
			if fuge.spinning and fuge.draw_lps <= 1e-6:
				var since: float = _fuge_dry_since.get(fuge.comp_name, now)
				_fuge_dry_since[fuge.comp_name] = since
				if now - since >= STARVED_S:
					_raise(seen, fuge.comp_name, "SPINNING DRY · no feed", now)
			else:
				_fuge_dry_since.erase(fuge.comp_name)
	new_keys.clear()
	for key: String in seen:
		if not active.has(key):
			active[key] = seen[key]
			new_keys.append(key)
	for key: String in active.keys():
		if not seen.has(key):
			active.erase(key)
	var out: Array[Dictionary] = []
	for key: String in active:
		out.append(active[key])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["since"]) < float(b["since"]))
	return out


func _raise(seen: Dictionary, tag: String, text: String, now: float) -> void:
	var key := tag + "|" + text
	if active.has(key):
		seen[key] = active[key]
	else:
		seen[key] = {"tag": tag, "text": text, "since": now}


## One line per alarm for the HUD: tag, condition, age.
static func line(alarm: Dictionary, now: float) -> String:
	var age := int(now - float(alarm["since"]))
	@warning_ignore("integer_division")
	return "⚠ %s  %s  · %d:%02d" % [str(alarm["tag"]).to_upper().replace("_", "-"),
		alarm["text"], age / 60, age % 60]
