class_name VialDraw
extends Node3D
## Draws a carrier's vials in three draws whatever their number: the
## glass, the liquid in each at its real volume and colour, and the caps
## on those that have one (2026-09-22). Each is a MultiMesh of a unit
## cylinder scaled per vial. The liquid's colour is its composition:
## water nearly clear, product amber, as the reactor's sight glass reads.

var _glass: MultiMeshInstance3D
var _liquid: MultiMeshInstance3D
var _caps: MultiMeshInstance3D
var _capacity := 0


func _init() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.70, 0.80, 0.86, 0.34)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Drawn before what is in it, so the liquid shows its own colour
	# through the glass rather than under a pale film.
	glass.render_priority = -1
	_glass = _instances(glass)
	var liquid := StandardMaterial3D.new()
	liquid.vertex_color_use_as_albedo = true
	liquid.vertex_color_is_srgb = true
	liquid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	liquid.roughness = 0.08
	_liquid = _instances(liquid)
	var cap := StandardMaterial3D.new()
	cap.vertex_color_use_as_albedo = true
	cap.vertex_color_is_srgb = true
	cap.metallic = 0.6
	cap.roughness = 0.35
	_caps = _instances(cap)
	_grow(32)


func _instances(mat: Material) -> MultiMeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _grow(count: int) -> void:
	if count <= _capacity:
		return
	_capacity = maxi(count, _capacity * 2)
	for inst: MultiMeshInstance3D in [_glass, _liquid, _caps]:
		inst.multimesh.instance_count = _capacity
		inst.multimesh.visible_instance_count = 0


## The colour of what is in a vial.
static func liquid_color(vial: SimVial) -> Color:
	var product := vial.contents.frac(SimSpecies.PRODUCT)
	return Color(0.50, 0.72, 0.90, 0.70).lerp(Color(0.80, 0.46, 0.08, 0.92), clampf(product * 1.5, 0.0, 1.0))


## Draw these vials: [SimVial, Vector3 bottom-centre in this node's space].
func draw(items: Array) -> void:
	_grow(items.size())
	var n := 0
	var caps := 0
	var wet := 0
	for item: Array in items:
		var vial: SimVial = item[0]
		var at: Vector3 = item[1]
		var r := vial.diameter_m / 2.0
		var h := vial.height_m
		_glass.multimesh.set_instance_transform(n,
			Transform3D(Basis.from_scale(Vector3(r, h, r)), at + Vector3(0, h / 2.0, 0)))
		_glass.multimesh.set_instance_color(n, Color.WHITE)
		n += 1
		var frac := clampf(vial.volume_l / vial.brim_l, 0.0, 1.0)
		if frac > 0.002:
			var lh := h * 0.9 * frac
			_liquid.multimesh.set_instance_transform(wet,
				Transform3D(Basis.from_scale(Vector3(r * 0.86, lh, r * 0.86)), at + Vector3(0, 0.002 + lh / 2.0, 0)))
			_liquid.multimesh.set_instance_color(wet, liquid_color(vial))
			wet += 1
		if vial.capped:
			_caps.multimesh.set_instance_transform(caps,
				Transform3D(Basis.from_scale(Vector3(r * 0.62, 0.011, r * 0.62)), at + Vector3(0, h + 0.004, 0)))
			_caps.multimesh.set_instance_color(caps, Color(0.72, 0.16, 0.14))
			caps += 1
	_glass.multimesh.visible_instance_count = n
	_liquid.multimesh.visible_instance_count = wet
	_caps.multimesh.visible_instance_count = caps
