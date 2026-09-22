class_name SimTank
extends SimComponent
## Holds liquid, and knows what the liquid is. Mirrors
## sim/components.py Tank.
##
## Two nozzles, and the difference between them is where they are.
## Each stands at a height on the shell (director, 2026-09-22: the
## nozzle's position belongs in the kernel; the view sets it where the
## player welded it), and what it feels is where it stands against the
## liquid: under the surface it carries the static head of whatever is
## standing above it, which is why a full tank will drain into an
## empty one through nothing but a pipe, and above it it sits at
## headspace pressure, so a line can fall in but nothing can come back
## out. So a tank keeps a heel below its outlet. The defaults put the
## outlet on the floor and the inlet at the roof.
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
## Flow a DN50 nozzle passes at the reference drop.
const OUTLET_CV_LPS := 20.0
## What a DN50 nozzle passes wide open across a 1 bar drop; a nozzle
## of another size scales with its bore's area (nozzle_cv).
var nozzle_cv_lps: float = OUTLET_CV_LPS
## Depth over which a nozzle uncovers as the level falls past it.
## Smooth, so an emptying vessel tails off instead of chattering shut.
const UNCOVER_M := 0.03
## A nozzle height meaning "at the roof", whatever the height is.
const AT_ROOF := -1.0
## The bore every nozzle had before they took their line's size.
const NOZZLE_DN_REF := 50
const NOZZLE_PORTS: Array[String] = ["inlet", "outlet"]

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
## An open-topped vessel (director, 2026-09-20: "fill an open tank ...
## drop by drop"): a line ending in the air above it lands what it
## spills here. The headspace is atmospheric either way.
var open_top: bool = false
## Where each nozzle stands on the shell, metres above the base
## (AT_ROOF for the roof), and its nominal size. The plant keeps both
## current: the height from the view's weld, the size from the line.
var nozzle_h_m: Dictionary = {"inlet": AT_ROOF, "outlet": 0.0}
var nozzle_dn: Dictionary = {"inlet": NOZZLE_DN_REF, "outlet": NOZZLE_DN_REF}
var _falling: SimStream = SimStream.empty()

var inlet: SimInputPort
var outlet: SimOutputPort
var level: SimOutputPort
var contents_tap: SimOutputPort

var _nozzle_nodes: Dictionary = {}      # port -> fixed node
var _nozzle_branches: Dictionary = {}   # port -> SimNozzleResistance


func _init(name_: String, capacity_l_: float, level_l_: float = 0.0, drain_lps_: float = 0.0,
		height_m_: float = 0.0, diameter_m_: float = 0.0,
		headspace_kpa_: float = 0.0, elevation_m_: float = 0.0,
		nozzle_cv_lps_: float = OUTLET_CV_LPS) -> void:
	super(name_)
	assert(capacity_l_ > 0.0, "capacity_l must be positive")
	assert(level_l_ >= 0.0, "level_l must be non-negative")
	assert(nozzle_cv_lps_ > 0.0, "nozzle_cv_lps must be positive")
	capacity_l = capacity_l_
	level_l = level_l_
	drain_lps = drain_lps_
	headspace_kpa = headspace_kpa_
	nozzle_cv_lps = nozzle_cv_lps_
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
	# The contents tap: a probe mounted on the shell reads what the
	# vessel holds through it. No branch, no flow, just the contents.
	contents_tap = add_output("contents", SimTypes.PortKind.PROCESS_MATERIAL)
	level.value = level_l
	add_observable("overflowed_l", &"overflowed_l")
	add_observable("ran_dry_ticks", &"ran_dry_ticks")
	add_observable("temp_c", &"temp_c")
	add_observable("depth_m", &"depth_m")


var cross_section_m2: float:
	get:
		return PI * pow(diameter_m / 2.0, 2)

## How deep the liquid stands. This is what a submerged nozzle feels,
## and what a level transmitter is really measuring.
var depth_m: float:
	get:
		return (level_l / 1000.0) / maxf(cross_section_m2, 1e-9)


## A tank does not come with a level port (director's call, 2026-09-02):
## the level tap exists for instruments mounted on the shell, and the
## plant wires it for them.
func hidden_ports() -> Array[String]:
	return ["level", "contents"]


func standing_ports() -> Array[String]:
	return ["contents"]


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


## ---- nozzles ---------------------------------------------------------------

