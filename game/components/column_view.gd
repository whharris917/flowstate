class_name ColumnView
extends Node3D
## Renders a SimColumn: a 10.5 m column on a skirt — tray flanges up
## the shell, a caged ladder, feed and vapor nozzles, and a top
## platform with railings where the overhead instrumentation lives.
## The reboiler band at the base glows with the actual duty. E cycles
## the reboiler off -> half -> full.

const COL_SHELL := Color(0.72, 0.74, 0.76)
const COL_STEEL := Color(0.16, 0.17, 0.19)
const COL_DECK := Color(0.34, 0.35, 0.37)
const COL_FLANGE := Color(0.60, 0.62, 0.64)
const COL_INSUL := Color(0.82, 0.82, 0.79)

const SHELL_R := 0.55
const SHELL_TOP := 10.4
const PLATFORM_Y := 9.6

var column: SimColumn
var _reboiler_mat: StandardMaterial3D
var _rumble: EquipmentAudio
var _plume: VaporPlume


func setup(column_: SimColumn) -> void:
	column = column_
	_build_shell()
	_build_trays_and_nozzles()
	_build_ladder()
	_build_platform()
	_build_top_head()
	ViewUtil.label(self, column.comp_name, Vector3(0, 11.6, 0))
	ViewUtil.interact_body(self, Vector3(1.6, 2.2, 1.6), Vector3(0, 1.1, 0))
	# A second interact volume at the platform so the column answers E
	# (and shows its describe line) from the top as well.
	ViewUtil.interact_body(self, Vector3(1.5, 1.6, 1.5), Vector3(0, 10.3, 0))
	_rumble = EquipmentAudio.make(self, "res://audio/boiler_loop.wav",
		Vector3(0, 1.15, 0), -10.0, 0.9)
	_plume = VaporPlume.make(self, Vector3(0, SHELL_TOP + 0.95, 1.15), 0.9)


func _build_shell() -> void:
	# Skirt, base ring, and the reboiler band that glows with duty.
	ViewUtil.cylinder(self, SHELL_R + 0.08, 1.3, Vector3(0, 0.65, 0), ViewUtil.flat(COL_STEEL))
	ViewUtil.cylinder(self, SHELL_R + 0.16, 0.1, Vector3(0, 0.05, 0), ViewUtil.flat(COL_STEEL))
	_reboiler_mat = ViewUtil.glow(Color(0.85, 0.45, 0.10), 0.0)
	ViewUtil.cylinder(self, SHELL_R + 0.10, 0.35, Vector3(0, 1.15, 0), _reboiler_mat)
	# Shell proper, 1.3 -> 10.4 m.
	ViewUtil.cylinder(self, SHELL_R, SHELL_TOP - 1.3,
		Vector3(0, (1.3 + SHELL_TOP) / 2.0, 0), ViewUtil.flat(COL_SHELL))


func _build_trays_and_nozzles() -> void:
	# Tray flange rings every 0.75 m mark the internals.
	var y := 2.2
	while y < 9.2:
		ViewUtil.cylinder(self, SHELL_R + 0.035, 0.06, Vector3(0, y, 0),
			ViewUtil.flat(COL_FLANGE))
		y += 0.75
	# Insulation band over the rectifying section.
	ViewUtil.cylinder(self, SHELL_R + 0.055, 2.6, Vector3(0, 7.0, 0), ViewUtil.flat(COL_INSUL))
	# Manways: one low, one high, on the +z face.
	for man_y: float in [2.6, 8.8]:
		var man := ViewUtil.cylinder(self, 0.26, 0.10, Vector3(0, man_y, SHELL_R + 0.02),
			ViewUtil.flat(COL_FLANGE))
		man.rotation_degrees = Vector3(90, 0, 0)
	# Feed nozzle at mid-height, +x, with a stub flange.
	var feed := ViewUtil.cylinder(self, 0.09, 0.6, Vector3(SHELL_R + 0.25, 5.6, 0),
		ViewUtil.flat(COL_FLANGE))
	feed.rotation_degrees = Vector3(0, 0, 90)
	var feed_flange := ViewUtil.cylinder(self, 0.15, 0.06, Vector3(SHELL_R + 0.55, 5.6, 0),
		ViewUtil.flat(COL_STEEL))
	feed_flange.rotation_degrees = Vector3(0, 0, 90)


func _build_ladder() -> void:
	# Rails, rungs, and cage hoops on the -z side, base to platform.
	var rail_h := PLATFORM_Y + 1.1
	for rail_x: float in [-0.22, 0.22]:
		ViewUtil.box(self, Vector3(0.05, rail_h, 0.05),
			Vector3(rail_x, rail_h / 2.0, -SHELL_R - 0.22), ViewUtil.flat(COL_STEEL))
	var rung_y := 0.35
	while rung_y < rail_h - 0.2:
		ViewUtil.box(self, Vector3(0.44, 0.035, 0.035),
			Vector3(0, rung_y, -SHELL_R - 0.22), ViewUtil.flat(COL_STEEL))
		rung_y += 0.32
	# Safety cage hoops from 2.5 m up.
	var hoop_y := 2.5
	while hoop_y < PLATFORM_Y - 0.2:
		var hoop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.46
		hoop.mesh = torus
		hoop.material_override = ViewUtil.flat(COL_STEEL)
		hoop.position = Vector3(0, hoop_y, -SHELL_R - 0.28)
		add_child(hoop)
		hoop_y += 1.2


