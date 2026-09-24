class_name Gallery
## Unit 500: a geometry showcase.
## Nothing here simulates anything; it exists so the director can see
## what high-detail placeholder art looks like before any of it is
## backed by a record. Four exhibits south of Unit 400: a tall
## bioreactor with a stair tower to its head, an autoclave, a large
## isolator with glove ports, and a QC lab. This is the one deliberate
## exception to "every visual object is backed by a sim record"; keep
## it in this file so it can be promoted or deleted piece by piece.
##
## Coordinates are world space. The stair tower, walls and catwalk are
## real structure records (placed through the plant, so the support
## rule and the stair rule apply); everything else is meshes on one
## node with static colliders where the player could walk into it.

# ---- palette ----------------------------------------------------------
static var STAINLESS := _mat(Color(0.74, 0.76, 0.79), 0.8, 0.28)
static var STAINLESS_DARK := _mat(Color(0.55, 0.57, 0.60), 0.7, 0.4)
static var STEEL := _mat(Color(0.30, 0.32, 0.35), 0.4, 0.6)
static var PAINT_WHITE := _mat(Color(0.90, 0.91, 0.90), 0.0, 0.5)
static var PAINT_GREY := _mat(Color(0.62, 0.64, 0.66), 0.0, 0.6)
static var PAINT_BLUE := _mat(Color(0.20, 0.34, 0.55), 0.1, 0.5)
static var EPOXY := _mat(Color(0.10, 0.10, 0.11), 0.0, 0.35)
static var RUBBER := _mat(Color(0.12, 0.12, 0.14), 0.0, 0.9)
static var BRASS := _mat(Color(0.78, 0.62, 0.30), 0.8, 0.35)
static var RED := _mat(Color(0.75, 0.12, 0.10), 0.0, 0.5)
static var YELLOW := _mat(Color(0.95, 0.78, 0.05), 0.0, 0.5)
static var GLASS := _glass(Color(0.80, 0.90, 0.95, 0.30))
static var GLASS_TINT := _glass(Color(0.65, 0.80, 0.88, 0.45))
static var SCREEN := ViewUtil.glow(Color(0.35, 0.75, 0.95), 0.9)
static var LAMP_GREEN := ViewUtil.glow(Color(0.10, 0.80, 0.35), 1.2)
static var LAMP_AMBER := ViewUtil.glow(Color(0.95, 0.65, 0.10), 1.2)
static var LIGHT := ViewUtil.glow(Color(0.95, 0.96, 0.90), 1.4)


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.2
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _liquid(color: Color) -> StandardMaterial3D:
	var m := ViewUtil.glow(color, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.85)
	return m


# ---- mesh kit -----------------------------------------------------------

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var inst := ViewUtil.box(parent, size, pos, mat)
	inst.rotation_degrees = rot_deg
	return inst


## A cylinder along y; give top_r for a cone or a taper.
static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: StandardMaterial3D,
		rot_deg: Vector3 = Vector3.ZERO, top_r: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r
	mesh.top_radius = r if top_r < 0.0 else top_r
	mesh.height = h
	mesh.radial_segments = 32
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.rotation_degrees = rot_deg
	parent.add_child(inst)
	return inst


