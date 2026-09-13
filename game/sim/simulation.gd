class_name Simulation
## Owns the component graph and advances it at a fixed rate.
##
## Tick order (one scan): input ports reset, wires copy last scan's
## outputs into inputs, the hydraulic network is solved for what
## actually flows and which way, components tick in insertion order,
## historian samples. Components only ever read their own input ports,
## so results are deterministic regardless of build order, and every
## hop through the graph costs one scan of latency — real relay/PLC
## scan delay, which is what makes chatter physically reproducible.

var dt: float
var time: float = 0.0
var components: Array[SimComponent] = []
var wires: Array[SimWire] = []
var historian: SimHistorian = null
## Wall time the last hydraulic pass took, for the smoke run's cost
## report: the whole pass, and the Newton solve alone. Not sim
## variables.
var solve_ms: float = 0.0
var newton_ms: float = 0.0

var _by_name: Dictionary = {}  # String -> SimComponent
var _network: SimNetwork = null
var _network_stale: bool = true
var _node_streams: Array[SimStream] = []
var _taps: Dictionary = {}        # tap node -> true
var _tap_source: Dictionary = {}  # tap node -> the node it watches


func _init(dt_: float = 0.05) -> void:
	assert(dt_ > 0.0, "dt must be positive")
	dt = dt_


func add(component: SimComponent) -> SimComponent:
	if _by_name.has(component.comp_name):
		push_error("duplicate component name '%s'" % component.comp_name)
		return component
	_by_name[component.comp_name] = component
	components.append(component)
	_network_stale = true
	return component


func get_component(name_: String) -> SimComponent:
	return _by_name.get(name_)


## Returns true when the wire was made. Kind mismatches and second
## wires into single-source inputs are rejected with an error. Several
## material runs may land on one nozzle: that is a tee.
func connect_ports(src: SimComponent, out_name: String, dst: SimComponent, in_name: String) -> bool:
	var out_port: SimOutputPort = src.outputs.get(out_name)
	var in_port: SimInputPort = dst.inputs.get(in_name)
	if out_port == null or in_port == null:
		push_error("no such port: %s.%s -> %s.%s" % [src.comp_name, out_name, dst.comp_name, in_name])
		return false
	if out_port.kind != in_port.kind:
		push_error("cannot wire %s (%s) to %s (%s)" % [
			out_port.path(), SimTypes.kind_name(out_port.kind),
			in_port.path(), SimTypes.kind_name(in_port.kind)])
		return false
	if out_port.kind == SimTypes.PortKind.POWER and out_port.spec != in_port.spec:
		push_error("voltage mismatch: %s is %s, %s needs %s" % [
			out_port.path(), out_port.spec, in_port.path(), in_port.spec])
		return false
	if in_port.wire_count > 0 and not SimTypes.allows_multiple_sources(in_port.kind):
		push_error("%s (%s) accepts only one wire" % [in_port.path(), SimTypes.kind_name(in_port.kind)])
		return false
	wires.append(SimWire.new(out_port, in_port))
	_network_stale = true
	return true


## Remove one wire between two ports (the physical act of pulling a
## run). Frees the input's single-source slot; the input reverts to
## its default on the next scan. False if no such wire exists.
func disconnect_ports(src: SimComponent, out_name: String, dst: SimComponent, in_name: String) -> bool:
	var wire := find_wire(src, out_name, dst, in_name)
	if wire == null:
		return false
	wires.erase(wire)
	wire.dst.wire_count -= 1
	_network_stale = true
	return true


func find_wire(src: SimComponent, out_name: String, dst: SimComponent, in_name: String) -> SimWire:
	if src == null or dst == null:
		return null
	var out_port: SimOutputPort = src.outputs.get(out_name)
	var in_port: SimInputPort = dst.inputs.get(in_name)
	if out_port == null or in_port == null:
		return null
	for wire in wires:
		if wire.src == out_port and wire.dst == in_port:
			return wire
	return null