## Where a nozzle stands on the shell, metres above the base (AT_ROOF
## for the roof). The view calls this where the player welded it.
func set_nozzle_height(port: String, height_m_: float) -> void:
	if not NOZZLE_PORTS.has(port):
		return
	nozzle_h_m[port] = AT_ROOF if height_m_ == AT_ROOF else maxf(height_m_, 0.0)


## A nozzle's nominal size: the size of the line on it (the plant
## keeps it current). Its Cv follows the bore's area.
func set_nozzle_dn(port: String, dn: int) -> void:
	if not NOZZLE_PORTS.has(port) or dn <= 0:
		return
	nozzle_dn[port] = dn


## Metres above the base, never above the roof.
func nozzle_height(port: String) -> float:
	var h := float(nozzle_h_m.get(port, 0.0))
	if h == AT_ROOF:
		return height_m
	return minf(h, height_m)


## What the nozzle passes wide open across the reference drop: the
## DN50 figure scaled by the bore's area.
func nozzle_cv(port: String) -> float:
	var ratio := float(int(nozzle_dn.get(port, NOZZLE_DN_REF))) / float(NOZZLE_DN_REF)
	return nozzle_cv_lps * ratio * ratio


## 0 with the level below the nozzle, 1 with it well above, ramping
## over UNCOVER_M between.
func nozzle_submergence(port: String) -> float:
	return clampf((depth_m - nozzle_height(port)) / UNCOVER_M, 0.0, 1.0)


func build_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	# One boundary node per nozzle, at the pressure the nozzle feels
	# where it stands; one nozzle branch each.
	_nozzle_nodes.clear()
	_nozzle_branches.clear()
	for port in NOZZLE_PORTS:
		var fixed := net.add_node(0.0, true)
		_nozzle_nodes[port] = fixed
		_nozzle_branches[port] = net.add_branch(SimNozzleResistance.new(
			fixed, node[port], nozzle_cv(port), comp_name + "." + port))


func update_hydraulics(net: SimNetwork, _node: Dictionary) -> void:
	# Piezometric, so a submerged nozzle at any height reads the same
	# as the floor: headspace plus the head of the whole depth. Above
	# the liquid it reads headspace at its own height, and passes
	# nothing out.
	var headspace_pa := headspace_kpa * 1000.0
	var depth := depth_m
	for port in NOZZLE_PORTS:
		var h := nozzle_height(port)
		net.set_pressure(int(_nozzle_nodes[port]),
			headspace_pa + SimHydraulics.static_head_pa(elevation_m + maxf(depth, h)), true)
		var branch := _nozzle_branches[port] as SimNozzleResistance
		var cv := nozzle_cv(port)
		if absf(branch.cv_lps - cv) > 1e-9:
			branch.set_cv(cv)
		branch.submergence = nozzle_submergence(port)


func supplied_stream(_port_name: String) -> SimStream:
	return contents  # the caller sets the rate


## Material falling in through the open top this scan, L/s at a
## composition: an open pipe end above the vessel hands its spill
## here, and the next tick blends it in like any other arrival.
func receive(stream: SimStream) -> void:
	if stream.flow_lps > 0.0:
		_falling = SimStream.mix(_falling, stream)


func tick(dt: float) -> void:
	# Both nozzles are signed into the vessel, so one balance covers
	# filling, draining, and a line that reversed on us.
	var net_lps := inlet.flow_lps + outlet.flow_lps
	var arriving := SimStream.empty()
	if inlet.flow_lps > 0.0:
		arriving = SimStream.mix(arriving, inlet.stream.with_flow(inlet.flow_lps))
	if outlet.flow_lps > 0.0:
		arriving = SimStream.mix(arriving, outlet.stream.with_flow(outlet.flow_lps))
	if _falling.flow_lps > 0.0:
		arriving = SimStream.mix(arriving, _falling)
		net_lps += _falling.flow_lps
		_falling = SimStream.empty()
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
		"open_top": open_top,
	}


func apply_state(state: Dictionary) -> void:
	if state.has("height_m") and state.has("diameter_m"):
		set_size(state["height_m"], state["diameter_m"])
	level_l = state.get("level_l", level_l)
	drain_lps = state.get("drain_lps", drain_lps)
	overflowed_l = state.get("overflowed_l", overflowed_l)
	ran_dry_ticks = int(state.get("ran_dry_ticks", ran_dry_ticks))
	open_top = bool(state.get("open_top", open_top))
	if state.has("contents"):
		contents = SimStream.from_dict(state["contents"]).with_flow(level_l)
		temp_c = contents.temp_c
	level.value = level_l
