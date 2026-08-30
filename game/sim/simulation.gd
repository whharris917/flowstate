class_name Simulation
## Owns the component graph and advances it at a fixed rate.
##
## Tick order (one scan): input ports reset, wires copy last scan's
## outputs into inputs, components tick in insertion order, historian
## samples. Components only ever read their own input ports, so results
## are deterministic regardless of build order, and every hop through
## the graph costs one scan of latency — real relay/PLC scan delay,
## which is what makes chatter physically reproducible.

var dt: float
var time: float = 0.0
var components: Array[SimComponent] = []
var wires: Array[SimWire] = []
var historian: SimHistorian = null

var _by_name: Dictionary = {}  # String -> SimComponent


func _init(dt_: float = 0.05) -> void:
	assert(dt_ > 0.0, "dt must be positive")
	dt = dt_


func add(component: SimComponent) -> SimComponent:
	if _by_name.has(component.comp_name):
		push_error("duplicate component name '%s'" % component.comp_name)
		return component
	_by_name[component.comp_name] = component
	components.append(component)
	return component


func get_component(name_: String) -> SimComponent:
	return _by_name.get(name_)


## Returns true when the wire was made. Kind mismatches and second
## wires into single-source inputs are rejected with an error.
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
	if in_port.wire_count > 0 and not SimTypes.allows_multiple_sources(in_port.kind):
		push_error("%s (%s) accepts only one wire" % [in_port.path(), SimTypes.kind_name(in_port.kind)])
		return false
	wires.append(SimWire.new(out_port, in_port))
	return true


## Register every output port and observable as a tag, then take the
## t=0 baseline sample. Attach after the graph is built.
func attach_historian(historian_: SimHistorian) -> SimHistorian:
	for component in components:
		for port_name: String in component.outputs:
			var port: SimOutputPort = component.outputs[port_name]
			historian_.register(port.path(), func() -> float: return port.value)
		for obs_name: String in component.observables:
			var comp := component
			var prop: StringName = component.observables[obs_name]
			historian_.register(component.comp_name + "." + obs_name,
				func() -> float: return float(comp.get(prop)))
	historian = historian_
	historian_.sample(time)
	return historian_


func tick() -> void:
	for component in components:
		for port_name: String in component.inputs:
			(component.inputs[port_name] as SimInputPort).reset()
	for wire in wires:
		wire.propagate()
	for component in components:
		component.tick(dt)
	time += dt
	if historian != null:
		historian.sample(time)


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
