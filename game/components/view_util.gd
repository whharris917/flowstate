class_name ViewUtil
## Shared art helpers. Boxes, cylinders, a material factory, one
## emissive variant, the interact volume and the floating label.
##
## Finish (director, 2026-09-11: "as realistic as possible", which
## retires the flat-colour placeholder policy): every view already
## encodes what a part is made of in the colour it asks for, so flat()
## reads the finish off the colour. A low-saturation light grey is
## brushed stainless; a low-saturation dark grey is painted or cast
## steel; anything with colour in it is enamel paint; anything with
## alpha is glass. Concrete, rubber and fabric ask for matte() by name.


## A material whose finish follows the colour. See the class comment.
static func flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.08
		mat.metallic = 0.0
		mat.metallic_specular = 0.9
	elif color.s < 0.13 and color.v > 0.45:
		_stainless(mat)
	elif color.s < 0.13:
		mat.metallic = 0.55
		mat.roughness = 0.58
	else:
		mat.metallic = 0.04
		mat.roughness = 0.42
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.25
		mat.clearcoat_roughness = 0.35
	return mat


## Brushed stainless, whatever the tint: the vessel shells, the
## sanitary lines, the handrails.
static func steel(color: Color = Color(0.62, 0.66, 0.70)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_stainless(mat)
	return mat


## Enamel paint, whatever the tint: pump casings, cabinets, steelwork.
static func painted(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.04
	mat.roughness = 0.42
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.25
	mat.clearcoat_roughness = 0.35
	return mat


## Dull and dielectric: concrete, rubber, grating paint, fabric.
static func matte(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 0.92
	return mat


static func _stainless(mat: StandardMaterial3D) -> void:
	mat.metallic = 0.92
	mat.roughness = 0.34
	mat.metallic_specular = 0.6
	# The brushing: anisotropic highlights along the surface, which the
	# primitive meshes' tangents carry for free.
	mat.anisotropy_enabled = true
	mat.anisotropy = 0.55


static func glow(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var mat := flat(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


## Invisible box collider that routes interaction back to a view node.
## The raycast hits this and follows the "view" meta to describe()/use().
## Lives on layer 4: rays probe it, but the player walks through it —
## otherwise a door's interact volume would block its own doorway.
static func interact_body(view: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = pos
	body.set_meta("view", view)
	view.add_child(body)
	return body


static func label(parent: Node3D, text: String, pos: Vector3) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.85, 0.85, 0.82)
	parent.add_child(lbl)
	return lbl
