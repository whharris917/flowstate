class_name StructureFactory
## Placeable structural and architectural elements. They exist to
## carry pipe, conduit, trays, and people — the support rule
## (SupportCheck) counts them, and their own placement has bearing
## rules so structure itself can't float.

const CATALOG: Array[Dictionary] = [
	{"type": "s_column", "label": "Steel column 6 m"},
	{"type": "s_beam", "label": "Beam — stretch to fit"},
	{"type": "s_wall", "label": "Wall panel 4 m"},
	{"type": "s_deck", "label": "Deck / ceiling 4 m"},
	{"type": "s_door", "label": "Doorway + slider"},
	{"type": "s_window", "label": "Window wall 4 m"},
	{"type": "s_stairs", "label": "Stairs 3 m rise"},
	{"type": "s_catwalk", "label": "Catwalk 4 m"},
	{"type": "s_railing", "label": "Railing — stretch"},
]

const CATALOG_ROUTING: Array[Dictionary] = [
	{"type": "run_pipe", "label": "Pipe run"},
	{"type": "run_conduit", "label": "Conduit run"},
	{"type": "run_tray", "label": "Cable tray"},
	{"type": "s_sign", "label": "Sign — E edits"},
	{"type": "s_slab", "label": "Floor slab 4 m (tile)"},
]

# Standalone routed infrastructure — laid before any equipment exists,
# no kernel wire behind it. Colliders live on layer 1: a tray or rack
# pipe is real support the support rule can count.
const RUNS := {
	"run_pipe": {"radius": 0.07, "style": "pipe", "color": Color(0.65, 0.67, 0.70)},
	"run_conduit": {"radius": 0.025, "style": "pipe", "color": Color(0.72, 0.72, 0.75)},
	"run_tray": {"radius": 0.20, "style": "tray", "color": Color(0.55, 0.57, 0.60)},
	# A multicore cable: many circuits in one sheath, from a junction
	# box to a cabinet. Placed by Plant.connect_multicore, not by hand.
	"run_cable": {"radius": 0.04, "style": "pipe", "color": Color(0.14, 0.14, 0.16)},
}

# Two-click stretch tools: start point, end point, exact length.
const STRETCH := {
	"s_beam": {"min": 1.0, "max": 8.0, "size_y": 0.35, "size_z": 0.3},
	"s_railing": {"min": 0.5, "max": 12.0, "size_y": 1.1, "size_z": 0.1},
}

const SIZES := {
	"s_column": Vector3(0.35, 6.0, 0.35),
	"s_beam": Vector3(6.0, 0.35, 0.3),
	"s_wall": Vector3(4.0, 3.2, 0.18),
	"s_deck": Vector3(4.0, 0.15, 4.0),
	"s_door": Vector3(1.6, 2.4, 0.24),
	"s_window": Vector3(4.0, 3.2, 0.18),
	"s_stairs": Vector3(1.5, 3.0, 4.4),
	"s_catwalk": Vector3(4.0, 1.2, 1.3),
	"s_railing": Vector3(2.0, 1.1, 0.1),
	"s_sign": Vector3(0.9, 2.2, 0.12),
	"s_slab": Vector3(4.0, 0.06, 4.0),
}

const COL_STEEL := Color(0.16, 0.17, 0.19)
const COL_WALL := Color(0.82, 0.82, 0.79)
const COL_DECK := Color(0.34, 0.35, 0.37)
const COL_SAFETY := Color(0.95, 0.78, 0.05)
const COL_GLASS := Color(0.75, 0.85, 0.95, 0.16)

const COLORS := {
	"s_column": COL_STEEL,
	"s_beam": COL_STEEL,
	"s_wall": COL_WALL,
	"s_deck": COL_DECK,
	"s_door": COL_WALL,
	"s_window": COL_WALL,
	"s_stairs": COL_DECK,
	"s_catwalk": COL_DECK,
	"s_railing": COL_STEEL,
	"s_sign": Color(0.10, 0.32, 0.52),
	"s_slab": Color(0.86, 0.85, 0.80),
}


