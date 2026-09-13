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


static var _brushed_normal: ImageTexture = null


static func _stainless(mat: StandardMaterial3D) -> void:
	mat.metallic = 0.92
	mat.roughness = 0.34
	mat.metallic_specular = 0.6
	# The brushing: anisotropic highlights along the surface, which the
	# primitive meshes' tangents carry for free, and a fine grain of
	# brush lines in a normal map projected triplanar so no primitive
	# needs UVs that line up.
	mat.anisotropy_enabled = true
	mat.anisotropy = 0.55
	mat.normal_enabled = true
	mat.normal_texture = brushed_normal()
	mat.normal_scale = 0.3
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(4.0, 4.0, 4.0)


## Brush lines as a normal map: streaks of smooth noise along one axis,
## generated once (2026-09-11). Sixty-four thousand pixels, a few
## milliseconds, no asset.
static func brushed_normal() -> ImageTexture:
	if _brushed_normal != null:
		return _brushed_normal
	var n := 256
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 20260911
	noise.frequency = 1.0
	var height := PackedFloat32Array()
	height.resize(n * n)
	for y in n:
		for x in n:
			# Slow along x, fast across y: long streaks.
			height[y * n + x] = noise.get_noise_2d(x * 0.03, y * 0.9) * 0.7 \
				+ noise.get_noise_2d(x * 0.15 + 50.0, y * 2.5) * 0.3
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var hl := height[y * n + (x + n - 1) % n]
			var hr := height[y * n + (x + 1) % n]
			var hu := height[((y + n - 1) % n) * n + x]
			var hd := height[((y + 1) % n) * n + x]
			var normal := Vector3(-(hr - hl) * 3.0, -(hd - hu) * 3.0, 1.0).normalized()
			img.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))
	img.generate_mipmaps()
	_brushed_normal = ImageTexture.create_from_image(img)
	return _brushed_normal


static func glow(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var mat := flat(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	# Sides by size (2026-09-13): the default 64 on a bolt is vertices
	# for nothing; a vessel a metre across still gets 48.
	mesh.radial_segments = clampi(int(radius * 48.0), 12, 48)
	mesh.rings = 1
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
	lbl.visibility_range_end = 30.0  # unreadable further off, and each label is a draw call
	# Floating text shows only on the equipment under the crosshair
	# (director, 2026-09-13); the world reveals it by this meta.
	lbl.visible = false
	lbl.set_meta("floating", true)
	parent.add_child(lbl)
	return lbl


## Engraved text: a legend plate, a rating plate, a sign. Always shown.
static func plate(parent: Node3D, text: String, pos: Vector3) -> Label3D:
	var lbl := label(parent, text, pos)
	lbl.remove_meta("floating")
	lbl.visible = true
	return lbl
