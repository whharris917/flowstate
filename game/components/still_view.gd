class_name StillView
extends Node3D
## Renders a SimStill: a packed recovery column with a reboiler at the
## base and an overhead condenser. The reboiler glows with real duty,
## the condenser plume tracks actual boilup, and the overhead line only
## runs full when distillate is genuinely going over the top.

var still: SimStill
var _reboiler: MeshInstance3D
var _overhead: MeshInstance3D
var _label: Label3D
var _boil: EquipmentAudio
var _plume: VaporPlume


func setup(still_: SimStill) -> void:
	still = still_
	var steel := ViewUtil.flat(Color(0.60, 0.64, 0.68))
	steel.metallic = 0.5
	steel.roughness = 0.33
	var lagging := ViewUtil.flat(Color(0.78, 0.78, 0.74))
	# Skirt and reboiler.
	ViewUtil.cylinder(self, 0.62, 0.14, Vector3(0, 0.07, 0),
		ViewUtil.flat(Color(0.30, 0.31, 0.33)))
	_reboiler = ViewUtil.cylinder(self, 0.55, 0.9, Vector3(0, 0.6, 0),
		ViewUtil.glow(Color(0.45, 0.24, 0.14), 0.15))
	# Lagged column shell with band joints.
	ViewUtil.cylinder(self, 0.42, 4.9, Vector3(0, 3.5, 0), lagging)
	for i in range(5):
		ViewUtil.cylinder(self, 0.45, 0.06, Vector3(0, 1.3 + i * 1.05, 0), steel)
	# Overhead: vapour line up and over into a condenser drum.
	ViewUtil.cylinder(self, 0.12, 1.0, Vector3(0, 6.35, 0), steel)
	var elbow := ViewUtil.cylinder(self, 0.12, 0.7, Vector3(0.35, 6.8, 0), steel)
	elbow.rotation_degrees = Vector3(0, 0, 90)
	var drum := ViewUtil.cylinder(self, 0.26, 0.9, Vector3(0.78, 6.8, 0), steel)
	drum.rotation_degrees = Vector3(0, 0, 90)
	# The overhead draw-off, tinted by how much is actually going over.
	_overhead = ViewUtil.cylinder(self, 0.07, 0.6, Vector3(0.78, 6.35, 0),
		ViewUtil.glow(Color(0.30, 0.55, 0.80), 0.2))
	# Column furniture: a flanged feed nozzle neck, a reflux return
	# from the condenser drum into the column top, cooling water
	# connections on the drum, a level gauge on it, a relief valve on
	# the column top, a sight glass and a nameplate on the reboiler, and
	# a caged ladder up the north side.
	var dark := ViewUtil.flat(Color(0.20, 0.21, 0.23))
	var bolt_mat := ViewUtil.flat(Color(0.35, 0.36, 0.38))
	var feed := ViewUtil.cylinder(self, 0.06, 0.22, Vector3(-0.53, 2.6, 0), steel)
	feed.rotation_degrees = Vector3(0, 0, 90)
	var feed_flange := ViewUtil.cylinder(self, 0.10, 0.03, Vector3(-0.64, 2.6, 0), steel)
	feed_flange.rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.cylinder(self, 0.04, 0.3, Vector3(0.55, 6.42, 0), steel)
	var reflux := ViewUtil.cylinder(self, 0.04, 0.32, Vector3(0.4, 6.28, 0), steel)
	reflux.rotation_degrees = Vector3(0, 0, 90)
	for cz: float in [-0.22, 0.22]:
		ViewUtil.cylinder(self, 0.035, 0.16, Vector3(0.78, 7.1, cz), steel)
		ViewUtil.cylinder(self, 0.06, 0.02, Vector3(0.78, 7.18, cz), steel)
	ViewUtil.box(self, Vector3(0.04, 0.4, 0.03), Vector3(1.05, 6.8, 0.27), dark)
	ViewUtil.box(self, Vector3(0.025, 0.34, 0.02), Vector3(1.05, 6.8, 0.275), ViewUtil.flat(Color(0.80, 0.88, 0.92, 0.5)))
	ViewUtil.cylinder(self, 0.035, 0.16, Vector3(-0.25, 6.05, 0.25), steel)
	ViewUtil.cylinder(self, 0.06, 0.12, Vector3(-0.25, 6.18, 0.25), ViewUtil.flat(Color(0.78, 0.62, 0.30)))
	ViewUtil.box(self, Vector3(0.16, 0.015, 0.02), Vector3(-0.18, 6.25, 0.25), steel)
	var sight := ViewUtil.cylinder(self, 0.1, 0.05, Vector3(0, 0.7, 0.55), steel)
	sight.rotation_degrees = Vector3(90, 0, 0)
	var glass := ViewUtil.cylinder(self, 0.075, 0.01, Vector3(0, 0.7, 0.58), ViewUtil.flat(Color(0.80, 0.88, 0.92, 0.5)))
	glass.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.22, 0.10, 0.005), Vector3(-0.25, 0.95, 0.553), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	for i in 22:
		ViewUtil.box(self, Vector3(0.36, 0.025, 0.025), Vector3(0, 1.5 + i * 0.25, -0.62), dark)
	for lx: float in [-0.18, 0.18]:
		ViewUtil.box(self, Vector3(0.03, 5.6, 0.03), Vector3(lx, 4.2, -0.62), dark)
	for i in 6:
		var hoop := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.33
		ring.outer_radius = 0.36
		hoop.mesh = ring
		hoop.material_override = dark
		hoop.position = Vector3(0, 3.0 + i * 0.7, -0.62)
		add_child(hoop)
	for i in 8:
		var a := TAU / 8.0 * i
		ViewUtil.cylinder(self, 0.012, 0.03, Vector3(-0.64 + 0.0, 2.6 + cos(a) * 0.08, sin(a) * 0.08), bolt_mat).rotation_degrees = Vector3(0, 0, 90)
	ViewUtil.label(self, still.comp_name, Vector3(0, 7.3, 0))
	_label = ViewUtil.label(self, "", Vector3(0, 7.05, 0))
	_label.font_size = 26
	ViewUtil.interact_body(self, Vector3(1.4, 6.9, 1.4), Vector3(0, 3.45, 0))
	_boil = EquipmentAudio.make(self, "res://audio/boiler_loop.wav",
		Vector3(0, 0.6, 0), -12.0, 0.75)
	_plume = VaporPlume.make(self, Vector3(0.78, 7.15, 0), 0.6)


