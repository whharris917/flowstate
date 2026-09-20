class_name AssetPreview
## Display-only copies of catalog assets — the same geometry the real
## views build, with labels stripped, collision disabled, and
## processing frozen. Used by the build menu's rendered thumbnails and
## by the placement ghost, so previews can never drift from the real
## thing.


static func build(type_id: String) -> Node3D:
	var node: Node3D = null
	if StructureFactory.RUNS.has(type_id):
		# A short demo elbow of the run, for thumbnails.
		var spec: Dictionary = StructureFactory.RUNS[type_id]
		var run := PipeView.new()
		run.setup([Vector3(-0.7, 0.15, 0), Vector3(0.5, 0.15, 0), Vector3(0.5, 1.0, 0)],
			func() -> float: return 0.0,
			spec["color"], spec["radius"], "", spec["style"], 0)
		node = run
	elif StructureFactory.SIZES.has(type_id):
		node = StructureFactory.make_view(type_id, "preview")
	elif type_id == "cabinet":
		var cab := CabinetView.new()
		cab.setup("cabinet")
		node = cab
	elif type_id == "junction_box":
		var jb := JunctionBoxView.new()
		jb.setup("junction box", 12, true)
		node = jb
	elif type_id == "control_station":
		var scratch_station := Simulation.new(0.05)
		var lcs := ControlStationView.new()
		lcs.setup("control station", [
			{"record": scratch_station.add(SimPushbutton.new("start")), "legend": "START", "color": "green"},
			{"record": scratch_station.add(SimPushbutton.new("stop", true, true)), "legend": "STOP", "color": "red"},
			{"record": scratch_station.add(SimPilotLight.new("running")), "legend": "RUNNING", "color": "green"},
			{"record": scratch_station.add(SimPilotLight.new("stopped", "red")), "legend": "STOPPED", "color": "red"},
		], true)
		lcs.set_meta("scratch_sim", scratch_station)
		node = lcs
	else:
		# A scratch sim graph backs the preview records; it is never
		# ticked and dies with the preview node (kept alive via meta).
		var scratch := Simulation.new(0.05)
		var record := PlantFactory.make_record(scratch, type_id, "preview", {})
		if record == null:
			return null
		node = PlantFactory.make_view(type_id, record)
		match type_id:
			"tank":
				(node as TankView).setup(record as SimTank, null)
			"pump":
				(node as PumpView).setup(record as SimPump)
			"relay":
				(node as RelayView).setup(record as SimRelay)
			"hmi_trend":
				(node as TrendScreenView).setup_trend(record as SimTrendScreen, null)
			"tee_split", "tee_mix":
				(node as TeeView).setup(record as SimTee)
			"float_switch":
				(node as FloatSwitchView).setup(record as SimFloatSwitch)
			"gauge_level", "gauge_flow", "gauge_dp", "gauge_press":
				(node as GaugeView).setup(record as SimGauge)
			"column":
				(node as ColumnView).setup(record as SimColumn)
			"valve":
				(node as ControlValveView).setup(record as SimControlValve)
			"block_valve":
				(node as BlockValveView).setup(record as SimBlockValve)
			"controller":
				(node as PIDView).setup(record as SimPID)
			"mains":
				(node as MainsView).setup(record as SimMainsFeed)
			"psu":
				(node as PsuView).setup(record as SimPowerSupply)
			"source":
				(node as SourceView).setup(record as SimSource)
			"drain":
				(node as DrainView).setup(record as SimDrain)
			"reactor":
				(node as ReactorView).setup(record as SimReactor)
			"centrifuge":
				(node as CentrifugeView).setup(record as SimCentrifuge)
			"hx":
				(node as HeatExchangerView).setup(record as SimHeatExchanger)
			"steamgen":
				(node as SteamGenView).setup(record as SimSteamGen)
			"vaclock":
				(node as VacLockView).setup(record as SimVacuumLock)
			"vialfill":
				(node as VialFillerView).setup(record as SimVialFiller)
			"orifice":
				(node as OrificeView).setup(record as SimOrifice)
			"needle_valve":
				(node as NeedleValveView).setup(record as SimNeedleValve)
			"ball_valve":
				(node as BallValveView).setup(record as SimBallValve)
			"solenoid_valve":
				(node as SolenoidValveView).setup(record as SimSolenoidValve)
			"metering_pump":
				(node as MeteringPumpView).setup(record as SimMeteringPump)
			"regulator":
				(node as RegulatorView).setup(record as SimRegulator)
			"rotameter":
				(node as RotameterView).setup(record as SimRotameter)
		node.set_meta("scratch_sim", scratch)
	if node == null:
		return null
	_strip(node)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	return node


## The node's base sits this far below its origin point when placed on
## a floor — mirrors Plant.place and structure placement conventions.
static func base_offset(type_id: String) -> float:
	if StructureFactory.SIZES.has(type_id):
		return (StructureFactory.SIZES[type_id] as Vector3).y / 2.0
	return PlantFactory.Y_OFFSETS.get(type_id, 0.0)


static func _strip(node: Node) -> void:
	for child in node.get_children():
		_strip(child)
	if node is Label3D:
		node.queue_free()
	elif node is StaticBody3D:
		(node as StaticBody3D).collision_layer = 0
		(node as StaticBody3D).collision_mask = 0


## Override every mesh with one shared material (the ghost tint).
static func tint(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		tint(child, mat)


## Merged AABB of all mesh geometry, in the node's own space.
static func bounds(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var merged := boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	return merged


static func _collect_bounds(node: Node, xform: Transform3D, boxes: Array[AABB]) -> void:
	if node is Node3D:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		boxes.append(xform * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_bounds(child, xform, boxes)
