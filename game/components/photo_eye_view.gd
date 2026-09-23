class_name PhotoEyeView
extends VialPartView
## Renders a SimPhotoEye: an emitter and a reflector on little posts
## either side of the track, the beam between them at half a vial's
## height drawn faint red while clear, and the emitter's lamp lit while
## a vial breaks it. The origin is the beam's point on the centreline;
## its post stands at +z a hand upstream, clear of a gate's at the beam
## and a needle's over it.

var eye: SimPhotoEye
var _beam: MeshInstance3D
var _lamp: StandardMaterial3D


func _build() -> void:
	eye = record as SimPhotoEye
	var h: float = vial_row()[1]
	var y := DECK + h * 0.5
	var dark := ViewUtil.flat(Color(0.14, 0.15, 0.16))
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	ViewUtil.box(self, Vector3(0.03, DECK + 0.02, 0.03), Vector3(-0.07, (DECK + 0.02) / 2.0, 0.16), steel)
	ViewUtil.cylinder(self, 0.05, 0.01, Vector3(-0.07, 0.005, 0.16), dark)
	ViewUtil.box(self, Vector3(0.05, 0.12, 0.02), Vector3(-0.07, 0.6, 0.155), dark)
	for z: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(0.012, y - DECK + 0.02, 0.012), Vector3(0, (y + DECK) / 2.0, z * 0.07), steel)
	# The arm from the post to the emitter's side.
	ViewUtil.box(self, Vector3(0.07, 0.012, 0.012), Vector3(-0.035, DECK + 0.02, 0.16), steel)
	ViewUtil.box(self, Vector3(0.012, 0.012, 0.09), Vector3(0, DECK + 0.02, 0.115), steel)
	ViewUtil.box(self, Vector3(0.02, 0.02, 0.018), Vector3(0, y, 0.06), dark)
	ViewUtil.box(self, Vector3(0.02, 0.02, 0.006), Vector3(0, y, -0.065), ViewUtil.flat(Color(0.8, 0.2, 0.15)))
	_beam = MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.0012
	beam.bottom_radius = 0.0012
	beam.height = 0.12
	beam.radial_segments = 6
	_beam.mesh = beam
	_beam.material_override = ViewUtil.glow(Color(1.0, 0.15, 0.1), 0.6)
	_beam.rotation_degrees = Vector3(90, 0, 0)
	_beam.position = Vector3(0, y, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_lamp = ViewUtil.glow(Color(1.0, 0.7, 0.1), 1.2)
	ViewUtil.cylinder(self, 0.004, 0.004, Vector3(0.011, y + 0.004, 0.06), _lamp).rotation_degrees = Vector3(0, 0, 90)
	var tag := ViewUtil.label(self, eye.comp_name, Vector3(0, DECK + 0.2, 0.12))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.05, 0.08, 0.18), Vector3(0, y, 0.02))


func _process(_delta: float) -> void:
	if eye == null:
		return
	_beam.visible = not eye.seen
	_lamp.emission_energy_multiplier = 1.2 if eye.seen else 0.0
	_lamp.albedo_color = Color(1.0, 0.7, 0.1) if eye.seen else Color(0.25, 0.22, 0.15)


func describe() -> String:
	var where := " on %s" % eye.host if eye.host != "" else " · not over a track"
	return "%s — photo-eye%s\n%s" % [eye.comp_name, where, "VIAL IN THE BEAM" if eye.seen else "beam clear"]
