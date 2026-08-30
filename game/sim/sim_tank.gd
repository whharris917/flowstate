class_name SimTank
extends SimComponent
## Holds liquid. Integrates inflow minus a fixed drain demand.
## overflowed_l and ran_dry_ticks are the failure evidence a player
## would trace.

var capacity_l: float
var level_l: float
var drain_lps: float
var overflowed_l: float = 0.0
var ran_dry_ticks: int = 0

var in_flow: SimInputPort
var level: SimOutputPort


func _init(name_: String, capacity_l_: float, level_l_: float = 0.0, drain_lps_: float = 0.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0, "capacity_l must be positive")
	assert(level_l_ >= 0.0 and level_l_ <= capacity_l_, "level_l must be within [0, capacity]")
	capacity_l = capacity_l_
	level_l = level_l_
	drain_lps = drain_lps_
	in_flow = add_input("in_flow", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	level.value = level_l
	add_observable("overflowed_l", func() -> float: return overflowed_l)
	add_observable("ran_dry_ticks", func() -> float: return float(ran_dry_ticks))


func tick(dt: float) -> void:
	var inflow := in_flow.value
	# Can't drain more than the tank holds this tick.
	var available := level_l + inflow * dt
	var drained := minf(drain_lps * dt, available)
	if drained < drain_lps * dt:
		ran_dry_ticks += 1
	var new_level := level_l + inflow * dt - drained
	if new_level > capacity_l:
		overflowed_l += new_level - capacity_l
		new_level = capacity_l
	level_l = new_level
	level.value = level_l


func state_dict() -> Dictionary:
	return {
		"level_l": level_l,
		"drain_lps": drain_lps,
		"overflowed_l": overflowed_l,
		"ran_dry_ticks": ran_dry_ticks,
	}


func apply_state(state: Dictionary) -> void:
	level_l = state.get("level_l", level_l)
	drain_lps = state.get("drain_lps", drain_lps)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	ran_dry_ticks = int(state.get("ran_dry_ticks", ran_dry_ticks))
	level.value = level_l