## Size a pipe run: Pa per (L/s)^2, so a long or thin line genuinely
## costs more pressure. Takes effect at the next scan.
func set_wire_resistance(wire: SimWire, k_pa_per_lps2: float) -> void:
	wire.k_pa_per_lps2 = maxf(k_pa_per_lps2, SimHydraulics.EPS)
	if wire.branch is SimResistance:
		(wire.branch as SimResistance).set_k(wire.k_pa_per_lps2)


## ---- the hydraulic pass ---------------------------------------------------

## Lay out the network: one node per nozzle, one branch per pipe run,
## plus whatever each component puts between its own nozzles. Only
## topology lives here. Pressures and settings are refreshed every
## scan, which is far cheaper than rebuilding.
## Topology or a boundary elevation changed outside a wiring call: the
## next tick rebuilds the network.
func invalidate_network() -> void:
	_network_stale = true


func _rebuild_network() -> void:
	var net := SimNetwork.new()
	for component in components:
		var ports := component.material_ports()
		var shared := {}
		for group: Array in component.shared_node_ports():
			var node := net.add_node()
			for port_name: String in group:
				shared[port_name] = node
		for port_name: String in ports:
			(ports[port_name] as SimPort).node = shared[port_name] if shared.has(port_name) else net.add_node()
		var node_map := {}
		for port_name: String in ports:
			node_map[port_name] = (ports[port_name] as SimPort).node
		component.node_map = node_map
	_taps.clear()
	_tap_source.clear()
	for component in components:
		var ports := component.material_ports()
		for tap_name in component.tap_ports():
			if ports.has(tap_name):
				_taps[(ports[tap_name] as SimPort).node] = true
	for wire in wires:
		wire.branch = null
		if not wire.is_material():
			continue
		var src_node := wire.src.node
		var dst_node := wire.dst.node
		if _taps.has(src_node) or _taps.has(dst_node):
			# An instrument tap draws nothing, so it gets no branch. It
			# reads whatever the line it is tapped into holds.
			if _taps.has(dst_node):
				_tap_source[dst_node] = src_node
			else:
				_tap_source[src_node] = dst_node
			continue
		wire.branch = net.add_branch(SimResistance.new(src_node, dst_node, wire.k_pa_per_lps2,
			wire.src.path() + "->" + wire.dst.path()))
	for component in components:
		if not component.material_ports().is_empty():
			component.build_hydraulics(net, component.node_map)
	_network = net
	_node_streams.clear()
	for _i in net.node_count():
		_node_streams.append(SimStream.empty())
	_network_stale = false


func _solve_hydraulics() -> void:
	if _network_stale or _network == null:
		_rebuild_network()
	var net := _network
	if net.branches.is_empty():
		return
	for component in components:
		if not component.material_ports().is_empty():
			component.update_hydraulics(net, component.node_map)
	var started := Time.get_ticks_usec()
	net.solve()
	newton_ms = (Time.get_ticks_usec() - started) / 1000.0

	# What each component sees at each nozzle: the net flow arriving
	# from the pipe runs attached to it. At a boundary the vessel
	# absorbs that; at a free node it equals what passes through the
	# component, by conservation. One rule covers both.
	for component in components:
		var ports := component.material_ports()
		for port_name: String in ports:
			(ports[port_name] as SimPort).flow_lps = 0.0
	for wire in wires:
		if wire.branch == null:
			continue
		var q := wire.branch.flow_lps
		wire.src.flow_lps -= q
		wire.dst.flow_lps += q
	_resolve_compositions()