func _build_platform() -> void:
	# One-sided top platform on +z with railings and a kickplate.
	var deck_size := Vector3(1.9, 0.08, 1.3)
	var deck_pos := Vector3(0, PLATFORM_Y, SHELL_R + 0.62)
	var body := StaticBody3D.new()
	body.position = deck_pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = deck_size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = deck_size
	mesh.mesh = deck_mesh
	mesh.material_override = ViewUtil.flat(COL_DECK)
	body.add_child(mesh)
	add_child(body)
	# Railings around the three open edges.
	var half_x := deck_size.x / 2.0
	var far_z := deck_pos.z + deck_size.z / 2.0
	var near_z := deck_pos.z - deck_size.z / 2.0
	for post: Vector3 in [
			Vector3(-half_x, 0, near_z), Vector3(-half_x, 0, far_z),
			Vector3(half_x, 0, near_z), Vector3(half_x, 0, far_z)]:
		ViewUtil.box(self, Vector3(0.05, 1.0, 0.05),
			Vector3(post.x, PLATFORM_Y + 0.54, post.z), ViewUtil.flat(COL_STEEL))
	for rail_y: float in [PLATFORM_Y + 0.55, PLATFORM_Y + 1.0]:
		ViewUtil.box(self, Vector3(deck_size.x, 0.05, 0.05),
			Vector3(0, rail_y, far_z), ViewUtil.flat(COL_STEEL))
		for side_x: float in [-half_x, half_x]:
			ViewUtil.box(self, Vector3(0.05, 0.05, deck_size.z),
				Vector3(side_x, rail_y, deck_pos.z), ViewUtil.flat(COL_STEEL))
	ViewUtil.box(self, Vector3(deck_size.x, 0.12, 0.03),
		Vector3(0, PLATFORM_Y + 0.1, far_z), ViewUtil.flat(Color(0.95, 0.78, 0.05)))


func _build_top_head() -> void:
	# Dished head, overhead vapor line to the condenser vent, relief
	# valve on its own stub, and a little davit for tray maintenance.
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SHELL_R
	sphere.height = 0.7
	dome.mesh = sphere
	dome.material_override = ViewUtil.flat(COL_SHELL)
	dome.position = Vector3(0, SHELL_TOP, 0)
	add_child(dome)
	# Overhead line: up, then a hard elbow out over the platform edge.
	ViewUtil.cylinder(self, 0.11, 0.7, Vector3(0, SHELL_TOP + 0.55, 0),
		ViewUtil.flat(COL_FLANGE))
	var elbow := MeshInstance3D.new()
	var elbow_mesh := SphereMesh.new()
	elbow_mesh.radius = 0.13
	elbow_mesh.height = 0.26
	elbow.mesh = elbow_mesh
	elbow.material_override = ViewUtil.flat(COL_FLANGE)
	elbow.position = Vector3(0, SHELL_TOP + 0.9, 0)
	add_child(elbow)
	var run := ViewUtil.cylinder(self, 0.11, 1.1, Vector3(0, SHELL_TOP + 0.9, 0.55),
		ViewUtil.flat(COL_FLANGE))
	run.rotation_degrees = Vector3(90, 0, 0)
	# Relief valve on a stub beside the vapor line.
	ViewUtil.cylinder(self, 0.06, 0.35, Vector3(-0.3, SHELL_TOP + 0.4, 0),
		ViewUtil.flat(COL_FLANGE))
	ViewUtil.box(self, Vector3(0.16, 0.2, 0.16), Vector3(-0.3, SHELL_TOP + 0.65, 0),
		ViewUtil.flat(Color(0.75, 0.20, 0.15)))
	var horn := ViewUtil.cylinder(self, 0.05, 0.3, Vector3(-0.45, SHELL_TOP + 0.72, 0),
		ViewUtil.flat(COL_FLANGE))
	horn.rotation_degrees = Vector3(0, 0, 90)
	# Davit: post and arm.
	ViewUtil.box(self, Vector3(0.07, 1.1, 0.07), Vector3(0.42, SHELL_TOP + 0.5, -0.25),
		ViewUtil.flat(COL_STEEL))
	ViewUtil.box(self, Vector3(0.07, 0.07, 0.8), Vector3(0.42, SHELL_TOP + 1.05, 0.1),
		ViewUtil.flat(COL_STEEL))


func _process(_delta: float) -> void:
	_reboiler_mat.emission_energy_multiplier = 1.8 * column.duty_frac
	_rumble.set_running(column.duty_kw > 1.0)
	_plume.set_strength(column.duty_frac)


func describe() -> String:
	return "%s — reboiler %.0f kW (E cycles)\nsump %.1f °C · overhead %.1f kPa · boilup %.3f kg/s" % [
		column.comp_name, column.duty_kw, column.temp_c,
		column.p_top_pa / 1000.0, column.boilup_kgps]


func use() -> void:
	column.step_duty()