## Walls, doors and windows are painted panels, not polished steel;
## the finish heuristic in ViewUtil.flat would read their light grey
## as stainless.
static func material_for(type_id: String) -> Material:
	if type_id == "s_slab":
		return tile_floor()
	if type_id in ["s_wall", "s_door", "s_window"]:
		return ViewUtil.matte(COLORS[type_id])
	return ViewUtil.flat(COLORS[type_id])


## The plant floor: matte off-white tiles with grout, laid in world
## space on whichever face is drawn, so a placed slab, the home pad and
## a hall floor all tile alike.
static func tile_floor() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/tile_floor.gdshader")
	return mat


static func beam_size(length: float) -> Vector3:
	return Vector3(clampf(length, 1.0, 8.0), 0.35, 0.3)


static func railing_size(length: float) -> Vector3:
	return Vector3(clampf(length, 0.5, 12.0), 1.1, 0.1)


static func make_view(type_id: String, name_: String, length: float = -1.0) -> StructureView:
	if not SIZES.has(type_id):
		push_error("unknown structure type '%s'" % type_id)
		return null
	var size: Vector3 = SIZES[type_id]
	if type_id == "s_beam" and length > 0.0:
		size = beam_size(length)
	elif type_id == "s_railing" and length > 0.0:
		size = railing_size(length)
	var body := StructureView.new()
	body.type_id = type_id
	body.struct_name = name_
	body.collision_layer = 1
	body.collision_mask = 0
	match type_id:
		"s_door":
			_build_door(body, size)
		"s_window":
			_build_window(body, size)
		"s_stairs":
			_build_stairs(body, size)
		"s_catwalk":
			_build_catwalk(body, size)
		"s_railing":
			_build_railing(body, size)
		"s_sign":
			_build_sign(body, size)
		_:
			_build_basic(body, type_id, size)
	body.set_meta("view", body)
	body.set_meta("structure_name", name_)
	return body


