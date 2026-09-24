class_name SpillPuddle
extends MeshInstance3D
## Liquid standing where a spill or an overflow reaches the floor.
## Fed every frame with the rate arriving (L/s) from the
## record's own meter; the puddle holds a volume at a film's depth, so
## its area is that volume spread thin, and the ground takes it back at
## a steady rate per square metre -- a litre a second stands about
## twenty square metres, a drip a few centimetres across, and a puddle
## whose feed stops soaks away over about forty seconds. It is how
## much has been arriving lately, drawn; nothing about it is scripted.

const DEPTH_M := 0.002          # a film on a tiled floor
const SOAK_M_PER_S := 0.00005   # what the floor takes back, per square metre
const MAX_RADIUS_M := 3.0

var volume_m3 := 0.0
var min_radius := 0.0           # a tank's overflow pools round its base, not under it
var _mat: ShaderMaterial


static func make(parent: Node3D) -> SpillPuddle:
	var puddle := SpillPuddle.new()
	puddle.top_level = true
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A square the shader cuts to a lobed outline; its edge lies inside
	# the unit radius, so the square's corners never show.
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(2.0, 2.0)
	puddle.mesh = sheet
	puddle._mat = ShaderMaterial.new()
	puddle._mat.shader = load("res://components/spill_puddle.gdshader") as Shader
	puddle._mat.set_shader_parameter("seed", float(puddle.get_instance_id() % 97))
	puddle.material_override = puddle._mat
	puddle.visible = false
	parent.add_child(puddle)
	return puddle


## The rate arriving this frame (L/s) and where, in world space.
func feed(lps: float, at: Vector3, delta: float) -> void:
	var area := volume_m3 / DEPTH_M
	volume_m3 = maxf(volume_m3 + (maxf(lps, 0.0) * 0.001 - SOAK_M_PER_S * area) * delta, 0.0)
	area = volume_m3 / DEPTH_M
	# The outline's mean edge is at 0.8 of the sheet's half-width.
	var r := sqrt(area / PI + min_radius * min_radius) / 0.8
	r = minf(r, MAX_RADIUS_M / 0.8)
	if area < 1e-6:
		visible = false
		return
	visible = true
	global_position = at + Vector3(0, 0.004, 0)
	scale = Vector3(r, 1.0, r)
	# A thin film is barely there; a standing puddle shines.
	_mat.set_shader_parameter("alpha", clampf(0.3 + 0.25 * sqrt(area), 0.3, 0.7))
