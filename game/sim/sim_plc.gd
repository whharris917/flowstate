class_name SimPLC
extends SimComponent
## Rack PLC: discrete/analog I/O channels as ports (di_N/do_N,
## ai_N/ao_N), bool memories, TON timers, and a validated ladder
## program scanned once per sim tick — rungs top to bottom, coils
## written immediately (later rungs see earlier results in the same
## scan), undriven outputs off, last coil wins. Mirrors sim/control.py.
##
## Rung: {"coil": "do_0"|"m_0"|"t_0", "logic": [[{"ref","nc"}...]...]}
## — branches OR together, elements in a branch AND together. Refs
## read di_N, do_N (readback), m_N, t_N (done). Driving t_N runs TON
## timer N. Analog: ao_moves [{dst, src, k, b}] map ai->ao scaled.

var n_di: int
var n_do: int
var n_ai: int
var n_ao: int
var di_ports: Array[SimInputPort] = []
var ai_ports: Array[SimInputPort] = []
var do_ports: Array[SimOutputPort] = []
var ao_ports: Array[SimOutputPort] = []
var mem: Array[bool] = []
var timer_acc: Array[float] = []
var timer_run: Array[bool] = []
var timer_done: Array[bool] = []
var timer_presets: Array[float] = []
var program: Array[Dictionary] = []
var ao_moves: Array[Dictionary] = []
var scans: int = 0
var power: SimInputPort


func _init(name_: String, di := 8, do := 8, ai := 4, ao := 4,
		memories := 16, timers := 4) -> void:
	super(name_)
	n_di = di
	n_do = do
	n_ai = ai
	n_ao = ao
	for i in range(di):
		di_ports.append(add_input("di_%d" % i, SimTypes.PortKind.SIGNAL_DISCRETE))
	for i in range(ai):
		ai_ports.append(add_input("ai_%d" % i, SimTypes.PortKind.SIGNAL_ANALOG))
	for i in range(do):
		do_ports.append(add_output("do_%d" % i, SimTypes.PortKind.SIGNAL_DISCRETE))
	for i in range(ao):
		ao_ports.append(add_output("ao_%d" % i, SimTypes.PortKind.SIGNAL_ANALOG))
	for _i in range(memories):
		mem.append(false)
	for _i in range(timers):
		timer_acc.append(0.0)
		timer_run.append(false)
		timer_done.append(false)
		timer_presets.append(1.0)
	power = add_input("power", SimTypes.PortKind.POWER, "24VDC")
	add_observable("scans", &"scans")


## ---- program management ---------------------------------------------------

## "" on success, else a human-readable refusal (the editor shows it).
func set_program(rungs: Array) -> String:
	var clean: Array[Dictionary] = []
	for rung_v: Variant in rungs:
		var rung := rung_v as Dictionary
		var coil := str(rung.get("coil", ""))
		var coil_err := _check_ref(coil, true)
		if coil_err != "":
			return coil_err
		var branches_in: Array = rung.get("logic", [])
		if branches_in.is_empty():
			return "rung for %s has no logic" % coil
		var branches: Array = []
		for branch_v: Variant in branches_in:
			var branch := branch_v as Array
			if branch.is_empty():
				return "rung for %s has an empty branch" % coil
			var elements: Array = []
			for element_v: Variant in branch:
				var element := element_v as Dictionary
				var ref := str(element.get("ref", ""))
				var ref_err := _check_ref(ref, false)
				if ref_err != "":
					return ref_err
				elements.append({"ref": ref, "nc": bool(element.get("nc", false))})
			branches.append(elements)
		clean.append({"coil": coil, "logic": branches})
	program = clean
	return ""


func set_ao_moves(moves: Array) -> String:
	var clean: Array[Dictionary] = []
	for move_v: Variant in moves:
		var move := move_v as Dictionary
		var dst := str(move.get("dst", ""))
		var src := str(move.get("src", ""))
		if not dst.begins_with("ao_") or _index_of(dst) < 0 or _index_of(dst) >= n_ao:
			return "bad move dst %s" % dst
		if not src.begins_with("ai_") or _index_of(src) < 0 or _index_of(src) >= n_ai:
			return "bad move src %s" % src
		clean.append({"dst": dst, "src": src,
			"k": float(move.get("k", 1.0)), "b": float(move.get("b", 0.0))})
	ao_moves = clean
	return ""