func _process(_delta: float) -> void:
	# The reboiler glows with the duty it is really being given.
	var duty_frac := clampf(still.boilup_lps / 3.0, 0.0, 1.0)
	var reb := _reboiler.material_override as StandardMaterial3D
	var hot := Color(0.45, 0.24, 0.14).lerp(Color(0.95, 0.45, 0.15), duty_frac)
	reb.albedo_color = hot
	reb.emission = hot
	reb.emission_energy_multiplier = 0.15 + 1.3 * duty_frac
	_boil.set_running(still.boilup_lps > 0.01)

	# Overhead line brightens with real distillate rate.
	var top_frac := clampf(still.distillate_lps / 2.0, 0.0, 1.0)
	var over := _overhead.material_override as StandardMaterial3D
	var cool := Color(0.22, 0.34, 0.46).lerp(Color(0.35, 0.70, 0.95), top_frac)
	over.albedo_color = cool
	over.emission = cool
	_plume.set_strength(top_frac * 0.7)

	if still.distillate_lps > 0.001:
		_label.text = "%.2f L/s over the top" % still.distillate_lps
	elif still.boilup_lps > 0.01:
		_label.text = "boiling, nothing over"
	else:
		_label.text = "cold"


func describe() -> String:
	return "%s — solvent recovery still\n%s · boilup %.2f L/s · distillate %.2f L/s · %.0f L recovered\ncut at %.0f °C, sharpness %.0f %%\noverhead: %s" % [
		still.comp_name, "RUNNING" if still.running else "STOPPED",
		still.boilup_lps, still.distillate_lps, still.recovered_l,
		still.cut_c, still.sharpness * 100.0, still.distillate.stream.describe()]


func use() -> void:
	still.is_on = not still.is_on
	EquipmentAudio.play_once(self, "res://audio/clunk.wav",
		Vector3(0, 1.2, 0.6), -6.0, 1.0)
