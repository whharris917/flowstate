class_name AsepticSuite
extends Node3D
## The aseptic annex west of the hall: airlock 1 -> gowning room ->
## airlock 2 -> aseptic core, with an isolator (glove ports, RTP
## hatch) in the core. Geometry is placeholder boxes; the truth is the
## SimAirCascade record whose door states these views set and whose
## room pressures the DP gauges read.
##
## All coordinates are world-space (the suite node sits at the world
## origin). The hall's west wall has a matching cut at HALL_DOOR_Z0/Z1.

const H := 3.2
const T := 0.15
const HALL_X := -22.0
const HALL_DOOR_Z0 := -5.75
const HALL_DOOR_Z1 := -4.25
const HALL_DOOR_H := 2.5

const COL_WALL := Color(0.92, 0.92, 0.90)
const COL_FLOOR := Color(0.75, 0.76, 0.74)
const COL_STEEL := Color(0.16, 0.17, 0.19)
const COL_GLASS := Color(0.70, 0.80, 0.88, 0.35)

# The cascade this suite realizes. PlantFactory builds the record from
# these tables; the view builds the rooms from the same geometry.
const ROOMS: Array[Dictionary] = [
	{"id": "al1", "volume_m3": 12.0, "supply_lps": 12.0},
	{"id": "gown", "volume_m3": 30.0, "supply_lps": 25.0},
	{"id": "al2", "volume_m3": 12.0, "supply_lps": 15.0},
	{"id": "core", "volume_m3": 80.0, "supply_lps": 60.0},
	{"id": "iso", "volume_m3": 2.0, "supply_lps": 4.0},
]
const DOORS: Array[Dictionary] = [
	{"id": "hall_al1", "a": "al1", "b": "ambient", "leak_closed": 3.0, "leak_open": 80.0},
	{"id": "al1_gown", "a": "gown", "b": "al1", "leak_closed": 3.0, "leak_open": 80.0},
	{"id": "gown_al2", "a": "al2", "b": "gown", "leak_closed": 3.0, "leak_open": 80.0},
	{"id": "al2_core", "a": "core", "b": "al2", "leak_closed": 3.0, "leak_open": 80.0},
	{"id": "iso_hatch", "a": "iso", "b": "core", "leak_closed": 0.12, "leak_open": 40.0},
]

var cascade: SimAirCascade


func setup(cascade_: SimAirCascade) -> void:
	cascade = cascade_
	_build_shell()
	_build_doors()
	_build_isolator()
	_build_furniture()
	_build_lights()


func _build_shell() -> void:
	_slab(-39.5, HALL_X, -11.0, -1.0, -0.5, 0.0, COL_FLOOR)      # foundation
	_slab(-39.5, HALL_X, -11.0, -1.0, H, H + 0.15, COL_WALL)     # roof

	_wall_x(-25.0, -9.0, -3.0, -6.0)     # AL1 | gowning (door)
	_wall_x(-28.6, -9.0, -3.0, -6.0)     # gowning | AL2 (door)
	_wall_x(-31.2, -11.0, -1.0, -6.0)    # AL2 | core (door)
	_wall_x(-39.5, -11.0, -1.0, NAN)     # far wall

	_wall_z(-8.0, -25.0, HALL_X)         # AL1 shell
	_wall_z(-4.0, -25.0, HALL_X)
	_wall_z(-9.0, -28.6, -25.0)          # gowning shell
	_wall_z(-3.0, -28.6, -25.0)
	_wall_z(-8.0, -31.2, -28.6)          # AL2 shell
	_wall_z(-4.0, -31.2, -28.6)
	_wall_z(-11.0, -39.5, -31.2)         # core shell
	_wall_z(-1.0, -39.5, -31.2)

	for label_data: Array in [["AIRLOCK 1", -23.5, -6.05], ["GOWNING", -26.8, -3.2],
			["AIRLOCK 2", -29.9, -6.05], ["ASEPTIC CORE", -35.3, -1.2]]:
		var tag := ViewUtil.label(self, label_data[0], Vector3(label_data[1], 2.6, label_data[2]))
		tag.font_size = 48


func _build_doors() -> void:
	_door(Vector3(HALL_X, 0, -5.0), "hall_al1", "AL-1 hall door")
	_door(Vector3(-25.0, 0, -6.0), "al1_gown", "AL-1 gowning door")
	_door(Vector3(-28.6, 0, -6.0), "gown_al2", "AL-2 gowning door")
	_door(Vector3(-31.2, 0, -6.0), "al2_core", "AL-2 core door")


func _door(pos: Vector3, door_id: String, label_: String) -> void:
	var door := SuiteDoorView.new()
	door.position = pos
	add_child(door)
	door.setup(cascade, door_id, label_)


