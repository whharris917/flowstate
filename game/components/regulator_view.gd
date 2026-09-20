class_name RegulatorView
extends Node3D
## Renders a SimRegulator: a body on the line with the spring bonnet
## standing on it — a dome with the adjusting screw and its lock nut on
## top — and a small gauge on the outlet side whose needle reads the
## real downstream pressure against a dial spanning twice the setting.
## Built at the bore of the line on it.

const LINE_Y := 0.32
const HALF := 0.20

var regulator: SimRegulator
var bore := 0.07
var _needle: Node3D


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_needle = null
	setup(regulator, r)


func setup(regulator_: SimRegulator, bore_r: float = 0.07) -> void:
	regulator = regulator_
	bore = bore_r
	var s := SmallBoreUtil.body_scale(bore_r)
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.28, 0.29, 0.32))
	var brass := ViewUtil.flat(Color(0.72, 0.60, 0.34))
	var body_w := 0.10 * s + 0.04
	ViewUtil.box(self, Vector3(body_w, 0.08 * s + 0.03, 0.08 * s + 0.03), Vector3(0, LINE_Y, 0), brass)
	SmallBoreUtil.spool(self, -HALF, -body_w / 2.0, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, body_w / 2.0, HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -HALF, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, HALF, LINE_Y, bore_r, steel)
	# The bonnet: a can with a domed top, the spring inside it.
	var bonnet_r := 0.040 * s + 0.018
	var bonnet_h := 0.05 * s + 0.03
	var bonnet_base := LINE_Y + 0.04 * s + 0.015
	ViewUtil.cylinder(self, bonnet_r, bonnet_h, Vector3(0, bonnet_base + bonnet_h / 2.0, 0), dark)
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = bonnet_r
	dome_mesh.height = bonnet_r * 2.0
	dome_mesh.is_hemisphere = true
	dome.mesh = dome_mesh
	dome.material_override = dark
	dome.position = Vector3(0, bonnet_base + bonnet_h, 0)
	add_child(dome)
	var dome_top := bonnet_base + bonnet_h + bonnet_r
	# The adjusting screw and its lock nut.
	ViewUtil.cylinder(self, 0.006, 0.05, Vector3(0, dome_top + 0.02, 0), steel)
	var nut := ViewUtil.cylinder(self, 0.012, 0.008, Vector3(0, dome_top + 0.004, 0), steel)
	(nut.mesh as CylinderMesh).radial_segments = 6
	ViewUtil.box(self, Vector3(0.03, 0.006, 0.006), Vector3(0, dome_top + 0.045, 0), steel)
	# The outlet gauge, standing off the body on the downstream side,
	# facing the aisle; the needle is held.
	var gauge_at := Vector3(body_w / 2.0 + 0.03, LINE_Y + 0.02, 0.06 * s + 0.03)
	var stem := ViewUtil.cylinder(self, 0.006, 0.05, Vector3(gauge_at.x, LINE_Y, gauge_at.z / 2.0), brass)
	stem.rotation_degrees = Vector3(90, 0, 0)
	var case := ViewUtil.cylinder(self, 0.03, 0.014, gauge_at, dark)
	case.rotation_degrees = Vector3(90, 0, 0)
	var face := ViewUtil.cylinder(self, 0.026, 0.004, gauge_at + Vector3(0, 0, 0.008),
		ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	face.rotation_degrees = Vector3(90, 0, 0)
	for i in 9:
		var a := deg_to_rad(-135.0 + 33.75 * i)
		var tick := ViewUtil.box(self, Vector3(0.002, 0.006, 0.002), Vector3.ZERO, dark)
		tick.position = gauge_at + Vector3(sin(a) * 0.022, cos(a) * 0.022, 0.011)
		tick.rotation.z = -a
	_needle = Node3D.new()
	_needle.position = gauge_at + Vector3(0, 0, 0.012)
	add_child(_needle)
	ViewUtil.box(_needle, Vector3(0.003, 0.022, 0.002), Vector3(0, 0.011, 0), ViewUtil.flat(Color(0.80, 0.16, 0.12)))
	var tag := ViewUtil.label(self, regulator.comp_name, Vector3(0, dome_top + 0.22, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(HALF * 2.0, dome_top + 0.05 - LINE_Y + 0.12, 0.2),
		Vector3(0, (LINE_Y + dome_top) / 2.0, 0))


func _process(_delta: float) -> void:
	if regulator == null or _needle == null:
		return
	# The dial spans zero to twice the setting: the setting is straight up.
	var frac := clampf(regulator.out_kpa / (2.0 * regulator.set_kpa), 0.0, 1.0)
	_needle.rotation.z = deg_to_rad(135.0 - 270.0 * frac)


func describe() -> String:
	return "%s — pressure regulator set %.0f kPa, %s at 1 bar full open\noutlet %.0f kPa · %.0f %% open · passing %s" % [
		regulator.comp_name, regulator.set_kpa, SimTypes.flow_text(regulator.cv_lps),
		regulator.out_kpa, regulator.opening * 100.0, SimTypes.flow_text(regulator.flow_lps)]


func use() -> void:
	pass
