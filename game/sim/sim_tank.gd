class_name SimTank
extends SimComponent
## Holds liquid. Integrates inlet flow minus what downstream equipment
## draws (plus the legacy constant drain). overflowed_l and
## ran_dry_ticks are the failure evidence a player would trace. The
## vessel has real geometry: height and diameter set the capacity.

var capacity_l: float
var level_l: float
var drain_lps: float
var height_m: float
var diameter_m: float
var overflowed_l: float = 0.0
var ran_dry_ticks: int = 0

var inlet: SimInputPort
var draw: SimInputPort
var level: SimOutputPort


func _init(name_: String, capacity_l_: float, level_l_: float = 0.0, drain_lps_: float = 0.0,
		height_m_: float = 0.0, diameter_m_: float = 0.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0, "capacity_l must be positive")
	assert(level_l_ >= 0.0, "level_l must be non-negative")
	capacity_l = capacity_l_
	level_l = level_l_
	drain_lps = drain_lps_
	if height_m_ > 0.0 and diameter_m_ > 0.0:
		# Geometry given: capacity follows it honestly.
		height_m = height_m_
		diameter_m = diameter_m_
		capacity_l = PI * pow(diameter_m_ / 2.0, 2) * height_m_ * 1000.0
		level_l = minf(level_l, capacity_l)
	elif height_m_ > 0.0:
		height_m = height_m_
		diameter_m = 2.0 * sqrt(capacity_l_ / 1000.0 / (PI * height_m_))
	else:
		# Capacity only: drum-like proportions (h = 1.4 d).
		diameter_m = pow(4.0 * capacity_l_ / 1000.0 / (1.4 * PI), 1.0 / 3.0)
		height_m = 1.4 * diameter_m
	level_l = minf(level_l, capacity_l)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_FLOW)
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	level.value = level_l
	add_observable("overflowed_l", &"overflowed_l")
	add_observable("ran_dry_ticks", &"ran_dry_ticks")


## Resize the vessel; capacity follows the geometry honestly and the
## inventory is clamped to what still fits.
func set_size(height_m_: float, diameter_m_: float) -> void:
	if height_m_ <= 0.0 or diameter_m_ <= 0.0:
		return
	height_m = height_m_
	diameter_m = diameter_m_
	capacity_l = PI * pow(diameter_m_ / 2.0, 2) * height_m_ * 1000.0
	level_l = minf(level_l, capacity_l)


func tick(dt: float) -> void:
	var inflow := inlet.value
	# Demand: equipment drawing from the outlet (pumps, drains) plus
	# the legacy constant-drain parameter. Can't remove more than it
	# holds.
	var demand := drain_lps + draw.value
	var available := level_l + inflow * dt
	var drained := minf(demand * dt, available)
	if drained < demand * dt - 1e-9:
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
		"height_m": height_m,
		"diameter_m": diameter_m,
	}


func apply_state(state: Dictionary) -> void:
	if state.has("height_m") and state.has("diameter_m"):
		set_size(state["height_m"], state["diameter_m"])
	level_l = state.get("level_l", level_l)
	drain_lps = state.get("drain_lps", drain_lps)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	ran_dry_ticks = int(state.get("ran_dry_ticks", ran_dry_ticks))
	level.value = level_l
