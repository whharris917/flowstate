class_name PlantFactory
## One place that knows how to make each equipment type: sim record,
## view, placement footprint, and where its port markers sit. Both the
## commissioned starting plant and player placement go through here, so
## save/load can rebuild anything.

const CATALOG: Array[Dictionary] = [
	{"type": "tank", "label": "Tank 100 L"},
	{"type": "pump", "label": "Pump 4 L/s"},
	{"type": "relay", "label": "Relay cabinet"},
	{"type": "gauge_level", "label": "Pressure gauge"},
	{"type": "gauge_flow", "label": "Flow gauge"},
]

# Ghost/collision footprint (x, y, z) and the view's y-offset when the
# placement point is on the floor.
const FOOTPRINTS := {
	"tank": Vector3(1.8, 2.3, 1.8),
	"pump": Vector3(0.85, 0.95, 0.7),
	"relay": Vector3(1.0, 2.2, 0.55),
	"gauge_level": Vector3(0.5, 1.8, 0.5),
	"gauge_flow": Vector3(0.5, 1.8, 0.5),
	"float_switch": Vector3(0.25, 0.6, 0.25),
}
const Y_OFFSETS := {
	"tank": 0.0, "pump": 0.0, "relay": 1.5,
	"gauge_level": 0.0, "gauge_flow": 0.0, "float_switch": 0.0,
}

# Where each port's marker sits in the view's local space.
const PORT_ANCHORS := {
	"tank": {"in_flow": Vector3(0, 2.35, 0), "level": Vector3(0.95, 1.1, 0)},
	"pump": {"run": Vector3(-0.3, 0.55, 0.25), "flow": Vector3(0.42, 0.42, 0)},
	"relay": {"coil": Vector3(-0.18, -0.22, 0.14), "contact": Vector3(0.18, -0.22, 0.14)},
	"float_switch": {"level": Vector3(0, -0.22, 0.12), "contact": Vector3(0.14, 0.2, 0.1)},
	"gauge_level": {"process": Vector3(0, 0.25, 0.1), "signal": Vector3(0.2, 1.32, 0)},
	"gauge_flow": {"process": Vector3(0, 0.25, 0.1), "signal": Vector3(0.2, 1.32, 0)},
}

const KIND_COLORS := {
	SimTypes.PortKind.SIGNAL_DISCRETE: Color(0.11, 0.69, 0.48),
	SimTypes.PortKind.SIGNAL_ANALOG: Color(0.92, 0.60, 0.10),
	SimTypes.PortKind.PROCESS_FLOW: Color(0.16, 0.47, 0.84),
	SimTypes.PortKind.PROCESS_LEVEL: Color(0.15, 0.65, 0.80),
}


static func type_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in CATALOG:
		ids.append(entry["type"])
	return ids


static func make_record(sim: Simulation, type_id: String, name_: String,
		params: Dictionary) -> SimComponent:
	match type_id:
		"tank":
			return sim.add(SimTank.new(name_,
				params.get("capacity_l", 100.0),
				params.get("level_l", 0.0),
				params.get("drain_lps", 0.0)))
		"pump":
			return sim.add(SimPump.new(name_, params.get("rated_lps", 4.0)))
		"relay":
			return sim.add(SimRelay.new(name_))
		"float_switch":
			return sim.add(SimFloatSwitch.new(name_,
				params.get("low_l", 40.0), params.get("high_l", 80.0)))
		"gauge_level":
			return sim.add(SimGauge.new(name_, "level_kpa",
				params.get("liters_per_meter", 45.45)))
		"gauge_flow":
			return sim.add(SimGauge.new(name_, "flow"))
	push_error("unknown equipment type '%s'" % type_id)
	return null


static func make_view(type_id: String, record: SimComponent,
		extra: SimComponent = null) -> Node3D:
	var view: Node3D = null
	match type_id:
		"tank":
			view = TankView.new()
		"pump":
			view = PumpView.new()
		"relay":
			view = RelayView.new()
		"float_switch":
			view = FloatSwitchView.new()
		"gauge_level", "gauge_flow":
			view = GaugeView.new()
	if view == null:
		push_error("unknown equipment type '%s'" % type_id)
		return null
	view.set_meta("type_id", type_id)
	view.set_meta("record_name", record.comp_name)
	return view


## Call after the view is in the tree and set up: builds the typed port
## markers connect mode clicks on (collision layer 2).
static func attach_port_markers(view: Node3D, record: SimComponent, type_id: String) -> void:
	var anchors: Dictionary = PORT_ANCHORS.get(type_id, {})
	var markers := {}
	for port_name: String in record.inputs:
		var anchor: Vector3 = anchors.get(port_name, Vector3(0, 0.5, 0))
		markers[port_name] = _marker(view, record, record.inputs[port_name], anchor, true)
	for port_name: String in record.outputs:
		var anchor: Vector3 = anchors.get(port_name, Vector3(0, 0.8, 0))
		markers[port_name] = _marker(view, record, record.outputs[port_name], anchor, false)
	view.set_meta("port_markers", markers)


static func _marker(view: Node3D, record: SimComponent, port: SimPort,
		local_pos: Vector3, is_input: bool) -> StaticBody3D:
	var color: Color = KIND_COLORS[port.kind]
	var body := StaticBody3D.new()
	body.position = local_pos
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.09
	shape.shape = sphere_shape
	body.add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	if is_input:
		var sphere := SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		mesh_inst.mesh = sphere
	else:
		var cube := BoxMesh.new()
		cube.size = Vector3(0.1, 0.1, 0.1)
		mesh_inst.mesh = cube
	mesh_inst.material_override = ViewUtil.glow(color, 1.0)
	body.add_child(mesh_inst)
	var tag := Label3D.new()
	tag.text = port.port_name
	tag.position = Vector3(0, 0.14, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 26
	tag.pixel_size = 0.003
	body.add_child(tag)
	body.set_meta("record_name", record.comp_name)
	body.set_meta("port_name", port.port_name)
	body.set_meta("is_input", is_input)
	body.set_meta("kind", port.kind)
	body.set_meta("owner_view", view)
	view.add_child(body)
	return body