static func _collide(body: StructureView, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	return shape


static func _build_basic(body: StructureView, type_id: String, size: Vector3) -> void:
	_collide(body, size, Vector3.ZERO)
	ViewUtil.box(body, size, Vector3.ZERO, material_for(type_id))
	# Flange lines on steel members so they read as sections, not slabs.
	var steel := ViewUtil.flat(COLORS[type_id])
	var bolt := ViewUtil.flat(Color(0.35, 0.36, 0.38))
	if type_id == "s_column":
		# Base and cap plates with anchor bolts, and the section's two
		# flanges standing proud of the web on either face.
		for face_y: float in [-size.y / 2.0 + 0.02, size.y / 2.0 - 0.02]:
			ViewUtil.box(body, Vector3(0.5, 0.03, 0.5), Vector3(0, face_y, 0), steel)
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			ViewUtil.cylinder(body, 0.018, 0.05, Vector3(corner.x * 0.2, -size.y / 2.0 + 0.05, corner.y * 0.2), bolt)
		for face_z: float in [-1.0, 1.0]:
			ViewUtil.box(body, Vector3(size.x + 0.04, size.y - 0.1, 0.03),
				Vector3(0, 0, face_z * (size.z / 2.0 - 0.005)), steel)
	elif type_id == "s_beam":
		# Top and bottom flanges, and a web stiffener every metre and a half.
		for flange_y: float in [-size.y / 2.0 + 0.015, size.y / 2.0 - 0.015]:
			ViewUtil.box(body, Vector3(size.x, 0.03, size.z + 0.1), Vector3(0, flange_y, 0), steel)
		var count := maxi(1, int(size.x / 1.5))
		for i in count:
			var x := -size.x / 2.0 + size.x * (i + 0.5) / count
			ViewUtil.box(body, Vector3(0.02, size.y - 0.06, size.z + 0.08), Vector3(x, 0, 0), steel)
	elif type_id == "s_deck":
		# Grating lines across the top so a deck reads as walkway.
		var lines := int(size.x / 0.25)
		for i in lines:
			ViewUtil.box(body, Vector3(0.012, 0.006, size.z - 0.04),
				Vector3(-size.x / 2.0 + 0.125 + i * 0.25, size.y / 2.0 + 0.003, 0),
				ViewUtil.flat(Color(0.22, 0.23, 0.25)))


## Doorway frame with a sliding leaf. Opening 1.24 x 2.05; the leaf
## and its blocker slide together, and the blocker disables once the
## leaf is mostly open so the doorway is passable.
static func _build_door(body: StructureView, size: Vector3) -> void:
	var mat := material_for("s_door")
	var half_h := size.y / 2.0
	for side: float in [-1.0, 1.0]:
		var jamb := Vector3(0.18, size.y, size.z)
		_collide(body, jamb, Vector3(side * 0.71, 0, 0))
		ViewUtil.box(body, jamb, Vector3(side * 0.71, 0, 0), mat)
	var header := Vector3(size.x, size.y - 2.05, size.z)
	_collide(body, header, Vector3(0, half_h - header.y / 2.0, 0))
	ViewUtil.box(body, header, Vector3(0, half_h - header.y / 2.0, 0), mat)
	var leaf_size := Vector3(1.24, 2.05, 0.06)
	var leaf_pos := Vector3(0, -half_h + leaf_size.y / 2.0, 0)
	var leaf := Node3D.new()
	leaf.position = leaf_pos
	body.add_child(leaf)
	ViewUtil.box(leaf, leaf_size, Vector3.ZERO, ViewUtil.flat(Color(0.60, 0.62, 0.66)))
	ViewUtil.box(leaf, Vector3(0.05, 0.35, 0.08), Vector3(-0.45, 0, 0),
		ViewUtil.flat(COL_STEEL))
	body._door_leaf = leaf
	var blocker := _collide(body, Vector3(leaf_size.x, leaf_size.y, 0.1), leaf_pos)
	body._door_blocker = blocker


static func _build_window(body: StructureView, size: Vector3) -> void:
	var mat := material_for("s_window")
	_collide(body, size, Vector3.ZERO)
	ViewUtil.box(body, Vector3(size.x, 1.0, size.z), Vector3(0, -size.y / 2.0 + 0.5, 0), mat)
	ViewUtil.box(body, Vector3(size.x, 0.6, size.z), Vector3(0, size.y / 2.0 - 0.3, 0), mat)
	for side: float in [-1.0, 1.0]:
		ViewUtil.box(body, Vector3(0.3, size.y - 1.6, size.z),
			Vector3(side * (size.x / 2.0 - 0.15), 0.2, 0), mat)
	var glass_mat := ViewUtil.flat(COL_GLASS)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.metallic = 0.2
	glass_mat.roughness = 0.05
	var pane := ViewUtil.box(body, Vector3(size.x - 0.6, size.y - 1.6, 0.05),
		Vector3(0, 0.2, 0), glass_mat)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for post_x: float in [-1.0, 0.0, 1.0]:
		ViewUtil.box(body, Vector3(0.08, size.y - 1.6, size.z * 0.6),
			Vector3(post_x, 0.2, 0), ViewUtil.flat(COL_STEEL))


## Open-riser stairs ascending toward local -Z: treads are visual, an
## invisible convex wedge does the climbing (the hall's proven trick).
## A flight with a landing: the last LANDING metres at the top are flat
## at full height. Without it the player's capsule reaches a deck edge
## with its feet still a quarter metre down the slope, and the edge
## beam and slab are a wall it cannot climb. Set the flight so its top
## edge sits 0.1 m inside the deck: the landing then spans the edge
## beam and the player walks straight off.
const STAIR_LANDING := 0.6


static func _build_stairs(body: StructureView, size: Vector3) -> void:
	var half_h := size.y / 2.0
	var half_d := size.z / 2.0
	var landing := STAIR_LANDING
	var run := size.z - landing
	var steps := 15
	var rise := size.y / steps
	var tread := (run - 0.2) / steps
	var tread_mat := ViewUtil.flat(COLORS["s_stairs"])
	for i in range(steps):
		ViewUtil.box(body, Vector3(size.x - 0.1, 0.06, tread),
			Vector3(0, -half_h + rise * (i + 1) - 0.03, half_d - 0.1 - tread * (i + 0.5)),
			tread_mat)
	ViewUtil.box(body, Vector3(size.x - 0.1, 0.06, landing),
		Vector3(0, half_h, -half_d + landing / 2.0), tread_mat)
	# Handrails climb with the treads: the flight rises toward -z, so a
	# positive pitch about x drops the +z end. A level rail guards the
	# landing.
	for side: float in [-1.0, 1.0]:
		var rail_len := sqrt(size.y * size.y + run * run)
		var rail := ViewUtil.box(body, Vector3(0.06, 0.06, rail_len),
			Vector3(side * (size.x / 2.0 - 0.03), 0.55, landing / 2.0), ViewUtil.flat(COL_STEEL))
		rail.rotation.x = atan2(size.y, run)
		ViewUtil.box(body, Vector3(0.06, 0.06, landing),
			Vector3(side * (size.x / 2.0 - 0.03), half_h + 0.95, -half_d + landing / 2.0),
			ViewUtil.flat(COL_STEEL))
	var points := PackedVector3Array()
	for side: float in [-1.0, 1.0]:
		var x := side * size.x / 2.0
		points.append(Vector3(x, half_h + 0.03, -half_d))            # landing, outer end
		points.append(Vector3(x, half_h + 0.03, -half_d + landing))  # landing, top of the slope
		points.append(Vector3(x, -half_h, -half_d))                  # below the landing
		points.append(Vector3(x, -half_h, half_d))                   # bottom front
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var shape := CollisionShape3D.new()
	shape.shape = hull
	body.add_child(shape)


static func _build_catwalk(body: StructureView, size: Vector3) -> void:
	var deck := Vector3(size.x, 0.1, 1.2)
	var deck_y := -size.y / 2.0 + 0.05
	_collide(body, deck, Vector3(0, deck_y, 0))
	ViewUtil.box(body, deck, Vector3(0, deck_y, 0), ViewUtil.flat(COLORS["s_catwalk"]))
	# Grating lines so it reads as walkway, not slab.
	for i in range(int(size.x / 0.5)):
		ViewUtil.box(body, Vector3(0.02, 0.012, 1.2),
			Vector3(-size.x / 2.0 + 0.25 + i * 0.5, deck_y + 0.06, 0),
			ViewUtil.flat(Color(0.22, 0.23, 0.25)))
	for side: float in [-1.0, 1.0]:
		var rail_z := side * 0.58
		_collide(body, Vector3(size.x, 1.05, 0.06), Vector3(0, deck_y + 0.6, rail_z))
		for rail_y: float in [deck_y + 1.1, deck_y + 0.6]:
			ViewUtil.box(body, Vector3(size.x, 0.05, 0.05), Vector3(0, rail_y, rail_z),
				ViewUtil.flat(COL_STEEL))
		ViewUtil.box(body, Vector3(size.x, 0.12, 0.03), Vector3(0, deck_y + 0.12, rail_z),
			ViewUtil.flat(COL_SAFETY))
		var posts := maxi(2, int(size.x / 2.0) + 1)
		for i in range(posts):
			var t := float(i) / float(posts - 1)
			ViewUtil.box(body, Vector3(0.05, 1.05, 0.05),
				Vector3(-size.x / 2.0 + 0.05 + t * (size.x - 0.1), deck_y + 0.575, rail_z),
				ViewUtil.flat(COL_STEEL))


static func _build_railing(body: StructureView, size: Vector3) -> void:
	_collide(body, size, Vector3.ZERO)
	var half_h := size.y / 2.0
	for rail_y: float in [half_h - 0.05, half_h - 0.55]:
		ViewUtil.box(body, Vector3(size.x, 0.05, 0.05), Vector3(0, rail_y, 0),
			ViewUtil.flat(COL_STEEL))
	ViewUtil.box(body, Vector3(size.x, 0.12, 0.03), Vector3(0, -half_h + 0.1, 0),
		ViewUtil.flat(COL_SAFETY))
	var posts := maxi(2, int(size.x / 2.0) + 1)
	for i in range(posts):
		var t := float(i) / float(posts - 1)
		ViewUtil.box(body, Vector3(0.06, size.y - 0.05, 0.06),
			Vector3(-size.x / 2.0 + 0.03 + t * (size.x - 0.06), -0.025, 0),
			ViewUtil.flat(COL_STEEL))


static func _build_sign(body: StructureView, size: Vector3) -> void:
	var half_h := size.y / 2.0
	_collide(body, Vector3(0.1, 1.6, 0.1), Vector3(0, -half_h + 0.8, 0))
	ViewUtil.box(body, Vector3(0.08, 1.6, 0.08), Vector3(0, -half_h + 0.8, 0),
		ViewUtil.flat(COL_STEEL))
	ViewUtil.box(body, Vector3(size.x, 0.62, 0.06), Vector3(0, half_h - 0.45, 0),
		ViewUtil.flat(COLORS["s_sign"]))
	var label := Label3D.new()
	label.text = "SIGN"
	label.position = Vector3(0, half_h - 0.45, 0.045)
	label.font_size = 44
	label.pixel_size = 0.0035
	label.width = 250.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(0.96, 0.96, 0.93)
	label.visibility_range_end = 45.0
	body.add_child(label)
	body._sign_label = label


## "" when the element can bear where the ghost sits, else the refusal
## reason. base_pos is the placement point (bottom center), world space.
static func placement_ok(type_id: String, base_pos: Vector3, rot_y: float,
		space: PhysicsDirectSpaceState3D, length: float = -1.0) -> String:
	var basis := Basis.from_euler(Vector3(0, rot_y, 0))
	match type_id:
		"s_column", "s_wall", "s_door", "s_window", "s_stairs", "s_sign", "s_slab":
			if not bears_point(base_pos, space, 0.6):
				return "needs bearing below"
		"s_beam", "s_railing":
			var size := beam_size(length) if type_id == "s_beam" else railing_size(length)
			if length <= 0.0:
				size = SIZES[type_id]
			var half: float = size.x / 2.0 - 0.1
			for side: float in [-1.0, 1.0]:
				if not bears_point(base_pos + basis * Vector3(half * side, 0, 0), space, 1.0):
					return "%s needs support at both ends" % ("beam" if type_id == "s_beam" else "railing")
		"s_deck", "s_catwalk":
			var size: Vector3 = SIZES[type_id]
			var found := 0
			for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				var offset := basis * Vector3(corner.x * (size.x / 2.0 - 0.3), 0,
					corner.y * (size.z / 2.0 - 0.3))
				if bears_point(base_pos + offset, space, 1.0):
					found += 1
			if found < 2:
				return "needs at least two supports under it"
	return ""


## Is there something to bear on at/below this point? A small box
## query, not a hairline ray: real seats have width, and a beam whose
## end lands 2 cm past a column's face still bears on it.
static func bears_point(point: Vector3, space: PhysicsDirectSpaceState3D,
		depth: float = 1.0) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, depth, 0.3)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY,
		point + Vector3(0, 0.05 - depth / 2.0, 0))
	return not space.intersect_shape(query, 1).is_empty()