func set_timer_preset(index: int, seconds: float) -> void:
	if index >= 0 and index < timer_presets.size() and seconds > 0.0:
		timer_presets[index] = seconds


func _family_limit(family: String) -> int:
	match family:
		"di": return n_di
		"do": return n_do
		"ai": return n_ai
		"ao": return n_ao
		"m": return mem.size()
		"t": return timer_acc.size()
	return -1


func _index_of(ref: String) -> int:
	var parts := ref.split("_")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return -1
	return int(parts[1])


func _check_ref(ref: String, coil: bool) -> String:
	var parts := ref.split("_")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return "bad %s '%s'" % ["coil" if coil else "ref", ref]
	var family := parts[0]
	var allowed: Array[String] = ["do", "m", "t"]
	if not coil:
		allowed = ["di", "do", "m", "t"]
	if not family in allowed:
		return "bad %s '%s'" % ["coil" if coil else "ref", ref]
	var index := int(parts[1])
	if index < 0 or index >= _family_limit(family):
		return "%s out of range" % ref
	return ""


## ---- scan -----------------------------------------------------------------

func _read(ref: String) -> bool:
	var parts := ref.split("_")
	var index := int(parts[1])
	match parts[0]:
		"di": return di_ports[index].value > 0.5
		"do": return do_ports[index].value > 0.5
		"m": return mem[index]
	return timer_done[index]


func tick(dt: float) -> void:
	if power.value <= 0.5:
		# De-energized: outputs drop, timers reset, memory holds
		# (battery-backed), no scan runs.
		for port in do_ports:
			port.value = 0.0
		for port in ao_ports:
			port.value = 0.0
		for i in range(timer_run.size()):
			timer_run[i] = false
			timer_acc[i] = 0.0
			timer_done[i] = false
		return
	scans += 1
	# Outputs no rung drives stay off; timers must be re-driven every
	# scan or they release (TON semantics).
	for port in do_ports:
		port.value = 0.0
	var driven: Array[bool] = []
	for _i in range(timer_run.size()):
		driven.append(false)
	for rung in program:
		var value := false
		for branch_v: Variant in rung["logic"]:
			var branch_true := true
			for element_v: Variant in (branch_v as Array):
				var element := element_v as Dictionary
				if _read(str(element["ref"])) == bool(element["nc"]):
					branch_true = false
					break
			if branch_true:
				value = true
				break
		var coil := str(rung["coil"])
		var index := _index_of(coil)
		if coil.begins_with("do_"):
			do_ports[index].value = 1.0 if value else 0.0
		elif coil.begins_with("m_"):
			mem[index] = value
		else:
			timer_run[index] = value
			driven[index] = true
	for i in range(timer_run.size()):
		if not driven[i]:
			timer_run[i] = false
		if timer_run[i]:
			timer_acc[i] = minf(timer_acc[i] + dt, timer_presets[i])
		else:
			timer_acc[i] = 0.0
		# Epsilon absorbs float accumulation (real PLCs count ms).
		timer_done[i] = timer_acc[i] >= timer_presets[i] - 1e-9
	for move in ao_moves:
		var src := ai_ports[_index_of(str(move["src"]))]
		var dst := ao_ports[_index_of(str(move["dst"]))]
		dst.value = float(src.value) * float(move["k"]) + float(move["b"])


## ---- save/load ------------------------------------------------------------

func state_dict() -> Dictionary:
	return {
		"program": program.duplicate(true), "ao_moves": ao_moves.duplicate(true),
		"mem": mem.duplicate(), "timer_acc": timer_acc.duplicate(),
		"timer_presets": timer_presets.duplicate(),
	}


func apply_state(state: Dictionary) -> void:
	if state.has("program"):
		set_program(state["program"])
	if state.has("ao_moves"):
		set_ao_moves(state["ao_moves"])
	var mem_in: Array = state.get("mem", [])
	for i in range(mini(mem_in.size(), mem.size())):
		mem[i] = bool(mem_in[i])
	var acc_in: Array = state.get("timer_acc", [])
	for i in range(mini(acc_in.size(), timer_acc.size())):
		timer_acc[i] = float(acc_in[i])
	var presets_in: Array = state.get("timer_presets", [])
	for i in range(mini(presets_in.size(), timer_presets.size())):
		timer_presets[i] = float(presets_in[i])