## Work out what is in each node, then hand it to the ports.
##
## Composition moves one node per scan, the same one-scan latency every
## other hop in this kernel costs. That is what lets a recycle loop
## close without a simultaneous solve: the ring simply fills up over a
## few scans, exactly as a real one does.
func _resolve_compositions() -> void:
	var net := _network
	var previous := _node_streams
	var count := net.node_count()
	var species := SimSpecies.COUNT

	# What arrives at each node, flow-weighted: flows add, temperature,
	# solids and composition are weighted by flow, which is exactly
	# what SimStream.mix does -- accumulated in flat arrays rather than
	# one stream object per branch, because in GDScript the allocations
	# cost more than the arithmetic.
	var flow := PackedFloat64Array()
	flow.resize(count)
	flow.fill(0.0)
	var temp := PackedFloat64Array()
	temp.resize(count)
	temp.fill(0.0)
	var solids := PackedFloat64Array()
	solids.resize(count)
	solids.fill(0.0)
	var comp := PackedFloat64Array()
	comp.resize(count * species)
	comp.fill(0.0)
	for branch in net.branches:
		var q := branch.flow_lps
		if absf(q) < 1e-12:
			continue
		var from := branch.node_a
		var to := branch.node_b
		if q < 0.0:
			from = branch.node_b
			to = branch.node_a
			q = -q
		var src := previous[from]
		flow[to] += q
		temp[to] += q * src.temp_c
		solids[to] += q * src.solids_frac
		var base := to * species
		for i in species:
			comp[base + i] += q * src.comp[i]
	var fresh: Array[SimStream] = []
	fresh.resize(count)
	for i in count:
		var q := flow[i]
		if q > SimStream.EPS:
			var c := PackedFloat32Array()
			c.resize(species)
			var base := i * species
			for s in species:
				c[s] = comp[base + s] / q
			fresh[i] = SimStream.make(q, temp[i] / q, c, solids[i] / q)

	# A source of material overrides what the pipes brought: a vessel
	# discharging supplies its own contents, not whatever happened to
	# be in the line.
	for component in components:
		var ports := component.material_ports()
		for port_name: String in ports:
			var port: SimPort = ports[port_name]
			if port.flow_lps < -1e-12:
				var supplied := component.supplied_stream(port_name)
				if supplied != null:
					fresh[port.node] = supplied.with_flow(-port.flow_lps)

	# A vessel's contents tap holds the contents whether or not anything
	# is moving: a probe on the shell reads what is in the vessel.
	for component in components:
		for port_name: String in component.standing_ports():
			var port: SimPort = component.material_ports().get(port_name)
			if port != null and port.flow_lps > -1e-12:
				var supplied := component.supplied_stream(port_name)
				if supplied != null:
					fresh[port.node] = supplied.with_flow(0.0)

	# A line with nothing moving in it still holds what it last held.
	# Forgetting would make a restarted pump briefly deliver water it
	# never contained.
	for i in count:
		if fresh[i] == null:
			fresh[i] = previous[i] if previous[i].flow_lps == 0.0 else previous[i].with_flow(0.0)
	for tap_node: int in _tap_source:
		var watched: int = _tap_source[tap_node]
		fresh[tap_node] = fresh[watched]
		net.pressures[tap_node] = net.pressures[watched]
	_node_streams = fresh

	for component in components:
		var taps := component.tap_ports()
		var ports := component.material_ports()
		for port_name: String in ports:
			var port: SimPort = ports[port_name]
			var at_node := fresh[port.node]
			if taps.has(port_name):
				# A tap reports the line, rate included, without taking
				# any of it.
				port.stream = at_node
			else:
				var rate := absf(port.flow_lps)
				# A nozzle with one run on it already carries its own
				# rate; only a tee needs restating.
				port.stream = at_node if at_node.flow_lps == rate else at_node.with_flow(rate)


## The live network, for probes and self-checks. Null before the first
## scan.
func network() -> SimNetwork:
	return _network


## Node pressure at a nozzle, Pa gauge, or 0 before the first scan.
func pressure_at(port: SimPort) -> float:
	if _network == null or port.node < 0 or port.node >= _network.node_count():
		return 0.0
	return _network.pressures[port.node]


## ---- historian ------------------------------------------------------------

## Register every output port and observable as a tag, then take the
## t=0 baseline sample. Attach after the graph is built; equipment
## placed later registers via register_with_historian.
func attach_historian(historian_: SimHistorian) -> SimHistorian:
	historian = historian_
	for component in components:
		register_with_historian(component)
	historian_.sample(time)
	return historian_


## Every historian tag one component contributes.
##
## A material nozzle is not a number, so it fans out into the numbers
## an operator would actually trend: signed rate, temperature, how much
## of it is solid, and the fraction of each species in it. Composition
## becomes real historized data rather than something a display has to
## infer.
static func stream_tags(base: String) -> PackedStringArray:
	var tags := PackedStringArray([base + ".flow", base + ".temp", base + ".solids"])
	for i in SimSpecies.COUNT:
		tags.append(base + ".x_" + SimSpecies.key_of(i))
	return tags


