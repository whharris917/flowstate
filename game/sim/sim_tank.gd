class_name SimTank
extends SimComponent
## Holds liquid, and knows what the liquid is. Mirrors
## sim/components.py Tank.
##
## Two nozzles, and the difference between them is where they are. The
## outlet is at the bottom, so it carries the static head of whatever
## is standing above it — which is why a full tank will drain into an
## empty one through nothing but a pipe. The inlet is at the top, at
## headspace pressure, so filling it never has to fight the level.
##
## Inflow is blended into the inventory: the contents take a
## volume-weighted temperature and composition, which is what makes a
## hot stream genuinely warm a vessel. Whatever leaves does so at the
## current contents composition. "level" stays a plain level tap for
## instruments. overflowed_l and ran_dry_ticks are the failure evidence
## a player would trace. The vessel has real geometry: height and
## diameter set the capacity.

## Bare-vessel heat loss to the hall. Slow: a hot batch left overnight
## is cold in the morning, but nothing changes in a minute.
const LOSS_PER_S := 0.0002
## The nozzle and its stub, Pa per (L/s)^2.
const NOZZLE_K := 800.0
## Flow the bottom nozzle passes at the reference drop.
const OUTLET_CV_LPS := 20.0
## Depth over which the bottom nozzle uncovers as the level falls past
## it. Smooth, so an emptying vessel tails off instead of chattering
## shut.
const UNCOVER_M := 0.03

var capacity_l: float
var level_l: float
var drain_lps: float
var height_m: float
var diameter_m: float
var headspace_kpa: float = 0.0
var elevation_m: float = 0.0
var temp_c: float = SimStream.AMBIENT_C
var contents: SimStream
var overflowed_l: float = 0.0
var ran_dry_ticks: int = 0

var inlet: SimInputPort
var outlet: SimOutputPort
var level: SimOutputPort

var _roof: int = -1
var _floor: int = -1
var _outlet_branch: SimControlResistance = null


func _init(name_: String, capacity_l_: float, level_l_: float = 0.0, drain_lps_: float = 0.0,
		height_m_: float = 0.0, diameter_m_: float = 0.0,
		headspace_kpa_: float = 0.0, elevation_m_: float = 0.0) -> void:
	super(name_)
	assert(capacity_l_ > 0.0, "capacity_l must be positive")
	assert(level_l_ >= 0.0, "level_l must be non-negative")
	capacity_l = capacity_l_
	level_l = level_l_
	drain_lps = drain_lps_
	headspace_kpa = headspace_kpa_
	elevation_m = elevation_m_
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
	inlet = add_input("inlet", SimTypes.PortKind.PROCESS_MATERIAL)
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	level = add_output("level", SimTypes.PortKind.PROCESS_LEVEL)
	level.value = level_l
	add_observable("overflowed_l", &"overflowed_l")
	add_observable("ran_dry_ticks", &"ran_dry_ticks")
	add_observable("temp_c", &"temp_c")
	add_observable("depth_m", &"depth_m")


var cross_section_m2: float:
	get:
		return PI * pow(diameter_m / 2.0, 2)

## How deep the liquid stands. This is what the outlet nozzle feels,
## and what a level transmitter is really measuring.
var depth_m: float:
	get:
		return (level_l / 1000.0) / maxf(cross_section_m2, 1e-9)


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


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	_roof = net.add_node(0.0, true)
	_floor = net.add_node(0.0, true)
	net.add_branch(SimCheckResistance.new(node["inlet"], _roof, NOZZLE_K, comp_name + ".inlet"))
	_outlet_branch = net.add_branch(SimControlResistance.new(
		_floor, node["outlet"], OUTLET_CV_LPS, comp_name + ".outlet")) as SimControlResistance


func update_hydraulics(net: SimNetwork, _node: Dictionary) -> void:
	var headspace_pa := headspace_kpa * 1000.0
	net.set_pressure(_roof, headspace_pa + SimHydraulics.static_head_pa(elevation_m + height_m), true)
	net.set_pressure(_floor, headspace_pa + SimHydraulics.static_head_pa(elevation_m + depth_m), true)
	# The bottom nozzle uncovers as the level drops past it. Filling
	# back in through it is always allowed -- that is how you charge a
	# vessel from below. Which way it went last scan is read off the
	# branch itself: a node pressure can be floating, a solved flow
	# cannot.
	var filling := _outlet_branch.flow_lps < -1e-9
	_outlet_branch.opening = 1.0 if filling else minf(depth_m / UNCOVER_M, 1.0)


func supplied_stream(_port_name: String) -> SimStream:
	return contents  # the caller sets the rate


func tick(dt: float) -> void:
	# Both nozzles are signed into the vessel, so one balance covers
	# filling, draining, and a line that reversed on us.
	var net_lps := inlet.flow_lps + outlet.flow_lps
	var arriving := SimStream.empty()
	if inlet.flow_lps > 0.0:
		arriving = SimStream.mix(arriving, inlet.stream.with_flow(inlet.flow_lps))
	if outlet.flow_lps > 0.0:
		arriving = SimStream.mix(arriving, outlet.stream.with_flow(outlet.flow_lps))
	var added_l := arriving.flow_lps * dt
	var leaving_l := maxf(-net_lps + arriving.flow_lps, 0.0) * dt
	var demand_l := drain_lps * dt + leaving_l
	if demand_l > level_l + added_l + 1e-9:
		ran_dry_ticks += 1

	# Blend what arrived into what was already there. Draw-off and
	# overflow both leave at the contents composition, so neither
	# changes it — only the inflow does.
	if added_l > 0.0:
		contents = SimStream.mix(contents.with_flow(level_l), arriving.with_flow(added_l))
	var new_level := level_l + added_l - minf(demand_l, level_l + added_l)
	if new_level > capacity_l:
		overflowed_l += new_level - capacity_l
		new_level = capacity_l
	level_l = maxf(new_level, 0.0)

	# Ambient loss, then republish the contents at the new level.
	temp_c = contents.temp_c
	temp_c -= (temp_c - SimStream.AMBIENT_C) * LOSS_PER_S * dt
	contents = contents.with_flow(level_l).with_temp(temp_c)
	level.value = level_l


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
