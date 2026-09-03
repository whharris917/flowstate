class_name TankView
extends Node3D
## Renders a SimTank as an opaque vessel sized by the record's real
## height and diameter, with three sight-glass strips at 120° whose
## liquid columns are the actual level fraction. Connections are
## realistic flanged nozzles welded to the shell — grab one with G in
## connect mode and re-position it anywhere on the surface. E opens
## the size editor. Render only — all numbers come from the record.

var tank: SimTank
var switch: SimFloatSwitch
var config_cb: Callable = Callable()
## Instruments on the shell (level switches, transmitters). Children of
## this view, so they follow a resize; their local +x is the outward
## normal at the mount, the same frame a nozzle gets.
var mounted: Array[Node3D] = []

# port -> {"frac": 0..1 height fraction, "angle": radians}. There is no
# level nozzle: a level instrument is mounted on the shell instead.
var nozzles := {
	"inlet": {"frac": 0.92, "angle": 2.4},
	"outlet": {"frac": 0.10, "angle": -0.7},
}

var _strips: Array[MeshInstance3D] = []
var _nozzle_nodes: Dictionary = {}   # port -> Node3D
var _built: Node3D = null
var _alarm_t: float = 0.0


func setup(tank_: SimTank, switch_: SimFloatSwitch = null) -> void:
	tank = tank_
	switch = switch_
	rebuild()


func rebuild() -> void:
	if _built != null:
		_built.queue_free()
	_strips.clear()
	_nozzle_nodes.clear()
	_built = Node3D.new()
	add_child(_built)
	var h := tank.height_m
	var r := tank.diameter_m / 2.0

	var shell_mat := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	shell_mat.metallic = 0.55
	shell_mat.roughness = 0.35
	ViewUtil.cylinder(_built, r, h, Vector3(0, h / 2.0, 0), shell_mat)
	ViewUtil.cylinder(_built, r + 0.04, 0.06, Vector3(0, h - 0.02, 0), shell_mat)
	ViewUtil.cylinder(_built, r + 0.04, 0.08, Vector3(0, 0.04, 0),
		ViewUtil.flat(Color(0.34, 0.35, 0.37)))

	# Three sight glasses at 120°: frame, glass, and a liquid column
	# driven by the real level each frame.
	var glass_mat := ViewUtil.flat(Color(0.80, 0.88, 0.92, 0.35))
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var liquid_mat := ViewUtil.glow(Color(0.16, 0.47, 0.84), 0.35)
	for i in range(3):
		var angle := TAU / 3.0 * i + 0.35
		var dir := Vector3(cos(angle), 0, sin(angle))
		var out := dir * (r + 0.015)
		var strip_h := h - 0.3
		var basis := Basis.looking_at(dir, Vector3.UP)
		var frame := ViewUtil.box(_built, Vector3(0.11, strip_h + 0.08, 0.03), Vector3.ZERO,
			ViewUtil.flat(Color(0.30, 0.31, 0.33)))
		frame.position = out + Vector3(0, h / 2.0, 0)
		frame.basis = basis
		var glass := ViewUtil.box(_built, Vector3(0.07, strip_h, 0.035), Vector3.ZERO, glass_mat)
		glass.position = dir * (r + 0.02) + Vector3(0, h / 2.0, 0)
		glass.basis = basis
		var liquid := ViewUtil.box(_built, Vector3(0.05, 1.0, 0.03), Vector3.ZERO, liquid_mat)
		liquid.basis = basis
		liquid.set_meta("dir", dir)
		liquid.set_meta("strip_h", strip_h)
		_strips.append(liquid)

	# Trip rings for every switch on the shell.
	for trip_switch in _trip_switches():
		for trip_l: float in [trip_switch.low_l, trip_switch.high_l]:
			ViewUtil.cylinder(_built, r + 0.02, 0.02,
				Vector3(0, h * clampf(trip_l / tank.capacity_l, 0.0, 1.0), 0),
				ViewUtil.flat(Color(0.54, 0.53, 0.51)))

	ViewUtil.label(_built, tank.comp_name, Vector3(0, h + 0.45, 0))
	ViewUtil.interact_body(_built, Vector3(r * 2.2, h, r * 2.2), Vector3(0, h / 2.0, 0))

	var markers := {}
	for port: String in nozzles:
		markers["%s:%s" % [tank.comp_name, port]] = _build_nozzle(port)
	set_meta("port_markers", markers)
	for inst in mounted:
		_place_mounted(inst)


## Put an instrument on the shell at a height fraction and a bearing.
func mount(view: Node3D, frac: float, angle: float) -> void:
	if view.get_parent() != self:
		add_child(view)
	view.set_meta("mount_frac", clampf(frac, 0.04, 0.97))
	view.set_meta("mount_angle", angle)
	if not mounted.has(view):
		mounted.append(view)
	_place_mounted(view)
	if view is FloatSwitchView:
		rebuild()  # its trip rings


func unmount(view: Node3D) -> void:
	mounted.erase(view)
	if view is FloatSwitchView:
		rebuild()


