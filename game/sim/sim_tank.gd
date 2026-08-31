class_name SimTank
extends SimComponent
## Holds liquid, and knows what the liquid is. Mirrors
## sim/components.py Tank.
##
## Inflow arriving on "inlet" is blended into the inventory: the
## contents take a volume-weighted temperature and composition, which
## is what makes a hot stream genuinely warm a vessel and a reagent
## charge genuinely change what is in it. Whatever is drawn off leaves
## at the current contents composition.
##
## The vessel offers its contents at "outlet" as a supply: the rate
## published there is the most that could be taken this instant, so a
## pump on a nearly empty tank throttles itself instead of pulling
## liquid that is not there. "level" stays a plain level tap for
## instruments. overflowed_l and ran_dry_ticks are the failure evidence
## a player would trace. The vessel has real geometry: height and
## diameter set the capacity.

## Nozzle capacity: the ceiling on what the outlet can offer however
## full the vessel is. Keeps a full tank from advertising an absurd
## instantaneous rate.
const OUTLET_MAX_LPS := 250.0
## Bare-vessel heat loss to the hall. Slow: a hot batch left overnight
## is cold in the morning, but nothing changes in a minute.
const LOSS_PER_S := 0.0002

var capacity_l: float
var level_l: float
var drain_lps: float
var height_m: float
var diameter_m: float
var temp_c: float = SimStream.AMBIENT_C
var contents: SimStream
var overflowed_l: float = 0.0
var ran_dry_ticks: int = 0

var inlet: SimInputPort
var draw: SimInputPort
var level: SimOutputPort
var outlet: SimOutputPort


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
	contents = SimStream.pure(SimSpecies.WATER, level_l, temp_c)
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_STREAM)
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_SUPPLY)
	level.value = level_l
	add_observable("overflowed_l", &"overflowed_l")
	add_observable("ran_dry_ticks", &"ran_dry_ticks")
	add_observable("temp_c", &"temp_c")


## Put a charge in the vessel directly — a commissioning fill, or a
## save being restored.
func charge(volume_l: float, comp: PackedFloat32Array, temp_c_: float) -> void:
	level_l = clampf(volume_l, 0.0, capacity_l)
	temp_c = temp_c_
	contents = SimStream.make(level_l, temp_c_, comp)
	level.value = level_l


func solids_frac() -> float:
	return contents.solids_frac


func purity_frac() -> float:
	return contents.frac(SimSpecies.PRODUCT)


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
	var incoming := inlet.stream
	var added_l := incoming.flow_lps * dt
	# Demand: equipment drawing from the outlet (pumps, drains) plus
	# the legacy constant-drain parameter. Cannot remove more than it
	# holds.
	var demand := drain_lps + draw.value
	var available := level_l + added_l
	var drained := minf(demand * dt, available)
	if drained < demand * dt - 1e-9:
		ran_dry_ticks += 1

	# Blend what arrived into what was already there. Draw-off and
	# overflow both leave at the contents composition, so neither
	# changes it — only the inflow does.
	if added_l > 0.0:
		contents = SimStream.mix(contents.with_flow(level_l), incoming.with_flow(added_l))

	var new_level := level_l + added_l - drained
	if new_level > capacity_l:
		overflowed_l += new_level - capacity_l
		new_level = capacity_l
	level_l = maxf(new_level, 0.0)

	# Ambient loss, then republish the contents at the new level.
	temp_c = contents.temp_c
	temp_c -= (temp_c - SimStream.AMBIENT_C) * LOSS_PER_S * dt
	contents = contents.with_flow(level_l).with_temp(temp_c)

	level.value = level_l
	# Offer the contents: at most a full nozzle, and never more than is
	# actually in the vessel this scan.
	var offered := minf(level_l / dt, OUTLET_MAX_LPS) if dt > 0.0 else 0.0
	outlet.stream = contents.with_flow(offered)


func state_dict() -> Dictionary:
	return {
		"level_l": level_l,
		"drain_lps": drain_lps,
		"overflowed_l": overflowed_l,
		"ran_dry_ticks": ran_dry_ticks,
		"height_m": height_m,
		"diameter_m": diameter_m,
		"contents": contents.to_dict(),
	}


func apply_state(state: Dictionary) -> void:
	if state.has("height_m") and state.has("diameter_m"):
		set_size(state["height_m"], state["diameter_m"])
	level_l = state.get("level_l", level_l)
	drain_lps = state.get("drain_lps", drain_lps)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	ran_dry_ticks = int(state.get("ran_dry_ticks", ran_dry_ticks))
	if state.has("contents"):
		contents = SimStream.from_dict(state["contents"]).with_flow(level_l)
		temp_c = contents.temp_c
	level.value = level_l