func _tag_names(component: SimComponent) -> PackedStringArray:
	var tags := PackedStringArray()
	for port_name: String in component.outputs:
		var port: SimOutputPort = component.outputs[port_name]
		if SimTypes.is_material(port.kind):
			tags.append_array(stream_tags(port.path()))
		else:
			tags.append(port.path())
	for obs_name: String in component.observables:
		tags.append(component.comp_name + "." + obs_name)
	return tags


## Register one component's tags — for equipment added mid-run.
func register_with_historian(component: SimComponent) -> void:
	if historian == null:
		return
	for port_name: String in component.outputs:
		var port: SimOutputPort = component.outputs[port_name]
		if SimTypes.is_material(port.kind):
			var base := port.path()
			historian.register(base + ".flow", func() -> float: return port.flow_lps)
			historian.register(base + ".temp", func() -> float: return port.stream.temp_c)
			historian.register(base + ".solids", func() -> float: return port.stream.solids_frac)
			for i in SimSpecies.COUNT:
				var index := i
				historian.register(base + ".x_" + SimSpecies.key_of(index),
					func() -> float: return port.stream.comp[index])
		else:
			historian.register(port.path(), func() -> float: return port.value)
	for obs_name: String in component.observables:
		var comp := component
		var prop: StringName = component.observables[obs_name]
		historian.register(component.comp_name + "." + obs_name,
			func() -> float: return float(comp.get(prop)))


func unique_name(prefix: String) -> String:
	var index := 1
	while _by_name.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]


## Remove a component and every wire touching it. Its historian tags
## are retired (history kept) — pulling real equipment stops the
## record, it doesn't erase it.
func remove_component(name_: String) -> bool:
	var component: SimComponent = _by_name.get(name_)
	if component == null:
		return false
	var kept: Array[SimWire] = []
	for wire in wires:
		if wire.src.owner_name == name_ or wire.dst.owner_name == name_:
			wire.dst.wire_count -= 1
		else:
			kept.append(wire)
	wires = kept
	components.erase(component)
	_by_name.erase(name_)
	_network_stale = true
	if historian != null:
		var active := historian.active_tags()
		for tag in _tag_names(component):
			if active.has(tag):
				historian.retire(tag)
	return true


## What the other phases of a scan cost, beside solve_ms: the signal
## propagation, the component ticks and the historian's sample. The
## plant's kernel-cost line prints them (2026-09-13: a 13 ms scan on
## the main thread is the stutter the director sees).
var signal_ms: float = 0.0
var components_ms: float = 0.0
var historian_ms: float = 0.0


func tick() -> void:
	# Signals first, so a valve knows its command and a pump knows
	# whether it is running before the network is solved on them.
	var started := Time.get_ticks_usec()
	for component in components:
		for port_name: String in component.inputs:
			(component.inputs[port_name] as SimInputPort).reset()
	for wire in wires:
		wire.propagate()
	var now := Time.get_ticks_usec()
	signal_ms = (now - started) / 1000.0
	# Then solve the hydraulics: what actually flows, and which way.
	started = now
	_solve_hydraulics()
	now = Time.get_ticks_usec()
	solve_ms = (now - started) / 1000.0
	# Then let the components act on it.
	started = now
	for component in components:
		component.tick(dt)
	time += dt
	now = Time.get_ticks_usec()
	components_ms = (now - started) / 1000.0
	started = now
	if historian != null:
		historian.sample(time)
	historian_ms = (Time.get_ticks_usec() - started) / 1000.0


func run_for(seconds: float) -> void:
	for _i in roundi(seconds / dt):
		tick()


func state_dict() -> Dictionary:
	var comp_states := {}
	for component in components:
		comp_states[component.comp_name] = component.state_dict()
	return {"time": time, "components": comp_states}


func apply_state(state: Dictionary) -> void:
	time = state.get("time", 0.0)
	var comp_states: Dictionary = state.get("components", {})
	for component in components:
		if comp_states.has(component.comp_name):
			component.apply_state(comp_states[component.comp_name])