func _place_mounted(view: Node3D) -> void:
	var r := tank.diameter_m / 2.0
	var angle := float(view.get_meta("mount_angle", 0.0))
	var dir := Vector3(cos(angle), 0, sin(angle))
	view.position = dir * r + Vector3(0, tank.height_m * float(view.get_meta("mount_frac", 0.5)), 0)
	view.basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP))


func _trip_switches() -> Array[SimFloatSwitch]:
	var out: Array[SimFloatSwitch] = []
	if switch != null:
		out.append(switch)
	for inst in mounted:
		if inst is FloatSwitchView:
			var record := (inst as FloatSwitchView).switch
			if not out.has(record):
				out.append(record)
	return out


## A flanged stub welded to the shell: pipe neck + flange + bolts
## suggestion, carrying the connect-mode metadata. Movable with G.
func _build_nozzle(port: String) -> StaticBody3D:
	var spot: Dictionary = nozzles[port]
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.14
	shape.shape = sphere
	body.add_child(shape)

	var is_level := port == "level"
	var neck_r := 0.045 if is_level else 0.085
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	var neck := ViewUtil.cylinder(body, neck_r, 0.22, Vector3.ZERO, steel)
	neck.rotation_degrees = Vector3(0, 0, 90)
	var flange := ViewUtil.cylinder(body, neck_r * 1.9, 0.045, Vector3(0.13, 0, 0), steel)
	flange.rotation_degrees = Vector3(0, 0, 90)
	var ring := ViewUtil.cylinder(body, neck_r * 1.35, 0.05, Vector3(0.155, 0, 0),
		ViewUtil.flat(PlantFactory.KIND_COLORS[SimTypes.PortKind.PROCESS_LEVEL if is_level
			else SimTypes.PortKind.PROCESS_MATERIAL]))
	ring.rotation_degrees = Vector3(0, 0, 90)
	var tag := Label3D.new()
	tag.text = port
	tag.position = Vector3(0.16, 0.16, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 24
	tag.pixel_size = 0.003
	body.add_child(tag)

	body.set_meta("record_name", tank.comp_name)
	body.set_meta("port_name", port)
	body.set_meta("is_input", port == "inlet")
	body.set_meta("kind", SimTypes.PortKind.PROCESS_LEVEL if is_level
		else SimTypes.PortKind.PROCESS_MATERIAL)
	body.set_meta("owner_view", self)
	body.set_meta("movable", true)
	_built.add_child(body)
	_nozzle_nodes[port] = body
	_place_nozzle(body, spot)
	return body


func _place_nozzle(body: StaticBody3D, spot: Dictionary) -> void:
	var r := tank.diameter_m / 2.0
	var angle := float(spot["angle"])
	var dir := Vector3(cos(angle), 0, sin(angle))
	body.position = dir * (r + 0.10) + Vector3(0, tank.height_m * float(spot["frac"]), 0)
	# The neck's local +X points outward, along the shell normal.
	body.basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP))


## Move a nozzle to a new spot on the shell (G-grab commit).
func set_nozzle(port: String, frac: float, angle: float) -> void:
	if not nozzles.has(port):
		return
	nozzles[port] = {"frac": clampf(frac, 0.04, 0.97), "angle": angle}
	_place_nozzle(_nozzle_nodes[port], nozzles[port])


func get_nozzles() -> Dictionary:
	return nozzles.duplicate(true)


func apply_nozzles(saved: Dictionary) -> void:
	for port: String in saved:
		if nozzles.has(port):
			var spot: Dictionary = saved[port]
			set_nozzle(port, float(spot.get("frac", 0.5)), float(spot.get("angle", 0.0)))


func _process(delta: float) -> void:
	var h := tank.height_m
	var r := tank.diameter_m / 2.0
	var frac := clampf(tank.level_l / tank.capacity_l, 0.0, 1.0)
	for liquid in _strips:
		var strip_h: float = liquid.get_meta("strip_h")
		var dir: Vector3 = liquid.get_meta("dir")
		var column := maxf(strip_h * frac, 0.005)
		liquid.scale = Vector3(1, column, 1)
		liquid.position = dir * (r + 0.025) + Vector3(0, 0.15 + column / 2.0, 0)
	# Local high-level annunciator: repeats while the real level sits
	# above 92% of capacity.
	if frac > 0.92:
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = 1.6
			EquipmentAudio.play_once(self, "res://audio/beep.wav",
				Vector3(0, h + 0.2, 0), -6.0, 1.0)
	else:
		_alarm_t = 0.0


## What a person at the vessel can see: its size, the sight glass, and
## the face of every instrument mounted on it. Nothing else.
func describe() -> String:
	var lines: Array[String] = ["%s — %.0f L vessel, %.1f m × ⌀%.1f m (E resizes)" % [
		tank.comp_name, tank.capacity_l, tank.height_m, tank.diameter_m]]
	lines.append("sight glass reads %.0f L" % tank.level_l)
	var faces: Array[String] = []
	for inst in mounted:
		if inst.has_method("summary"):
			faces.append(str(inst.call("summary")))
	if not faces.is_empty():
		lines.append(" · ".join(faces))
	if tank.overflowed_l > 0.0:
		lines.append("overflowed %.1f L" % tank.overflowed_l)
	return "\n".join(lines)


func use() -> void:
	if config_cb.is_valid():
		config_cb.call(self)