static func _sphere(parent: Node3D, r: float, pos: Vector3, mat: StandardMaterial3D,
		scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.scale = scale
	parent.add_child(inst)
	return inst


## A ring in the XZ plane (around y); rotate to stand it up.
static func _torus(parent: Node3D, ring_r: float, tube_r: float, pos: Vector3,
		mat: StandardMaterial3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ring_r - tube_r
	mesh.outer_radius = ring_r + tube_r
	mesh.rings = 48
	mesh.ring_segments = 16
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.rotation_degrees = rot_deg
	parent.add_child(inst)
	return inst


static func _collide_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)


static func _collide_cyl(parent: Node3D, r: float, h: float, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	shape.shape = cyl
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)


static func _label(parent: Node3D, text: String, pos: Vector3, size: int = 40) -> Label3D:
	var l := ViewUtil.plate(parent, text, pos)
	l.font_size = size
	return l


## A flanged nozzle: neck, flange ring, bolt heads. dir is the outward
## axis (unit vector), the neck starts at pos.
static func _nozzle(parent: Node3D, pos: Vector3, dir: Vector3, r: float, length: float,
		mat: StandardMaterial3D = STAINLESS) -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	var node := Node3D.new()
	node.position = pos
	node.basis = basis
	parent.add_child(node)
	# In the node's frame -z is outward.
	_cyl(node, r, length, Vector3(0, 0, -length / 2.0), mat, Vector3(90, 0, 0))
	_cyl(node, r * 1.7, 0.03, Vector3(0, 0, -length + 0.015), mat, Vector3(90, 0, 0))
	for i in 8:
		var a := TAU / 8.0 * i
		_cyl(node, r * 0.14, 0.03, Vector3(cos(a) * r * 1.4, sin(a) * r * 1.4, -length - 0.012),
			STEEL, Vector3(90, 0, 0))


## A handwheel: rim, three spokes, hub. Faces along +z of its own node.
static func _handwheel(parent: Node3D, pos: Vector3, r: float, mat: StandardMaterial3D = STEEL,
		rot_deg: Vector3 = Vector3.ZERO) -> void:
	var node := Node3D.new()
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	_torus(node, r, r * 0.09, Vector3.ZERO, mat, Vector3(90, 0, 0))
	for i in 3:
		_box(node, Vector3(r * 0.08, r * 2.0, r * 0.08), Vector3.ZERO, mat, Vector3(0, 0, 60.0 * i))
	_cyl(node, r * 0.22, 0.06, Vector3.ZERO, mat, Vector3(90, 0, 0))


## A short pipe between two points, with a small elbow ball at the end.
static func _pipe(parent: Node3D, a: Vector3, b: Vector3, r: float,
		mat: StandardMaterial3D = STAINLESS_DARK, elbow: bool = true) -> void:
	var seg := PipeView.segment_node(a, b, r, "pipe", mat)
	parent.add_child(seg)
	if elbow:
		_sphere(parent, r * 1.05, b, mat)


# ---- entry point --------------------------------------------------------

static func build(plant: Plant, world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Gallery"
	world.add_child(root)
	_stair_tower(plant)
	_bioreactor(root)
	_autoclave(root)
	_isolator(root)
	_lab(plant, root)
	plant.place_structure("s_sign", "sign_u500", Vector3(2.0, 0.0, 24.6), 0.0)
	plant.set_sign_text("sign_u500", "UNIT 500\nGALLERY")


# ---- the bioreactor and its stair tower -----------------------------------

## A four-bay frame along z (A 27..31, B 31..35, C 35..39, D 39..43):
## L1 over A and B, L2 over C and D, L3 over B, so every flight climbs
## under open sky. A bay is 4 m and a flight is 4.4 m plus 0.4 m of
## foot, so a flight can never climb inside the footprint of the deck
## it serves: the deck above it has to be missing. Flight 1 comes in from the aisle onto L1's
## east edge; flight 2 climbs south up bay B's west strip onto L2;
## flight 3 climbs north up bay C's east strip onto L3; the catwalk
## leaves L3 westward to the vessel head.
static func _stair_tower(plant: Plant) -> void:
	for z: float in [27.0, 31.0, 35.0, 39.0, 43.0]:
		for x: float in [-4.0, 0.0]:
			plant.place_structure("s_column", "u500_col_%d_%d" % [int(-x), int(z)],
				Vector3(x, 0.0, z), 0.0)
			if z == 31.0 or z == 35.0:
				plant.place_structure("s_column", "u500_col_%d_%d_up" % [int(-x), int(z)],
					Vector3(x, 6.0, z), 0.0)
	# Beams under each level's bays, decks on them.
	var levels := {2.7: [29.0, 33.0], 5.7: [37.0, 41.0], 8.7: [33.0]}
	for tier: float in levels:
		var centers: Array = levels[tier]
		var t := int(tier * 10.0)
		var edges: Array[float] = []
		for c: float in centers:
			if not edges.has(c - 2.0):
				edges.append(c - 2.0)
			if not edges.has(c + 2.0):
				edges.append(c + 2.0)
		for z: float in edges:
			plant.place_structure("s_beam", "u500_beam_%d_x%d" % [t, int(z)], Vector3(-2, tier, z), 0.0, 4.0)
		for c: float in centers:
			plant.place_structure("s_beam", "u500_beam_%d_w%d" % [t, int(c)], Vector3(-4, tier, c), PI / 2.0, 4.0)
			plant.place_structure("s_beam", "u500_beam_%d_e%d" % [t, int(c)], Vector3(0, tier, c), PI / 2.0, 4.0)
			plant.place_structure("s_deck", "u500_deck_%d_%d" % [t, int(c)], Vector3(-2, tier + 0.175, c), 0.0)
	# Top ring over bay B for the frame's look.
	plant.place_structure("s_beam", "u500_beam_top_n", Vector3(-2, 11.7, 31), 0.0, 4.0)
	plant.place_structure("s_beam", "u500_beam_top_s", Vector3(-2, 11.7, 35), 0.0, 4.0)
	plant.place_structure("s_beam", "u500_beam_top_w", Vector3(-4, 11.7, 33), PI / 2.0, 4.0)
	plant.place_structure("s_beam", "u500_beam_top_e", Vector3(0, 11.7, 33), PI / 2.0, 4.0)
	# Flights. A flight ascends toward its local -z and its top edge sits
	# 0.1 m inside the deck edge it lands on.
	plant.place_structure("s_stairs", "u500_stairs_1", Vector3(2.1, 0.0, 29.75), PI / 2.0)
	plant.place_structure("s_stairs", "u500_stairs_2", Vector3(-3.2, 3.025, 32.9), PI)
	plant.place_structure("s_stairs", "u500_stairs_3", Vector3(-0.8, 6.025, 37.1), 0.0)
	# Railings, leaving flight feet and landings open.
	var rails := [
		# L1, z 27..35: flight 1 enters the east edge at z 29..30.5;
		# flight 2's hull takes the west strip from z 30.7 south.
		["u500_r1_n", Vector3(-2, 3.025, 27.05), 0.0, 4.0],
		["u500_r1_e1", Vector3(-0.05, 3.025, 28.0), PI / 2.0, 2.0],
		["u500_r1_e2", Vector3(-0.05, 3.025, 32.75), PI / 2.0, 4.5],
		["u500_r1_s", Vector3(-1.225, 3.025, 34.95), 0.0, 2.45],
		["u500_r1_w", Vector3(-3.95, 3.025, 28.85), PI / 2.0, 3.7],
		# L2, z 35..43: flight 2 lands on the north edge's west strip;
		# flight 3 leaves from bay D's north side up bay C's east strip.
		["u500_r2_n", Vector3(-1.225, 6.025, 35.05), 0.0, 2.45],
		["u500_r2_e", Vector3(-0.05, 6.025, 39.0), PI / 2.0, 8.0],
		["u500_r2_s", Vector3(-2, 6.025, 42.95), 0.0, 4.0],
		["u500_r2_w", Vector3(-3.95, 6.025, 39.0), PI / 2.0, 8.0],
		# L3, z 31..35: flight 3 lands on the south edge's east strip;
		# the catwalk leaves the west edge at z 32.35..33.65.
		["u500_r3_n", Vector3(-2, 9.025, 31.05), 0.0, 4.0],
		["u500_r3_e", Vector3(-0.05, 9.025, 33.0), PI / 2.0, 4.0],
		["u500_r3_s", Vector3(-2.775, 9.025, 34.95), 0.0, 2.45],
		["u500_r3_w1", Vector3(-3.95, 9.025, 31.675), PI / 2.0, 1.35],
		["u500_r3_w2", Vector3(-3.95, 9.025, 34.325), PI / 2.0, 1.35],
		# The catwalk ends above the vessel head, 1.1 m down: rail it.
		["u500_catwalk_end", Vector3(-8.0, 9.025, 33.0), PI / 2.0, 1.3],
	]
	for r: Array in rails:
		plant.place_structure("s_railing", str(r[0]), r[1] as Vector3, float(r[2]), float(r[3]))
	# The catwalk to the vessel head: its deck top is 0.1 m above its
	# base, flush with L3.
	plant.place_structure("s_catwalk", "u500_catwalk", Vector3(-6.0, 8.925, 33.0), 0.0)


static func _bioreactor(root: Node3D) -> void:
	var g := Node3D.new()
	g.position = Vector3(-9.6, 0.0, 33.0)
	root.add_child(g)
	var R := 1.4
	# Skirt with a doorway, anchor bolts, and a base ring.
	_cyl(g, 1.55, 1.3, Vector3(0, 0.65, 0), STEEL)
	_torus(g, 1.6, 0.05, Vector3(0, 0.05, 0), STEEL)
	for i in 12:
		var a := TAU / 12.0 * i
		_box(g, Vector3(0.12, 0.08, 0.12), Vector3(cos(a) * 1.68, 0.04, sin(a) * 1.68), STEEL)
		_cyl(g, 0.025, 0.12, Vector3(cos(a) * 1.68, 0.12, sin(a) * 1.68), STEEL)
	_box(g, Vector3(0.7, 1.0, 0.1), Vector3(0, 0.5, 1.53), EPOXY)  # skirt access door
	_collide_cyl(g, 1.56, 1.3, Vector3(0, 0.65, 0))
	# Dished bottom, shell, top head, jacket, seams.
	_sphere(g, R, Vector3(0, 1.3, 0), STAINLESS, Vector3(1, 0.32, 1))
	_cyl(g, R, 6.0, Vector3(0, 4.3, 0), STAINLESS)
	_sphere(g, R, Vector3(0, 7.3, 0), STAINLESS, Vector3(1, 0.42, 1))
	_cyl(g, R + 0.09, 4.4, Vector3(0, 4.5, 0), STAINLESS_DARK)
	for y: float in [2.3, 6.7]:
		_torus(g, R + 0.09, 0.05, Vector3(0, y, 0), STAINLESS_DARK)
	for y: float in [3.4, 4.5, 5.6]:
		_torus(g, R + 0.1, 0.012, Vector3(0, y, 0), STEEL)
	_torus(g, R + 0.05, 0.06, Vector3(0, 7.3, 0), STAINLESS)  # head flange
	for i in 24:
		var a := TAU / 24.0 * i
		_cyl(g, 0.03, 0.07, Vector3(cos(a) * (R + 0.05), 7.36, sin(a) * (R + 0.05)), STEEL)
	_collide_cyl(g, R + 0.1, 6.6, Vector3(0, 4.6, 0))
	# Insulation cladding bands on the jacket, with strapping.
	for i in 5:
		_torus(g, R + 0.1, 0.018, Vector3(0, 2.6 + i * 0.95, 0), STAINLESS)
	# Manway on the north face with a davit and a bolt circle.
	var mw := Vector3(0, 2.6, -(R + 0.12))
	_cyl(g, 0.42, 0.24, mw, STAINLESS, Vector3(90, 0, 0))
	_cyl(g, 0.48, 0.05, mw + Vector3(0, 0, -0.12), STAINLESS, Vector3(90, 0, 0))
	for i in 16:
		var a := TAU / 16.0 * i
		_cyl(g, 0.02, 0.06, mw + Vector3(cos(a) * 0.44, sin(a) * 0.44, -0.16), STEEL, Vector3(90, 0, 0))
	_box(g, Vector3(0.06, 0.9, 0.06), mw + Vector3(0.62, 0.35, 0.1), STEEL)
	_box(g, Vector3(0.7, 0.05, 0.05), mw + Vector3(0.3, 0.8, 0.1), STEEL)
	# Sight glasses with lamps, north face.
	for y: float in [3.6, 5.6]:
		var sg := Vector3(0.55, y, -(R + 0.08))
		_cyl(g, 0.17, 0.16, sg, STAINLESS, Vector3(90, 0, 0))
		_cyl(g, 0.12, 0.02, sg + Vector3(0, 0, -0.09), GLASS_TINT, Vector3(90, 0, 0))
		_box(g, Vector3(0.14, 0.14, 0.12), sg + Vector3(-0.45, 0, 0.02), STEEL)
		_cyl(g, 0.05, 0.02, sg + Vector3(-0.45, 0, -0.06), LAMP_AMBER, Vector3(90, 0, 0))
	# Probes: pH, DO, temperature, on the east face, with cables to a
	# junction box on the skirt.
	for i in 3:
		var p := Vector3(R + 0.1, 2.7 + i * 0.45, 0.3 - i * 0.3)
		_nozzle(g, p - Vector3(0.1, 0, 0), Vector3.RIGHT, 0.04, 0.22)
		_cyl(g, 0.03, 0.1, p + Vector3(0.27, 0, 0), RUBBER, Vector3(0, 0, 90))
		_pipe(g, p + Vector3(0.32, 0, 0), Vector3(R + 0.55, 1.4, 0.0), 0.012, RUBBER, false)
	_box(g, Vector3(0.3, 0.4, 0.14), Vector3(R + 0.55, 1.2, 0.0), PAINT_GREY)
	_cyl(g, 0.02, 0.02, Vector3(R + 0.55, 1.32, -0.08), LAMP_GREEN, Vector3(90, 0, 0))
	# Sample valve on the west face.
	_nozzle(g, Vector3(-R, 2.9, 0.2), Vector3.LEFT, 0.04, 0.2)
	_box(g, Vector3(0.14, 0.14, 0.12), Vector3(-R - 0.28, 2.9, 0.2), STEEL)
	_handwheel(g, Vector3(-R - 0.28, 3.05, 0.2), 0.09, STEEL, Vector3(90, 0, 0))
	# Bottom outlet under the dish: valve, handwheel, line out through
	# the skirt to a flanged stub.
	_cyl(g, 0.07, 0.4, Vector3(0, 0.75, 0), STAINLESS)
	_box(g, Vector3(0.28, 0.24, 0.24), Vector3(0, 0.55, 0), STEEL)
	_handwheel(g, Vector3(0.24, 0.55, 0), 0.13, STEEL, Vector3(0, 90, 0))
	_pipe(g, Vector3(0, 0.4, 0), Vector3(0, 0.4, 1.9), 0.06)
	_nozzle(g, Vector3(0, 0.4, 1.9), Vector3.BACK, 0.06, 0.3)
	# Head plate: nozzles around, the exhaust with a condenser and a
	# filter, the sparge and feed lines, and the agitator drive.
	for i in 6:
		var a := TAU / 6.0 * i + 0.3
		var p := Vector3(cos(a) * 0.85, 7.72 - 0.06 * absf(sin(a)), sin(a) * 0.85)
		_nozzle(g, p, Vector3.UP, 0.06 if i % 2 == 0 else 0.045, 0.3)
	# Exhaust: a nozzle to a condenser column, then a filter housing,
	# then down the south side to grade.
	var ex := Vector3(0.95, 7.75, 0.55)
	_nozzle(g, ex, Vector3.UP, 0.1, 0.35)
	_cyl(g, 0.22, 1.1, ex + Vector3(0, 0.9, 0), STAINLESS)
	_torus(g, 0.22, 0.03, ex + Vector3(0, 0.36, 0), STAINLESS)
	_torus(g, 0.22, 0.03, ex + Vector3(0, 1.44, 0), STAINLESS)
	# The run heads south off the head, away from the catwalk's end, and
	# drops to grade outside the jacket.
	_pipe(g, ex + Vector3(0, 1.45, 0), ex + Vector3(0, 1.75, 0), 0.06)
	_pipe(g, ex + Vector3(0, 1.75, 0), ex + Vector3(0, 1.75, 0.75), 0.06)
	_cyl(g, 0.17, 0.55, ex + Vector3(0, 1.75, 1.0), STAINLESS, Vector3(90, 0, 0))
	_pipe(g, ex + Vector3(0, 1.75, 1.3), ex + Vector3(0, 1.75, 1.6), 0.06)
	_pipe(g, ex + Vector3(0, 1.75, 1.6), Vector3(ex.x, 1.0, ex.z + 1.6), 0.06)
	_pipe(g, Vector3(ex.x, 1.0, ex.z + 1.6), Vector3(ex.x, 1.0, ex.z + 2.4), 0.06, STAINLESS_DARK, false)
	_nozzle(g, Vector3(ex.x, 1.0, ex.z + 2.4), Vector3.BACK, 0.06, 0.25)
	# Feed and sparge lines climbing the west side.
	_pipe(g, Vector3(-R - 0.15, 1.3, 0.9), Vector3(-R - 0.15, 7.9, 0.9), 0.035)
	_pipe(g, Vector3(-R - 0.15, 7.9, 0.9), Vector3(-0.85, 8.05, 0.55), 0.035)
	_pipe(g, Vector3(-R - 0.35, 1.3, -0.6), Vector3(-R - 0.35, 7.9, -0.6), 0.025)
	_pipe(g, Vector3(-R - 0.35, 7.9, -0.6), Vector3(-0.6, 8.05, -0.75), 0.025)
	# A rotameter on the sparge line at eye level.
	_box(g, Vector3(0.08, 0.5, 0.08), Vector3(-R - 0.35, 1.6, -0.6), STEEL)
	_cyl(g, 0.03, 0.42, Vector3(-R - 0.35, 1.6, -0.6), GLASS_TINT)
	# Agitator: lantern, gearbox, motor, terminal box, conduit.
	_cyl(g, 0.22, 0.35, Vector3(0, 8.0, 0), STAINLESS)
	_box(g, Vector3(0.55, 0.4, 0.55), Vector3(0, 8.4, 0), PAINT_BLUE)
	_cyl(g, 0.34, 0.85, Vector3(0, 9.05, 0), PAINT_BLUE)
	_cyl(g, 0.36, 0.06, Vector3(0, 9.5, 0), STEEL)
	for i in 10:
		_box(g, Vector3(0.72, 0.02, 0.03), Vector3(0, 8.75 + i * 0.07, 0), PAINT_BLUE,
			Vector3(0, 36.0 * i, 0))
	_box(g, Vector3(0.2, 0.16, 0.12), Vector3(0.36, 9.25, 0.2), PAINT_GREY)
	_pipe(g, Vector3(0.36, 9.15, 0.2), Vector3(1.9, 8.2, 0.8), 0.02, PAINT_GREY, false)
	_pipe(g, Vector3(1.9, 8.2, 0.8), Vector3(1.9, 1.1, 0.8), 0.02, PAINT_GREY, false)
	# Nameplate and a shadow of level: three sight ports read nothing,
	# because nothing is simulated here.
	_label(g, "BR-501\n8,000 L STIRRED BIOREACTOR", Vector3(0, 10.4, 0), 44)
	# Jacket water skid to the west: pump, plate exchanger, valves,
	# lines to the jacket nozzles.
	var sk := Node3D.new()
	sk.position = Vector3(-3.6, 0.0, 0.0)
	g.add_child(sk)
	_box(sk, Vector3(2.0, 0.12, 1.2), Vector3(0, 0.06, 0), STEEL)
	_collide_box(sk, Vector3(2.0, 1.2, 1.2), Vector3(0, 0.6, 0))
	_cyl(sk, 0.18, 0.5, Vector3(-0.6, 0.45, 0.3), PAINT_BLUE, Vector3(0, 0, 90))
	_box(sk, Vector3(0.3, 0.3, 0.3), Vector3(-0.15, 0.4, 0.3), STAINLESS_DARK)
	_box(sk, Vector3(0.7, 0.8, 0.45), Vector3(0.5, 0.55, -0.25), STAINLESS)
	for i in 9:
		_box(sk, Vector3(0.02, 0.7, 0.42), Vector3(0.2 + i * 0.075, 0.55, -0.25), STAINLESS_DARK)
	for i in 4:
		_cyl(sk, 0.03, 0.9, Vector3(0.18 + (i % 2) * 0.64, 0.55, -0.02 - (i / 2) * 0.46), STEEL, Vector3(0, 0, 90))
	_pipe(sk, Vector3(-0.15, 0.7, 0.3), Vector3(-0.15, 2.3, 0.3), 0.04)
	_pipe(sk, Vector3(-0.15, 2.3, 0.3), Vector3(2.05, 2.3, 0.3), 0.04)
	_pipe(sk, Vector3(0.5, 1.0, -0.25), Vector3(0.5, 6.8, -0.25), 0.04)
	_pipe(sk, Vector3(0.5, 6.8, -0.25), Vector3(2.05, 6.8, -0.25), 0.04)
	_nozzle(g, Vector3(-R - 0.09, 2.3, 0.3), Vector3.LEFT, 0.045, 0.3)
	_nozzle(g, Vector3(-R - 0.09, 6.8, -0.25), Vector3.LEFT, 0.045, 0.3)
	_handwheel(sk, Vector3(-0.15, 1.6, 0.3), 0.1, STEEL, Vector3(0, 90, 0))
	_handwheel(sk, Vector3(0.5, 1.8, -0.25), 0.1, STEEL, Vector3(0, 90, 0))
	_label(sk, "JACKET SKID", Vector3(0.2, 1.5, 0), 28)


# ---- the autoclave ------------------------------------------------------

static func _autoclave(root: Node3D) -> void:
	# East of the stair tower's first flight, whose foot reaches x 4.3
	# and needs the aisle beyond it clear.
	var g := Node3D.new()
	g.position = Vector3(8.0, 0.0, 30.0)
	root.add_child(g)
	# Cabinet on feet, chamber inside, the door on the north face.
	for i in 4:
		_box(g, Vector3(0.12, 0.12, 0.12), Vector3(-1.0 + 2.0 * (i % 2), 0.06, -1.1 + 2.2 * (i / 2)), STEEL)
	_box(g, Vector3(2.3, 2.0, 2.6), Vector3(0, 1.12, 0), PAINT_WHITE)
	_box(g, Vector3(2.32, 0.12, 2.62), Vector3(0, 2.18, 0), STAINLESS_DARK)
	_box(g, Vector3(2.32, 0.06, 2.62), Vector3(0, 0.15, 0), STAINLESS_DARK)
	_collide_box(g, Vector3(2.3, 2.3, 2.6), Vector3(0, 1.15, 0))
	var face := -1.31
	# Door: dished disc, clamp ring, radial locking bars, hinge, handwheel.
	_cyl(g, 0.86, 0.08, Vector3(-0.2, 1.15, face - 0.04), STAINLESS, Vector3(90, 0, 0))
	_sphere(g, 0.86, Vector3(-0.2, 1.15, face - 0.06), STAINLESS, Vector3(1, 1, 0.12))
	_torus(g, 0.92, 0.05, Vector3(-0.2, 1.15, face), STAINLESS_DARK, Vector3(90, 0, 0))
	for i in 8:
		var a := TAU / 8.0 * i
		_box(g, Vector3(0.05, 0.42, 0.06), Vector3(-0.2 + cos(a) * 0.72, 1.15 + sin(a) * 0.72, face - 0.1),
			STEEL, Vector3(0, 0, rad_to_deg(a) + 90.0))
		_cyl(g, 0.045, 0.04, Vector3(-0.2 + cos(a) * 0.95, 1.15 + sin(a) * 0.95, face - 0.03), STEEL, Vector3(90, 0, 0))
	_handwheel(g, Vector3(-0.2, 1.15, face - 0.18), 0.3, STEEL)
	_box(g, Vector3(0.08, 1.6, 0.14), Vector3(0.78, 1.15, face - 0.07), STEEL)   # hinge post
	_box(g, Vector3(0.25, 0.08, 0.1), Vector3(0.68, 1.85, face - 0.08), STEEL)
	_box(g, Vector3(0.25, 0.08, 0.1), Vector3(0.68, 0.45, face - 0.08), STEEL)
	# Pressure gauge, chart recorder, control panel with screen, keys and lamps.
	_cyl(g, 0.1, 0.05, Vector3(-0.85, 2.0, face - 0.025), STAINLESS_DARK, Vector3(90, 0, 0))
	_cyl(g, 0.08, 0.01, Vector3(-0.85, 2.0, face - 0.055), PAINT_WHITE, Vector3(90, 0, 0))
	_box(g, Vector3(0.012, 0.07, 0.01), Vector3(-0.85, 2.03, face - 0.065), RED, Vector3(0, 0, -30))
	var pnl := Vector3(0.85, 1.45, face - 0.03)
	_box(g, Vector3(0.36, 0.7, 0.06), pnl, PAINT_GREY)
	_box(g, Vector3(0.28, 0.2, 0.01), pnl + Vector3(0, 0.2, -0.035), SCREEN)
	for i in 6:
		_cyl(g, 0.02, 0.02, pnl + Vector3(-0.1 + 0.04 * i, -0.02, -0.04),
			LAMP_GREEN if i < 4 else LAMP_AMBER, Vector3(90, 0, 0))
	for i in 3:
		for j in 3:
			_box(g, Vector3(0.05, 0.03, 0.02), pnl + Vector3(-0.08 + 0.08 * i, -0.15 - 0.05 * j, -0.04), EPOXY)
	_cyl(g, 0.11, 0.03, pnl + Vector3(0, -0.5, -0.01), STAINLESS_DARK, Vector3(90, 0, 0))  # chart recorder
	_cyl(g, 0.09, 0.005, pnl + Vector3(0, -0.5, -0.03), PAINT_WHITE, Vector3(90, 0, 0))
	_label(g, "AC-502  STEAM STERILIZER", Vector3(0, 2.55, face), 30)
	_label(g, "HOT SURFACE", Vector3(-0.2, 0.32, face - 0.02), 22)
	# Steam and condensate at the back: generator, safety valve with
	# a lever, trap, drain, three lines to grade.
	_box(g, Vector3(0.9, 0.9, 0.5), Vector3(0.5, 0.6, 1.55), STAINLESS_DARK)
	_cyl(g, 0.06, 0.16, Vector3(0.5, 1.15, 1.55), BRASS)
	_box(g, Vector3(0.2, 0.02, 0.03), Vector3(0.58, 1.24, 1.55), STEEL)
	for i in 3:
		var x := -0.6 + 0.25 * i
		_pipe(g, Vector3(x, 1.9, 1.32), Vector3(x, 1.9, 1.8), 0.03)
		_pipe(g, Vector3(x, 1.9, 1.8), Vector3(x, 0.2, 1.8), 0.03)
		_pipe(g, Vector3(x, 0.2, 1.8), Vector3(x, 0.2, 2.3), 0.03, STAINLESS_DARK, false)
	_cyl(g, 0.07, 0.2, Vector3(-0.35, 0.6, 1.8), STAINLESS_DARK)  # trap
	_handwheel(g, Vector3(-0.6, 1.2, 1.9), 0.06, STEEL, Vector3(0, 90, 0))
	# Loading trolley in front, with a basket of bottles.
	var tr := Node3D.new()
	tr.position = Vector3(-0.2, 0.0, -2.6)
	g.add_child(tr)
	_box(tr, Vector3(1.0, 0.04, 1.4), Vector3(0, 1.0, 0), STAINLESS_DARK)
	for i in 4:
		var p := Vector3(-0.45 + 0.9 * (i % 2), 0.55, -0.6 + 1.2 * (i / 2))
		_box(tr, Vector3(0.04, 0.9, 0.04), p, STAINLESS_DARK)
		_cyl(tr, 0.07, 0.04, Vector3(p.x, 0.07, p.z), RUBBER, Vector3(0, 0, 90))
	_collide_box(tr, Vector3(1.0, 1.1, 1.4), Vector3(0, 0.55, 0))
	for i in 6:
		_box(tr, Vector3(0.9, 0.3, 0.01), Vector3(0, 1.2, -0.62 + i * 0.25), STAINLESS_DARK)
	for i in 8:
		var p := Vector3(-0.3 + 0.2 * (i % 4), 1.12, -0.25 + 0.5 * (i / 4))
		_cyl(tr, 0.05, 0.2, p, GLASS)
		_cyl(tr, 0.052, 0.03, p + Vector3(0, 0.115, 0), PAINT_BLUE)
		_cyl(tr, 0.045, 0.12, p - Vector3(0, 0.02, 0), _liquid(Color(0.6, 0.75, 0.9)))


# ---- the isolator -------------------------------------------------------

static func _isolator(root: Node3D) -> void:
	var g := Node3D.new()
	g.position = Vector3(12.6, 0.0, 30.0)
	root.add_child(g)
	# Frame, lower shelf with supplies, chamber, glass front and ends.
	for i in 4:
		_box(g, Vector3(0.06, 0.9, 0.06), Vector3(-1.75 + 3.5 * (i % 2), 0.45, -0.5 + 1.0 * (i / 2)), STEEL)
	_box(g, Vector3(3.6, 0.04, 1.0), Vector3(0, 0.3, 0), STEEL)
	for i in 3:
		_box(g, Vector3(0.5, 0.35, 0.4), Vector3(-1.2 + i * 1.0, 0.5, 0.15), PAINT_GREY)
	# Chamber: stainless floor, ceiling, back and ends; the whole front
	# is one glass panel so the work inside reads from the aisle.
	_box(g, Vector3(3.6, 0.06, 1.1), Vector3(0, 0.90, 0.02), STAINLESS)
	_box(g, Vector3(3.6, 0.06, 1.1), Vector3(0, 2.00, 0.02), STAINLESS)
	_box(g, Vector3(3.6, 1.16, 0.06), Vector3(0, 1.45, 0.54), STAINLESS)
	for x: float in [-1.77, 1.77]:
		_box(g, Vector3(0.06, 1.16, 1.1), Vector3(x, 1.45, 0.02), STAINLESS)
	_box(g, Vector3(3.6, 0.05, 0.05), Vector3(0, 0.955, -0.51), STAINLESS_DARK)   # sill
	_box(g, Vector3(3.6, 0.05, 0.05), Vector3(0, 1.945, -0.51), STAINLESS_DARK)   # head rail
	_box(g, Vector3(3.5, 1.0, 0.02), Vector3(0, 1.45, -0.53), GLASS)
	_collide_box(g, Vector3(3.6, 2.6, 1.1), Vector3(0, 1.3, 0))
	# Interior: light strip, work tray with vials, filling head, a
	# balance, a bin. Visible through the glass.
	_box(g, Vector3(3.2, 0.03, 0.2), Vector3(0, 1.94, 0.0), LIGHT)
	_box(g, Vector3(3.3, 0.02, 0.9), Vector3(0, 0.92, 0.0), STAINLESS_DARK)
	_box(g, Vector3(0.9, 0.02, 0.5), Vector3(-0.4, 0.94, 0.05), STAINLESS_DARK)
	for i in 6:
		for j in 4:
			var p := Vector3(-0.78 + i * 0.15, 0.98, -0.15 + j * 0.13)
			_cyl(g, 0.02, 0.06, p, GLASS)
			_cyl(g, 0.02, 0.012, p + Vector3(0, 0.035, 0), PAINT_GREY if (i + j) % 3 else RUBBER)
			if (i + j) % 2 == 0:
				_cyl(g, 0.017, 0.035, p - Vector3(0, 0.008, 0), _liquid(Color(0.85, 0.85, 0.95)))
	_box(g, Vector3(0.12, 0.35, 0.12), Vector3(0.45, 1.25, 0.15), STAINLESS_DARK)
	_box(g, Vector3(0.35, 0.05, 0.05), Vector3(0.3, 1.4, 0.15), STAINLESS_DARK)
	_cyl(g, 0.006, 0.18, Vector3(0.15, 1.28, 0.15), STAINLESS)
	_box(g, Vector3(0.28, 0.06, 0.3), Vector3(1.1, 0.97, 0.05), PAINT_GREY)
	_cyl(g, 0.07, 0.006, Vector3(1.1, 1.005, 0.05), STAINLESS)
	_box(g, Vector3(0.2, 0.25, 0.02), Vector3(1.1, 1.13, -0.12), GLASS)
	_box(g, Vector3(0.2, 0.3, 0.2), Vector3(-1.5, 1.08, 0.25), RED)
	# Four glove ports: rings on the front, sleeves and hands inside.
	for i in 4:
		var x := -1.25 + i * 0.83
		_torus(g, 0.16, 0.035, Vector3(x, 1.38, -0.55), RUBBER, Vector3(90, 0, 0))
		_torus(g, 0.19, 0.015, Vector3(x, 1.38, -0.54), STAINLESS_DARK, Vector3(90, 0, 0))
		var sleeve := _cyl(g, 0.09, 0.55, Vector3(x, 1.28, -0.25), RUBBER, Vector3(-70, 0, 0), 0.06)
		sleeve.rotation_degrees = Vector3(-70, 0, 0)
		_sphere(g, 0.075, Vector3(x, 1.12, -0.02), RUBBER, Vector3(1.2, 0.6, 1.0))
	# Rapid transfer port on the west end with a docked beta container,
	# pass-through hatch on the east end.
	_cyl(g, 0.24, 0.06, Vector3(-1.83, 1.45, 0.0), STAINLESS_DARK, Vector3(0, 0, 90))
	_torus(g, 0.25, 0.02, Vector3(-1.83, 1.45, 0.0), STEEL, Vector3(0, 0, 90))
	_box(g, Vector3(0.04, 0.3, 0.05), Vector3(-1.88, 1.45, 0.0), STEEL)
	_cyl(g, 0.2, 0.34, Vector3(-2.06, 1.45, 0.0), PAINT_WHITE, Vector3(0, 0, 90))
	_box(g, Vector3(0.06, 0.58, 0.5), Vector3(1.83, 1.45, 0.02), STAINLESS_DARK)
	_box(g, Vector3(0.01, 0.5, 0.42), Vector3(1.87, 1.45, 0.02), GLASS)
	_box(g, Vector3(0.03, 0.12, 0.03), Vector3(1.88, 1.45, 0.3), STEEL)
	# HEPA housing on top with a grille and fan cowls, exhaust duct.
	_box(g, Vector3(3.2, 0.36, 0.85), Vector3(0, 2.2, 0.0), PAINT_WHITE)
	for i in 14:
		_box(g, Vector3(0.015, 0.36, 0.7), Vector3(-1.45 + i * 0.22, 2.2, 0.0), PAINT_GREY)
	for x: float in [-0.9, 0.9]:
		_cyl(g, 0.22, 0.14, Vector3(x, 2.45, 0.0), PAINT_GREY)
		_torus(g, 0.16, 0.02, Vector3(x, 2.53, 0.0), STEEL)
	_pipe(g, Vector3(0.9, 2.5, 0.0), Vector3(0.9, 3.4, 0.0), 0.1, PAINT_GREY)
	_pipe(g, Vector3(0.9, 3.4, 0.0), Vector3(0.9, 3.4, 1.4), 0.1, PAINT_GREY, false)
	# Magnehelic gauge, status lamp, control panel, foot pedal, sign.
	_cyl(g, 0.09, 0.05, Vector3(-1.5, 2.05, -0.57), STAINLESS_DARK, Vector3(90, 0, 0))
	_cyl(g, 0.075, 0.01, Vector3(-1.5, 2.05, -0.59), PAINT_WHITE, Vector3(90, 0, 0))
	_box(g, Vector3(0.008, 0.06, 0.008), Vector3(-1.5, 2.07, -0.6), RED, Vector3(0, 0, 40))
	_cyl(g, 0.03, 0.02, Vector3(-1.2, 2.05, -0.57), LAMP_GREEN, Vector3(90, 0, 0))
	_box(g, Vector3(0.4, 0.3, 0.05), Vector3(1.3, 0.62, -0.5), PAINT_GREY)
	_box(g, Vector3(0.3, 0.16, 0.01), Vector3(1.3, 0.66, -0.53), SCREEN)
	_box(g, Vector3(0.25, 0.04, 0.15), Vector3(0.4, 0.02, -0.8), STEEL)
	_label(g, "ISO-503  ASEPTIC FILLING ISOLATOR", Vector3(0, 3.7, 0), 30)


# ---- the QC lab ---------------------------------------------------------

static func _lab(plant: Plant, root: Node3D) -> void:
	# The room: south wall, east wall with a window, an open west and
	# north side so the gallery reads as a cutaway.
	plant.place_structure("s_wall", "u500_lab_wall_s1", Vector3(18.4, 0.0, 35.0), 0.0)
	plant.place_structure("s_wall", "u500_lab_wall_s2", Vector3(22.4, 0.0, 35.0), 0.0)
	plant.place_structure("s_window", "u500_lab_window_e", Vector3(24.4, 0.0, 29.0), PI / 2.0)
	plant.place_structure("s_wall", "u500_lab_wall_e", Vector3(24.4, 0.0, 33.0), PI / 2.0)
	var g := Node3D.new()
	g.position = Vector3(20.4, 0.0, 31.0)
	root.add_child(g)
	# Floor: a slab with grout lines, a coved skirting along the walls.
	_box(g, Vector3(8.0, 0.06, 8.0), Vector3(0, 0.03, 0), _mat(Color(0.86, 0.86, 0.82), 0.0, 0.3))
	for i in 15:
		_box(g, Vector3(8.0, 0.004, 0.012), Vector3(0, 0.063, -3.75 + i * 0.5), PAINT_GREY)
		_box(g, Vector3(0.012, 0.004, 8.0), Vector3(-3.75 + i * 0.5, 0.063, 0), PAINT_GREY)
	_box(g, Vector3(8.0, 0.12, 0.04), Vector3(0, 0.12, 3.96), PAINT_GREY)
	_box(g, Vector3(0.04, 0.12, 8.0), Vector3(3.96, 0.12, 0), PAINT_GREY)
	# Two island benches and a wall bench.
	_bench(g, Vector3(-1.9, 0, -1.2), Vector2(2.4, 0.9))
	_bench(g, Vector3(1.6, 0, -1.2), Vector2(2.4, 0.9))
	_bench(g, Vector3(-0.3, 0, 3.55), Vector2(6.6, 0.7))
	# Wall shelves with bottles and boxes, a whiteboard, a light bar.
	for y: float in [1.55, 1.95]:
		_box(g, Vector3(3.2, 0.03, 0.28), Vector3(-1.6, y, 3.8), PAINT_WHITE)
		for i in 9:
			var p := Vector3(-3.05 + i * 0.36, y + 0.09, 3.8)
			var col: Color = [Color(0.55, 0.30, 0.15), Color(0.85, 0.85, 0.8), Color(0.2, 0.4, 0.7),
				Color(0.9, 0.9, 0.5)][(i + int(y * 10)) % 4]
			_cyl(g, 0.045, 0.16, p, _mat(col, 0.0, 0.4))
			_cyl(g, 0.047, 0.03, p + Vector3(0, 0.095, 0), RUBBER if i % 2 else PAINT_WHITE)
			_box(g, Vector3(0.06, 0.05, 0.001), p + Vector3(0, -0.01, -0.047), PAINT_WHITE)
	for i in 3:
		_box(g, Vector3(0.4, 0.25, 0.25), Vector3(1.0 + i * 0.45, 1.68, 3.8), _mat(Color(0.8, 0.7, 0.5), 0.0, 0.8))
	_box(g, Vector3(1.8, 1.1, 0.03), Vector3(1.6, 1.75, 3.9), PAINT_WHITE)
	_box(g, Vector3(1.84, 1.14, 0.02), Vector3(1.6, 1.75, 3.915), STEEL)
	for i in 5:
		_box(g, Vector3(0.5 + 0.15 * (i % 3), 0.02, 0.005), Vector3(1.1 + 0.2 * (i % 2), 2.1 - i * 0.14, 3.88),
			[PAINT_BLUE, RED, EPOXY][i % 3])
	_box(g, Vector3(0.2, 0.02, 0.005), Vector3(0.9, 1.35, 3.88), EPOXY)
	_box(g, Vector3(2.6, 0.06, 0.12), Vector3(-1.4, 2.85, 3.85), PAINT_WHITE)
	_box(g, Vector3(2.5, 0.02, 0.08), Vector3(-1.4, 2.815, 3.85), LIGHT)
	# Fume hood in the south-east corner, sash half open, services.
	var fh := Node3D.new()
	fh.position = Vector3(3.15, 0.0, 3.5)
	g.add_child(fh)
	_box(fh, Vector3(1.5, 0.9, 0.85), Vector3(0, 0.45, 0), PAINT_GREY)
	_box(fh, Vector3(1.5, 1.6, 0.85), Vector3(0, 1.7, 0.0), PAINT_WHITE)
	_box(fh, Vector3(1.3, 1.3, 0.7), Vector3(0, 1.6, 0.05), _mat(Color(0.93, 0.94, 0.95), 0.0, 0.4))
	_box(fh, Vector3(1.3, 0.02, 0.6), Vector3(0, 2.2, 0.05), LIGHT)
	_box(fh, Vector3(1.32, 0.6, 0.02), Vector3(0, 1.85, -0.42), GLASS)
	_box(fh, Vector3(1.32, 0.03, 0.04), Vector3(0, 1.56, -0.43), STAINLESS_DARK)
	_box(fh, Vector3(0.4, 0.5, 0.8), Vector3(0, 2.75, 0.0), PAINT_GREY)
	_pipe(fh, Vector3(0, 3.0, 0.0), Vector3(0, 3.6, 0.0), 0.12, PAINT_GREY, false)
	for i in 3:
		_cyl(fh, 0.02, 0.1, Vector3(-0.5 + i * 0.12, 1.05, -0.35), [YELLOW, PAINT_BLUE, STEEL][i])
		_box(fh, Vector3(0.05, 0.02, 0.05), Vector3(-0.5 + i * 0.12, 1.11, -0.35), [YELLOW, PAINT_BLUE, STEEL][i])
	_cyl(fh, 0.05, 0.15, Vector3(0.3, 0.98, 0.1), _mat(Color(0.5, 0.25, 0.1), 0.0, 0.4))
	_cyl(fh, 0.04, 0.18, Vector3(0.0, 0.99, 0.15), GLASS)
	_cyl(fh, 0.035, 0.1, Vector3(0.0, 0.95, 0.15), _liquid(Color(0.95, 0.75, 0.2)))
	_collide_box(fh, Vector3(1.5, 2.5, 0.85), Vector3(0, 1.25, 0))
	_label(fh, "FUME HOOD", Vector3(0, 2.55, -0.44), 22)
	# Incubator in the south-west corner, with a glass door and a glow.
	var inc := Node3D.new()
	inc.position = Vector3(-3.4, 0.0, 3.4)
	g.add_child(inc)
	_box(inc, Vector3(0.75, 1.9, 0.75), Vector3(0, 0.95, 0), PAINT_WHITE)
	_box(inc, Vector3(0.55, 1.2, 0.02), Vector3(0, 1.1, -0.38), GLASS_TINT)
	_box(inc, Vector3(0.5, 1.1, 0.02), Vector3(0, 1.1, -0.36), ViewUtil.glow(Color(0.95, 0.6, 0.3), 0.5))
	for i in 4:
		_box(inc, Vector3(0.5, 0.01, 0.5), Vector3(0, 0.65 + i * 0.3, 0), STAINLESS_DARK)
		for j in 3:
			_cyl(inc, 0.045, 0.012, Vector3(-0.15 + j * 0.15, 0.665 + i * 0.3, -0.05), GLASS)
	_box(inc, Vector3(0.03, 0.4, 0.03), Vector3(0.32, 1.1, -0.4), STEEL)
	_box(inc, Vector3(0.4, 0.15, 0.01), Vector3(0, 1.82, -0.38), SCREEN)
	_collide_box(inc, Vector3(0.75, 1.9, 0.75), Vector3(0, 0.95, 0))
	_label(inc, "INCUBATOR 37 C", Vector3(0, 2.1, 0), 22)
	# Benchtop equipment on the islands.
	_microscope(g, Vector3(-2.6, 0.9, -1.2))
	_microscope(g, Vector3(2.3, 0.9, -1.4))
	_beaker_row(g, Vector3(-1.4, 0.9, -1.45))
	_flasks(g, Vector3(1.0, 0.9, -1.0))
	_balance(g, Vector3(-3.0, 0.9, 3.5))
	_centrifuge(g, Vector3(-2.1, 0.9, 3.5))
	_hotplate(g, Vector3(-1.2, 0.9, 3.5))
	_pipettes(g, Vector3(-0.4, 0.9, 3.6))
	_tube_rack(g, Vector3(0.3, 0.9, 3.5))
	_laptop(g, Vector3(1.4, 0.9, 3.45))
	_petri_stack(g, Vector3(2.0, 0.9, 3.6))
	_notebook(g, Vector3(2.5, 0.9, 3.5))
	# A sink at the wall bench's west end, with a tap and a wash bottle.
	_box(g, Vector3(0.45, 0.16, 0.4), Vector3(-3.35, 0.83, 3.5), STAINLESS_DARK)
	_box(g, Vector3(0.38, 0.14, 0.33), Vector3(-3.35, 0.845, 3.5), _mat(Color(0.2, 0.2, 0.22), 0.6, 0.4))
	_pipe(g, Vector3(-3.35, 0.9, 3.75), Vector3(-3.35, 1.2, 3.75), 0.012, STAINLESS, true)
	_pipe(g, Vector3(-3.35, 1.2, 3.75), Vector3(-3.35, 1.2, 3.55), 0.012, STAINLESS, false)
	_cyl(g, 0.04, 0.16, Vector3(-3.05, 0.98, 3.6), _mat(Color(0.9, 0.9, 0.9, 0.7), 0.0, 0.4))
	_cyl(g, 0.006, 0.12, Vector3(-3.08, 1.1, 3.55), PAINT_WHITE, Vector3(30, 0, 30))
	# Two stools, an eyewash station, a fire extinguisher, a bin.
	for p: Vector3 in [Vector3(-1.9, 0, -0.2), Vector3(1.6, 0, -2.2)]:
		_cyl(g, 0.2, 0.05, p + Vector3(0, 0.62, 0), EPOXY)
		_cyl(g, 0.025, 0.55, p + Vector3(0, 0.32, 0), STEEL)
		_torus(g, 0.22, 0.02, p + Vector3(0, 0.05, 0), STEEL)
		_collide_cyl(g, 0.22, 0.65, p + Vector3(0, 0.33, 0))
	_box(g, Vector3(0.05, 1.2, 0.05), Vector3(3.8, 0.6, -2.5), STEEL)
	_box(g, Vector3(0.3, 0.12, 0.2), Vector3(3.7, 1.2, -2.5), LAMP_GREEN)
	for x: float in [3.63, 3.77]:
		_cyl(g, 0.04, 0.03, Vector3(x, 1.28, -2.5), PAINT_WHITE, Vector3.ZERO, 0.02)
	_cyl(g, 0.075, 0.5, Vector3(3.75, 0.25, 2.5), RED)
	_cyl(g, 0.03, 0.08, Vector3(3.75, 0.54, 2.5), EPOXY)
	_box(g, Vector3(0.05, 0.02, 0.1), Vector3(3.75, 0.6, 2.45), EPOXY)
	_cyl(g, 0.16, 0.45, Vector3(0.3, 0.225, -2.6), PAINT_GREY, Vector3.ZERO, 0.19)
	_label(g, "LAB-504  QC LABORATORY", Vector3(0, 3.3, 3.8), 34)


static func _bench(g: Node3D, at: Vector3, size: Vector2) -> void:
	var body := Node3D.new()
	body.position = at
	g.add_child(body)
	_box(body, Vector3(size.x - 0.1, 0.78, size.y - 0.15), Vector3(0, 0.45, 0), PAINT_WHITE)
	_box(body, Vector3(size.x - 0.1, 0.1, size.y - 0.3), Vector3(0, 0.05, 0), EPOXY)  # kick plate
	_box(body, Vector3(size.x, 0.05, size.y), Vector3(0, 0.875, 0), EPOXY)  # epoxy top
	var drawers := int(size.x / 0.6)
	for i in drawers:
		var x := -size.x / 2.0 + 0.3 + i * (size.x - 0.1) / drawers
		for j in 3:
			_box(body, Vector3(0.5, 0.2, 0.01), Vector3(x, 0.72 - j * 0.23, -(size.y - 0.15) / 2.0 - 0.005), PAINT_GREY)
			_box(body, Vector3(0.14, 0.015, 0.02), Vector3(x, 0.78 - j * 0.23, -(size.y - 0.15) / 2.0 - 0.02), STEEL)
	_collide_box(body, Vector3(size.x, 0.9, size.y), Vector3(0, 0.45, 0))


static func _microscope(g: Node3D, at: Vector3) -> void:
	var m := Node3D.new()
	m.position = at
	g.add_child(m)
	_box(m, Vector3(0.2, 0.03, 0.28), Vector3(0, 0.015, 0), EPOXY)
	_box(m, Vector3(0.06, 0.3, 0.06), Vector3(0, 0.18, 0.1), EPOXY)
	_box(m, Vector3(0.06, 0.06, 0.22), Vector3(0, 0.34, 0.0), EPOXY)
	_box(m, Vector3(0.16, 0.012, 0.14), Vector3(0, 0.15, -0.04), PAINT_GREY)  # stage
	_box(m, Vector3(0.12, 0.004, 0.04), Vector3(0, 0.158, -0.04), GLASS)         # slide
	_cyl(m, 0.02, 0.01, Vector3(0, 0.12, -0.04), LIGHT)                          # illuminator
	_cyl(m, 0.05, 0.02, Vector3(0, 0.29, -0.04), EPOXY)                          # turret
	for i in 4:
		var a := TAU / 4.0 * i
		_cyl(m, 0.012, 0.06, Vector3(cos(a) * 0.03, 0.25, -0.04 + sin(a) * 0.03), STAINLESS_DARK, Vector3(15 * cos(a), 0, 15 * sin(a)))
	var eye := _cyl(m, 0.016, 0.14, Vector3(0.03, 0.42, -0.1), EPOXY, Vector3(35, 0, 0))
	eye.rotation_degrees = Vector3(35, 0, 0)
	var eye2 := _cyl(m, 0.016, 0.14, Vector3(-0.03, 0.42, -0.1), EPOXY, Vector3(35, 0, 0))
	eye2.rotation_degrees = Vector3(35, 0, 0)
	_cyl(m, 0.02, 0.015, Vector3(0.03, 0.485, -0.145), RUBBER, Vector3(35, 0, 0))
	_cyl(m, 0.02, 0.015, Vector3(-0.03, 0.485, -0.145), RUBBER, Vector3(35, 0, 0))
	for side: float in [-1.0, 1.0]:
		_cyl(m, 0.025, 0.02, Vector3(side * 0.045, 0.2, 0.1), EPOXY, Vector3(0, 0, 90))   # focus knobs
		_cyl(m, 0.015, 0.03, Vector3(side * 0.06, 0.2, 0.1), STEEL, Vector3(0, 0, 90))


static func _beaker_row(g: Node3D, at: Vector3) -> void:
	var sizes := [[0.05, 0.11], [0.07, 0.15], [0.045, 0.09], [0.06, 0.13], [0.08, 0.17]]
	var fills := [0.6, 0.35, 0.8, 0.5, 0.25]
	var colors := [Color(0.3, 0.6, 0.9), Color(0.9, 0.75, 0.2), Color(0.5, 0.85, 0.5),
		Color(0.85, 0.35, 0.3), Color(0.7, 0.5, 0.9)]
	for i in sizes.size():
		var r: float = sizes[i][0]
		var h: float = sizes[i][1]
		var p := at + Vector3(i * 0.2, 0, 0)
		_cyl(g, r, h, p + Vector3(0, h / 2.0, 0), GLASS)
		_cyl(g, r * 1.03, 0.006, p + Vector3(0, h, 0), GLASS)
		_cyl(g, r * 0.94, h * float(fills[i]), p + Vector3(0, h * float(fills[i]) / 2.0 + 0.004, 0),
			_liquid(colors[i]))
		# Graduations.
		for j in 4:
			_box(g, Vector3(0.02, 0.002, 0.001), p + Vector3(0, h * 0.2 * (j + 1), -r), PAINT_WHITE)


static func _flasks(g: Node3D, at: Vector3) -> void:
	# Two Erlenmeyers, one on a magnetic stirrer with a stir bar.
	_box(g, Vector3(0.22, 0.06, 0.22), at + Vector3(0, 0.03, 0), PAINT_GREY)
	_cyl(g, 0.02, 0.02, at + Vector3(0.08, 0.06, 0.08), EPOXY)
	for i in 2:
		var p := at + Vector3(i * 0.32, 0.06 if i == 0 else 0.0, 0)
		_cyl(g, 0.085, 0.17, p + Vector3(0, 0.085, 0), GLASS, Vector3.ZERO, 0.025)
		_cyl(g, 0.025, 0.06, p + Vector3(0, 0.2, 0), GLASS)
		_cyl(g, 0.08, 0.075, p + Vector3(0, 0.04, 0), _liquid(Color(0.4, 0.75, 0.85) if i == 0 else Color(0.9, 0.5, 0.2)), Vector3.ZERO, 0.05)
		if i == 0:
			_box(g, Vector3(0.04, 0.006, 0.006), p + Vector3(0, 0.006, 0), PAINT_WHITE, Vector3(0, 30, 0))
		else:
			_cyl(g, 0.026, 0.02, p + Vector3(0, 0.235, 0), RUBBER)  # stopper


static func _balance(g: Node3D, at: Vector3) -> void:
	_box(g, Vector3(0.24, 0.07, 0.3), at + Vector3(0, 0.035, 0), PAINT_GREY)
	_cyl(g, 0.06, 0.006, at + Vector3(0, 0.075, -0.02), STAINLESS)
	_box(g, Vector3(0.2, 0.22, 0.2), at + Vector3(0, 0.19, -0.02), GLASS)
	_box(g, Vector3(0.1, 0.03, 0.01), at + Vector3(0, 0.03, -0.155), SCREEN)


static func _centrifuge(g: Node3D, at: Vector3) -> void:
	_box(g, Vector3(0.38, 0.24, 0.38), at + Vector3(0, 0.12, 0), PAINT_WHITE)
	_cyl(g, 0.16, 0.03, at + Vector3(0, 0.255, 0.02), PAINT_GREY)
	_box(g, Vector3(0.06, 0.02, 0.03), at + Vector3(0, 0.25, -0.17), STEEL)
	_box(g, Vector3(0.12, 0.04, 0.01), at + Vector3(0.1, 0.16, -0.195), SCREEN)
	_cyl(g, 0.015, 0.01, at + Vector3(-0.1, 0.16, -0.195), LAMP_GREEN, Vector3(90, 0, 0))


static func _hotplate(g: Node3D, at: Vector3) -> void:
	_box(g, Vector3(0.22, 0.06, 0.24), at + Vector3(0, 0.03, 0), PAINT_WHITE)
	_box(g, Vector3(0.18, 0.01, 0.18), at + Vector3(0, 0.065, 0.02), EPOXY)
	for i in 2:
		_cyl(g, 0.02, 0.02, at + Vector3(-0.05 + i * 0.1, 0.07, -0.09), EPOXY)
	_cyl(g, 0.055, 0.12, at + Vector3(0, 0.13, 0.02), GLASS)
	_cyl(g, 0.05, 0.07, at + Vector3(0, 0.107, 0.02), _liquid(Color(0.95, 0.6, 0.6)))


static func _pipettes(g: Node3D, at: Vector3) -> void:
	_cyl(g, 0.05, 0.02, at + Vector3(0, 0.01, 0), PAINT_GREY)
	_cyl(g, 0.012, 0.36, at + Vector3(0, 0.18, 0), STEEL)
	_cyl(g, 0.06, 0.012, at + Vector3(0, 0.32, 0), PAINT_GREY)
	var caps := [PAINT_BLUE, YELLOW, RED, LAMP_GREEN]
	for i in 4:
		var a := TAU / 4.0 * i
		var p := at + Vector3(cos(a) * 0.055, 0.2, sin(a) * 0.055)
		_cyl(g, 0.012, 0.2, p, PAINT_WHITE, Vector3.ZERO, 0.006)
		_cyl(g, 0.014, 0.04, p + Vector3(0, 0.12, 0), caps[i])
		_cyl(g, 0.004, 0.06, p - Vector3(0, 0.13, 0), GLASS)


static func _tube_rack(g: Node3D, at: Vector3) -> void:
	_box(g, Vector3(0.3, 0.05, 0.08), at + Vector3(0, 0.025, 0), PAINT_BLUE)
	_box(g, Vector3(0.3, 0.02, 0.08), at + Vector3(0, 0.1, 0), PAINT_BLUE)
	for i in 6:
		var p := at + Vector3(-0.12 + i * 0.048, 0.08, 0)
		_cyl(g, 0.011, 0.11, p, GLASS)
		if i % 2 == 0:
			_cyl(g, 0.009, 0.05, p - Vector3(0, 0.02, 0), _liquid([Color(0.9, 0.2, 0.2), Color(0.3, 0.3, 0.9), Color(0.9, 0.9, 0.3)][i / 2]))
		else:
			_cyl(g, 0.012, 0.015, p + Vector3(0, 0.06, 0), RUBBER)


static func _laptop(g: Node3D, at: Vector3) -> void:
	_box(g, Vector3(0.34, 0.015, 0.24), at + Vector3(0, 0.008, 0), STAINLESS_DARK)
	_box(g, Vector3(0.28, 0.002, 0.11), at + Vector3(0, 0.017, 0.02), EPOXY)
	var lid := _box(g, Vector3(0.34, 0.22, 0.012), at + Vector3(0, 0.115, -0.15), STAINLESS_DARK, Vector3(-15, 0, 0))
	lid.rotation_degrees = Vector3(-15, 0, 0)
	var scr := _box(g, Vector3(0.3, 0.18, 0.002), at + Vector3(0, 0.115, -0.142), SCREEN, Vector3(-15, 0, 0))
	scr.rotation_degrees = Vector3(-15, 0, 0)


static func _petri_stack(g: Node3D, at: Vector3) -> void:
	for i in 4:
		_cyl(g, 0.045, 0.012, at + Vector3(0, 0.006 + i * 0.014, 0), GLASS)
		_cyl(g, 0.04, 0.004, at + Vector3(0, 0.005 + i * 0.014, 0), _liquid(Color(0.85, 0.6, 0.45)))


static func _notebook(g: Node3D, at: Vector3) -> void:
	_box(g, Vector3(0.22, 0.02, 0.3), at + Vector3(0, 0.01, 0), _mat(Color(0.95, 0.95, 0.9), 0.0, 0.8), Vector3(0, 12, 0))
	for i in 8:
		_box(g, Vector3(0.14, 0.001, 0.004), at + Vector3(-0.02, 0.021, -0.1 + i * 0.025), PAINT_GREY, Vector3(0, 12, 0))
	_cyl(g, 0.005, 0.14, at + Vector3(0.14, 0.01, 0.02), PAINT_BLUE, Vector3(0, 0, 90))
