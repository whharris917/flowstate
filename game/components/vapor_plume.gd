class_name VaporPlume
extends GPUParticles3D
## Soft white vapor for stacks, vents, and flash steam. Continuous
## plumes are throttled with set_strength() from real sim state;
## puff() fires one explosive cloud for a discrete event (a vent
## burst). Placeholder-art particles: billboard quads fading out as
## they rise and swell.

static func make(parent: Node3D, at: Vector3, size: float = 1.0,
		one_shot_: bool = false) -> VaporPlume:
	var plume := VaporPlume.new()
	plume.position = at
	plume.amount = 28 if not one_shot_ else 16
	plume.lifetime = 2.6 * size
	plume.one_shot = one_shot_
	plume.explosiveness = 1.0 if one_shot_ else 0.0
	plume.emitting = false
	plume.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 12.0
	proc.initial_velocity_min = 0.7 * size
	proc.initial_velocity_max = 1.3 * size
	proc.gravity = Vector3(0, 0.35, 0)
	proc.damping_min = 0.15
	proc.damping_max = 0.3
	proc.scale_min = 0.5 * size
	proc.scale_max = 0.9 * size
	var grow := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	grow.curve = curve
	proc.scale_curve = grow
	var ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	gradient.add_point(0.12, Color(1, 1, 1, 0.30))
	gradient.add_point(0.55, Color(1, 1, 1, 0.16))
	ramp.gradient = gradient
	proc.color_ramp = ramp
	plume.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55) * size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.94, 0.95, 0.97)
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	plume.draw_pass_1 = quad
	parent.add_child(plume)
	return plume


## Continuous plume throttle: 0 stops it, up to 1 for a full stack.
func set_strength(frac: float) -> void:
	if frac <= 0.01:
		emitting = false
		return
	emitting = true
	amount_ratio = clampf(frac, 0.15, 1.0)


## One discrete cloud, for a real burst event.
func puff() -> void:
	restart()
	emitting = true
