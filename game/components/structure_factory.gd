class_name StructureFactory
## Placeable structural elements: columns, beams, walls, decks. They
## exist to carry pipe, conduit, and equipment — the support rule
## (SupportCheck) counts them, and their own placement has bearing
## rules so structure itself can't float.

const CATALOG: Array[Dictionary] = [
	{"type": "s_column", "label": "Steel column 6 m"},
	{"type": "s_beam", "label": "Beam 6 m"},
	{"type": "s_wall", "label": "Wall panel 4 m"},
	{"type": "s_deck", "label": "Deck / ceiling 4 m"},
]

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


static func make_view(type_id: String, name_: String) -> StructureView:
	if not SIZES.has(type_id):
		push_error("unknown structure type '%s'" % type_id)
		return null
	var size: Vector3 = SIZES[type_id]
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
		space: PhysicsDirectSpaceState3D) -> String:
	var basis := Basis.from_euler(Vector3(0, rot_y, 0))
	match type_id:
		"s_column":
			if not _bears(base_pos, 0.6, space):
				return "column needs bearing below"
		"s_wall":
			if not _bears(base_pos, 0.6, space):
				return "wall needs bearing below"
		"s_beam":
			var half: float = (SIZES[type_id] as Vector3).x / 2.0 - 0.2
			for side: float in [-1.0, 1.0]:
				if not _bears(base_pos + basis * Vector3(half * side, 0, 0), 1.0, space):
					return "beam needs support at both ends"
		"s_deck":
			var size: Vector3 = SIZES[type_id]
			var found := 0
			for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				var offset := basis * Vector3(corner.x * (size.x / 2.0 - 0.3), 0,
					corner.y * (size.z / 2.0 - 0.3))
				if _bears(base_pos + offset, 1.0, space):
					found += 1
			if found < 2:
				return "deck needs at least two supports under it"
	return ""


static func _bears(point: Vector3, depth: float, space: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3(0, 0.2, 0),
		point + Vector3(0, -depth, 0), 1)
	return not space.intersect_ray(query).is_empty()
