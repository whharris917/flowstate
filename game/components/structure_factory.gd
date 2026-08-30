class_name StructureFactory
## Placeable structural elements: columns, beams, walls, decks. They
## exist to carry pipe, conduit, and equipment — the support rule
## (SupportCheck) counts them, and their own placement has bearing
## rules so structure itself can't float.

const CATALOG: Array[Dictionary] = [
	{"type": "s_column", "label": "Steel column 6 m"},
	{"type": "s_beam", "label": "Beam — stretch to fit"},
	{"type": "s_wall", "label": "Wall panel 4 m"},
	{"type": "s_deck", "label": "Deck / ceiling 4 m"},
	{"type": "run_pipe", "label": "Pipe run"},
	{"type": "run_conduit", "label": "Conduit run"},
	{"type": "run_tray", "label": "Cable tray"},
]

# Standalone routed infrastructure — laid before any equipment exists,
# no kernel wire behind it. Colliders live on layer 1: a tray or rack
# pipe is real support the support rule can count.
const RUNS := {
	"run_pipe": {"radius": 0.07, "style": "pipe", "color": Color(0.65, 0.67, 0.70)},
	"run_conduit": {"radius": 0.025, "style": "pipe", "color": Color(0.72, 0.72, 0.75)},
	"run_tray": {"radius": 0.20, "style": "tray", "color": Color(0.55, 0.57, 0.60)},
}

# Beams stretch between two supported points, up to a maximum span.
const BEAM_MIN := 1.0
const BEAM_MAX := 8.0

const SIZES := {
	"s_column": Vector3(0.35, 6.0, 0.35),
	"s_beam": Vector3(6.0, 0.35, 0.3),
	"s_wall": Vector3(4.0, 3.2, 0.18),
	"s_deck": Vector3(4.0, 0.15, 4.0),
}

const COLORS := {
	"s_column": Color(0.16, 0.17, 0.19),
	"s_beam": Color(0.16, 0.17, 0.19),
	"s_wall": Color(0.82, 0.82, 0.79),
	"s_deck": Color(0.34, 0.35, 0.37),
}


static func beam_size(length: float) -> Vector3:
	return Vector3(clampf(length, BEAM_MIN, BEAM_MAX), 0.35, 0.3)


static func make_view(type_id: String, name_: String, length: float = -1.0) -> StructureView:
	if not SIZES.has(type_id):
		push_error("unknown structure type '%s'" % type_id)
		return null
	var size: Vector3 = SIZES[type_id]
	if type_id == "s_beam" and length > 0.0:
		size = beam_size(length)
	var body := StructureView.new()
	body.type_id = type_id
	body.struct_name = name_
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = ViewUtil.flat(COLORS[type_id])
	body.add_child(mesh)
	# Flange lines on steel members so they read as sections, not slabs.
	if type_id == "s_column":
		for face_y: float in [-size.y / 2.0 + 0.02, size.y / 2.0 - 0.02]:
			ViewUtil.box(body, Vector3(0.5, 0.03, 0.5), Vector3(0, face_y, 0),
				ViewUtil.flat(COLORS[type_id]))
	elif type_id == "s_beam":
		for flange_y: float in [-size.y / 2.0 + 0.015, size.y / 2.0 - 0.015]:
			ViewUtil.box(body, Vector3(size.x, 0.03, size.z + 0.1), Vector3(0, flange_y, 0),
				ViewUtil.flat(COLORS[type_id]))
	body.set_meta("view", body)
	body.set_meta("structure_name", name_)
	return body


## "" when the element can bear where the ghost sits, else the refusal
## reason. base_pos is the placement point (bottom center), world space.
static func placement_ok(type_id: String, base_pos: Vector3, rot_y: float,
		space: PhysicsDirectSpaceState3D, length: float = -1.0) -> String:
	var basis := Basis.from_euler(Vector3(0, rot_y, 0))
	match type_id:
		"s_column":
			if not bears_point(base_pos, space, 0.6):
				return "column needs bearing below"
		"s_wall":
			if not bears_point(base_pos, space, 0.6):
				return "wall needs bearing below"
		"s_beam":
			var size := beam_size(length) if length > 0.0 else SIZES[type_id] as Vector3
			var half: float = size.x / 2.0 - 0.2
			for side: float in [-1.0, 1.0]:
				if not bears_point(base_pos + basis * Vector3(half * side, 0, 0), space, 1.0):
					return "beam needs support at both ends"
		"s_deck":
			var size: Vector3 = SIZES[type_id]
			var found := 0
			for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				var offset := basis * Vector3(corner.x * (size.x / 2.0 - 0.3), 0,
					corner.y * (size.z / 2.0 - 0.3))
				if bears_point(base_pos + offset, space, 1.0):
					found += 1
			if found < 2:
				return "deck needs at least two supports under it"
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