func _build_isolator() -> void:
	var center := Vector3(-35.3, 0, -6.0)
	for leg_offset: Vector3 in [Vector3(-1.0, 0, -0.4), Vector3(1.0, 0, -0.4),
			Vector3(-1.0, 0, 0.4), Vector3(1.0, 0, 0.4)]:
		ViewUtil.box(self, Vector3(0.08, 1.0, 0.08),
			center + leg_offset + Vector3(0, 0.5, 0), ViewUtil.flat(COL_STEEL))
	var shell := ViewUtil.flat(Color(0.80, 0.82, 0.84))
	shell.metallic = 0.6
	shell.roughness = 0.3
	ViewUtil.box(self, Vector3(2.4, 0.12, 1.1), center + Vector3(0, 1.06, 0), shell)   # base tray
	ViewUtil.box(self, Vector3(2.4, 0.12, 1.1), center + Vector3(0, 2.14, 0), shell)   # top
	ViewUtil.box(self, Vector3(0.12, 1.1, 1.1), center + Vector3(-1.14, 1.6, 0), shell)
	ViewUtil.box(self, Vector3(0.12, 1.1, 1.1), center + Vector3(1.14, 1.6, 0), shell)
	var glass := ViewUtil.flat(COL_GLASS)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var front := ViewUtil.box(self, Vector3(2.2, 1.0, 0.03), center + Vector3(0, 1.6, 0.53), glass)
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var back := ViewUtil.box(self, Vector3(2.2, 1.0, 0.03), center + Vector3(0, 1.6, -0.53), glass)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ViewUtil.label(self, "isolator", center + Vector3(0, 2.6, 0))

	for glove_data: Array in [[-0.6, 1], [0.6, 2]]:
		var glove := GlovePortView.new()
		glove.position = center + Vector3(glove_data[0], 1.45, 0.55)
		add_child(glove)
		glove.setup(glove_data[1])

	# Rapid-transfer hatch on the west end, scaled-down sliding door.
	var hatch := SuiteDoorView.new()
	hatch.position = center + Vector3(-1.2, 1.15, 0)
	hatch.rotation_degrees = Vector3(0, 90, 0)
	hatch.scale = Vector3(0.35, 0.35, 0.35)
	add_child(hatch)
	hatch.setup(cascade, "iso_hatch", "RTP hatch")


func _build_furniture() -> void:
	# Gowning bench and locker — set dressing for the gowning ritual.
	ViewUtil.box(self, Vector3(1.8, 0.08, 0.4), Vector3(-26.8, 0.45, -8.3),
		ViewUtil.flat(Color(0.70, 0.68, 0.60)))
	for leg_x: float in [-27.6, -26.0]:
		ViewUtil.box(self, Vector3(0.06, 0.45, 0.34), Vector3(leg_x, 0.225, -8.3),
			ViewUtil.flat(COL_STEEL))
	ViewUtil.box(self, Vector3(0.5, 2.0, 1.6), Vector3(-25.45, 1.0, -3.9),
		ViewUtil.flat(Color(0.55, 0.58, 0.62)))
	# Ceiling supply diffusers — the cascade's air, made visible.
	for diffuser: Vector3 in [Vector3(-23.5, 0, -6), Vector3(-26.8, 0, -6),
			Vector3(-29.9, 0, -6), Vector3(-33.5, 0, -6), Vector3(-37.0, 0, -6)]:
		ViewUtil.box(self, Vector3(0.5, 0.06, 0.5), Vector3(diffuser.x, H - 0.04, diffuser.z),
			ViewUtil.flat(Color(0.82, 0.83, 0.85)))


func _build_lights() -> void:
	for light_pos: Vector3 in [Vector3(-23.5, 0, -6), Vector3(-26.8, 0, -6),
			Vector3(-29.9, 0, -6), Vector3(-33.5, 0, -6), Vector3(-37.0, 0, -6)]:
		var strip := ViewUtil.box(self, Vector3(1.0, 0.05, 0.12),
			Vector3(light_pos.x, H - 0.12, light_pos.z), ViewUtil.glow(Color(0.93, 0.96, 1.0), 2.0))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.position = Vector3(light_pos.x, H - 0.4, light_pos.z)
		light.light_energy = 0.85
		light.light_color = Color(0.93, 0.96, 1.0)
		light.omni_range = 5.5
		add_child(light)


func _wall_x(x: float, z0: float, z1: float, door_z: float) -> void:
	if is_nan(door_z):
		_slab(x - T / 2.0, x + T / 2.0, z0, z1, 0.0, H, COL_WALL)
		return
	var opening_half := 0.68
	_slab(x - T / 2.0, x + T / 2.0, z0, door_z - opening_half, 0.0, H, COL_WALL)
	_slab(x - T / 2.0, x + T / 2.0, door_z + opening_half, z1, 0.0, H, COL_WALL)
	_slab(x - T / 2.0, x + T / 2.0, door_z - opening_half, door_z + opening_half,
		2.3, H, COL_WALL)


func _wall_z(z: float, x0: float, x1: float) -> void:
	_slab(x0, x1, z - T / 2.0, z + T / 2.0, 0.0, H, COL_WALL)


func _slab(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float,
		color: Color) -> void:
	var size := Vector3(x1 - x0, y1 - y0, z1 - z0)
	var pos := Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = ViewUtil.flat(color)
	body.add_child(mesh)
	add_child(body)
