class_name LabVesselView
extends BenchView
## Renders a SimLabVessel: a beaker, an Erlenmeyer flask, a sample vial
## or a reagent bottle (a glass bottle for a liquid, a white jar for a
## powder), and what is in it. The liquid stands at its real volume and
## shows its real colour (each coloured species by its concentration, an
## indicator by the pH); undissolved solid settles in a layer, or clouds
## the liquid while the hotplate stirs it; a stir bar spins while it
## stirs; gas coming off shows as bubbles, boiling as bigger bubbles and
## steam at the mouth, each with its sound.

const WALL := 0.0022             # glass thickness
const SETTLED_PACKING := 1.6     # settled solid holds liquid between its grains

var vessel: SimLabVessel
var _liquid: MeshInstance3D
var _liquid_mesh: CylinderMesh
var _liquid_mat: StandardMaterial3D
var _solid: MeshInstance3D
var _solid_mesh: CylinderMesh
var _solid_mat: StandardMaterial3D
var _bar: MeshInstance3D
var _bubbles: GPUParticles3D
var _bubble_box: ParticleProcessMaterial
var _steam: VaporPlume
var _fizz: EquipmentAudio
var _boil: EquipmentAudio
var _shown_level := -1.0
var _shown_solid := -1.0
var _bar_angle := 0.0

## The body's radius at the base and at the top of the body (a flask
## narrows to its neck), and the body's height; a bottle and a vial
## have a shoulder and a neck above.
var _r_base := 0.035
var _r_top := 0.035
var _body_h := 0.09


func _build() -> void:
	vessel = record as SimLabVessel
	var r := vessel.diameter_m / 2.0
	var h := vessel.height_m
	var glass := ViewUtil.flat(Color(0.86, 0.93, 0.96, 0.16))
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var jar := vessel.kind == "bottle" and _stock_is_powder()
	match vessel.kind:
		"beaker":
			_r_base = r
			_r_top = r
			_body_h = h
			_open_cylinder(r, h, glass)
			# The rolled rim and the pouring lip.
			var rim := TorusMesh.new()
			rim.inner_radius = r - 0.001
			rim.outer_radius = r + 0.0025
			var ring := MeshInstance3D.new()
			ring.mesh = rim
			ring.material_override = glass
			ring.position = Vector3(0, h, 0)
			add_child(ring)
			_graduations(r, h * 0.85, 5)
		"flask":
			_r_base = r
			_r_top = r * 0.32
			_body_h = h * 0.72
			var body := CylinderMesh.new()
			body.top_radius = _r_top
			body.bottom_radius = r
			body.height = _body_h
			body.cap_top = false
			var shell := MeshInstance3D.new()
			shell.mesh = body
			shell.material_override = glass
			shell.position = Vector3(0, _body_h / 2.0, 0)
			add_child(shell)
			var neck := CylinderMesh.new()
			neck.top_radius = _r_top
			neck.bottom_radius = _r_top
			neck.height = h - _body_h
			neck.cap_top = false
			neck.cap_bottom = false
			var neck_node := MeshInstance3D.new()
			neck_node.mesh = neck
			neck_node.material_override = glass
			neck_node.position = Vector3(0, _body_h + (h - _body_h) / 2.0, 0)
			add_child(neck_node)
			_graduations(r * 0.9, _body_h * 0.7, 4)
		"vial", "bottle":
			_r_base = r
			_r_top = r
			_body_h = h * 0.72
			var wall := ViewUtil.matte(Color(0.93, 0.93, 0.91)) if jar else glass
			if jar:
				_body_h = h * 0.85
			_open_cylinder(r, _body_h, wall)
			var neck_r := r * (0.85 if jar else 0.45)
			var shoulder := CylinderMesh.new()
			shoulder.top_radius = neck_r
			shoulder.bottom_radius = r
			shoulder.height = h * (0.06 if jar else 0.14)
			shoulder.cap_top = false
			shoulder.cap_bottom = false
			var shoulder_node := MeshInstance3D.new()
			shoulder_node.mesh = shoulder
			shoulder_node.material_override = wall
			shoulder_node.position = Vector3(0, _body_h + shoulder.height / 2.0, 0)
			add_child(shoulder_node)
			var cap_h := h - _body_h - shoulder.height
			var cap_color := Color(0.95, 0.95, 0.94) if jar else Color(0.10, 0.20, 0.45)
			if vessel.kind == "vial":
				cap_color = Color(0.08, 0.08, 0.09)
			ViewUtil.cylinder(self, neck_r + 0.002, cap_h, Vector3(0, h - cap_h / 2.0, 0),
				ViewUtil.matte(cap_color))
			if vessel.kind == "bottle":
				_label_band(r)
	_liquid_mat = StandardMaterial3D.new()
	_liquid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_liquid_mat.roughness = 0.1
	_liquid_mat.metallic_specular = 0.7
	_liquid_mesh = CylinderMesh.new()
	_liquid_mesh.radial_segments = 24
	_liquid_mesh.rings = 1
	_liquid = MeshInstance3D.new()
	_liquid.mesh = _liquid_mesh
	_liquid.material_override = _liquid_mat
	_liquid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_liquid.visible = false
	add_child(_liquid)
	_solid_mat = ViewUtil.matte(Color(0.95, 0.95, 0.94))
	_solid_mesh = CylinderMesh.new()
	_solid_mesh.radial_segments = 20
	_solid_mesh.rings = 1
	_solid = MeshInstance3D.new()
	_solid.mesh = _solid_mesh
	_solid.material_override = _solid_mat
	_solid.visible = false
	add_child(_solid)
	if vessel.kind != "bottle":
		var bar := CapsuleMesh.new()
		bar.radius = 0.004
		bar.height = minf(0.025, r * 1.2)
		_bar = MeshInstance3D.new()
		_bar.mesh = bar
		_bar.material_override = ViewUtil.matte(Color(0.97, 0.97, 0.96))
		_bar.rotation.z = PI / 2.0
		_bar.position = Vector3(0, WALL + 0.004, 0)
		_bar.visible = false
		add_child(_bar)
	_bubble_box = ParticleProcessMaterial.new()
	_bubble_box.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_bubble_box.emission_box_extents = Vector3(r * 0.55, 0.002, r * 0.55)
	_bubble_box.direction = Vector3.UP
	_bubble_box.spread = 8.0
	_bubble_box.initial_velocity_min = 0.03
	_bubble_box.initial_velocity_max = 0.06
	_bubble_box.gravity = Vector3(0, 0.25, 0)
	_bubble_box.scale_min = 0.6
	_bubble_box.scale_max = 1.4
	_bubbles = GPUParticles3D.new()
	_bubbles.process_material = _bubble_box
	var bead := SphereMesh.new()
	bead.radius = 0.0015
	bead.height = 0.003
	bead.radial_segments = 6
	bead.rings = 3
	var bead_mat := ViewUtil.flat(Color(0.95, 0.98, 1.0, 0.55))
	bead.material = bead_mat
	_bubbles.draw_pass_1 = bead
	_bubbles.amount = 40
	_bubbles.lifetime = 0.6
	_bubbles.emitting = false
	_bubbles.position = Vector3(0, WALL + 0.004, 0)
	_bubbles.visibility_aabb = AABB(Vector3(-r, 0, -r), Vector3(2 * r, h, 2 * r))
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bubbles)
	_steam = VaporPlume.make(self, Vector3(0, h + 0.01, 0), 0.15)
	_fizz = EquipmentAudio.make(self, "res://audio/gurgle_loop.wav", Vector3(0, h * 0.5, 0), -16.0, 1.7)
	_boil = EquipmentAudio.make(self, "res://audio/boiler_loop.wav", Vector3(0, h * 0.5, 0), -18.0, 1.9)
	ViewUtil.label(self, vessel.comp_name, Vector3(0, h + 0.08, 0)).font_size = 22
	ViewUtil.interact_cylinder(self, r + 0.01, h + 0.01, Vector3(0, (h + 0.01) / 2.0, 0))
	_shown_level = -1.0
	_shown_solid = -1.0


func radius() -> float:
	return vessel.diameter_m / 2.0 if vessel != null else 0.05


func _stock_is_powder() -> bool:
	if vessel.stock == "":
		return false
	var grams: Dictionary = ChemLibrary.stock(vessel.stock).get("grams", {})
	for key: String in grams:
		if ChemLibrary.phase[ChemLibrary.index_of(key)] != ChemLibrary.Phase.SOLID:
			return false
	return true


func _open_cylinder(r: float, h: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.cap_top = false
	mesh.radial_segments = 28
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = Vector3(0, h / 2.0, 0)
	add_child(node)


## White printed graduations up one side, the way a beaker reads.
func _graduations(r: float, top: float, count: int) -> void:
	var ink := ViewUtil.matte(Color(0.95, 0.95, 0.95))
	for i in count:
		var y := top * float(i + 1) / count
		var mark := ViewUtil.box(self, Vector3(0.012 if i % 2 == 1 else 0.007, 0.0012, 0.0008),
			Vector3(0, y, -r - 0.0004), ink)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A reagent bottle's paper label, printed with what the hold packed in it.
func _label_band(r: float) -> void:
	var band_h := _body_h * 0.5
	var paper := ViewUtil.matte(Color(0.96, 0.95, 0.90))
	var band := CylinderMesh.new()
	band.top_radius = r + 0.0012
	band.bottom_radius = r + 0.0012
	band.height = band_h
	band.cap_top = false
	band.cap_bottom = false
	var node := MeshInstance3D.new()
	node.mesh = band
	node.material_override = paper
	node.position = Vector3(0, _body_h * 0.45, 0)
	add_child(node)
	var text := Label3D.new()
	text.text = vessel.label_text()
	text.font_size = 32
	text.pixel_size = 0.00028
	text.modulate = Color(0.1, 0.1, 0.12)
	text.outline_size = 0
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.width = r * 1.5 / text.pixel_size
	text.position = Vector3(0, _body_h * 0.45, r + 0.003)
	add_child(text)
	var stripe := ViewUtil.matte(Color(0.75, 0.15, 0.12) if _hazardous() else Color(0.20, 0.35, 0.60))
	var bar := CylinderMesh.new()
	bar.top_radius = r + 0.0014
	bar.bottom_radius = r + 0.0014
	bar.height = 0.006
	bar.cap_top = false
	bar.cap_bottom = false
	for y: float in [_body_h * 0.45 + band_h / 2.0 - 0.006, _body_h * 0.45 - band_h / 2.0 + 0.006]:
		var s := MeshInstance3D.new()
		s.mesh = bar
		s.material_override = stripe
		s.position = Vector3(0, y, 0)
		add_child(s)


## A bottle of something corrosive, an oxidizer or flammable wears red.
func _hazardous() -> bool:
	var grams: Dictionary = ChemLibrary.stock(vessel.stock).get("grams", {})
	for key: String in grams:
		if ChemLibrary.hazards[ChemLibrary.index_of(key)] != "":
			return true
	return false


## The radius of the inside at height y above the base.
func _radius_at(y: float) -> float:
	if y >= _body_h:
		return _r_top - WALL
	return lerpf(_r_base, _r_top, y / _body_h) - WALL


## The height that holds this many millilitres: the body's volume up to
## a height, found by halving (a flask narrows as it fills).
func _height_for(ml: float) -> float:
	var litres := ml / 1e6
	if absf(_r_base - _r_top) < 1e-6:
		var area := PI * pow(_r_base - WALL, 2.0)
		return litres / area
	var lo := 0.0
	var hi := vessel.height_m
	for _k in 30:
		var mid := 0.5 * (lo + hi)
		if _volume_below(mid) < litres:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


func _volume_below(y: float) -> float:
	var y_body := minf(y, _body_h)
	var ra := _r_base - WALL
	var rb := _radius_at(y_body)
	var v := PI * y_body / 3.0 * (ra * ra + ra * rb + rb * rb)
	if y > _body_h:
		v += PI * pow(_r_top - WALL, 2.0) * (y - _body_h)
	return v


func _process(delta: float) -> void:
	if vessel == null:
		return
	var m := vessel.contents
	var liquid_ml := m.liquid_ml()
	var solid_ml := m.solid_ml()
	var stirring := vessel.mix > SimMixture.UNSTIRRED + 0.01
	var settled := 0.0 if stirring else solid_ml * SETTLED_PACKING
	var solid_top := _height_for(settled) if settled > 0.0 else 0.0
	var level := _height_for(liquid_ml + solid_ml)
	level = maxf(level, solid_top)
	if absf(level - _shown_level) > 0.0003 or absf(solid_top - _shown_solid) > 0.0003:
		_shown_level = level
		_shown_solid = solid_top
		_shape_fill(level, solid_top)
	# The liquid's colour, clouded by solid the stirrer keeps up.
	var tint := m.liquid_color()
	var base := Color(0.88, 0.94, 0.98)
	var c := base.lerp(Color(tint.r, tint.g, tint.b), tint.a)
	var alpha := 0.22 + 0.6 * tint.a
	if stirring and solid_ml > 0.0 and liquid_ml > 0.0:
		var cloud := clampf(solid_ml / liquid_ml * 40.0, 0.0, 0.9)
		c = c.lerp(m.solid_color(), cloud)
		alpha = lerpf(alpha, 0.95, cloud)
	c.a = alpha
	_liquid_mat.albedo_color = c
	_solid_mat.albedo_color = m.solid_color()
	if _bar != null:
		_bar.visible = stirring and liquid_ml > 0.0
		if _bar.visible:
			_bar_angle = wrapf(_bar_angle + delta * 25.0 * vessel.mix, 0.0, TAU)
			_bar.rotation = Vector3(0, _bar_angle, PI / 2.0)
	# Bubbles and steam from what the mixture is really doing.
	var gas := vessel.gas_ml_s
	var fizzing := gas > 0.05 and liquid_ml > 0.5
	var boiling := m.boiling and liquid_ml > 0.5
	_bubbles.emitting = fizzing or boiling
	if _bubbles.emitting:
		_bubbles.amount_ratio = clampf(maxf(gas / 5.0, 1.0 if boiling else 0.0), 0.15, 1.0)
		_bubbles.lifetime = maxf(level / 0.07, 0.1)
		_bubble_box.scale_max = 3.0 if boiling else 1.4
	_steam.set_strength(clampf(vessel.boil_g_s * 4.0, 0.0, 1.0) if boiling else 0.0)
	_fizz.set_running(fizzing)
	_boil.set_running(boiling)


func _shape_fill(level: float, solid_top: float) -> void:
	_liquid.visible = level > solid_top + 0.0005
	if _liquid.visible:
		var y0 := WALL + solid_top
		var y1 := WALL + level
		_liquid_mesh.bottom_radius = _radius_at(y0)
		_liquid_mesh.top_radius = _radius_at(y1)
		_liquid_mesh.height = y1 - y0
		_liquid.position = Vector3(0, (y0 + y1) / 2.0, 0)
	_solid.visible = solid_top > 0.0005
	if _solid.visible:
		_solid_mesh.bottom_radius = _radius_at(WALL)
		_solid_mesh.top_radius = _radius_at(WALL + solid_top)
		_solid_mesh.height = solid_top
		_solid.position = Vector3(0, WALL + solid_top / 2.0, 0)


## What the eye can tell: how full, what it looks like, whether it is
## fizzing or boiling. Temperature, pH and weight take the instruments.
func describe() -> String:
	var m := vessel.contents
	var lines: Array[String] = []
	var title := "%s — %s, %d mL" % [vessel.comp_name, _kind_name(), int(vessel.capacity_ml)]
	lines.append(title)
	if vessel.stock != "":
		lines.append("label: " + vessel.label_text())
	lines.append(look(m))
	lines.append("double-click to pour · right-hold to carry")
	return "\n".join(lines)


func _kind_name() -> String:
	match vessel.kind:
		"beaker":
			return "beaker"
		"flask":
			return "Erlenmeyer flask"
		"vial":
			return "sample vial"
	return "jar" if _stock_is_powder() else "reagent bottle"


## A plain description of what a mixture looks like, read off its state.
static func look(m: SimMixture) -> String:
	var liquid_ml := m.liquid_ml()
	var solid_ml := m.solid_ml()
	if liquid_ml < 0.05 and solid_ml < 0.05:
		return "empty"
	var parts: Array[String] = []
	if liquid_ml >= 0.05:
		var tint := m.liquid_color()
		var colour := "clear, colourless"
		if tint.a > 0.08:
			colour = "clear, " + _colour_word(tint)
		parts.append("about %d mL of %s liquid" % [_nearest_graduation(liquid_ml), colour])
	if solid_ml >= 0.05:
		var where := "settled at the bottom" if liquid_ml >= 0.05 else "dry"
		parts.append("%s solid %s" % [_colour_word(m.solid_color()), where])
	if m.boiling:
		parts.append("boiling")
	elif m.gas_mol_s * SimLabVessel.GAS_ML_PER_MOL > 0.05:
		parts.append("fizzing")
	return " · ".join(parts)


static func _nearest_graduation(ml: float) -> int:
	if ml < 20.0:
		return maxi(int(round(ml)), 1)
	if ml < 200.0:
		return int(round(ml / 5.0) * 5.0)
	return int(round(ml / 10.0) * 10.0)


static func _colour_word(c: Color) -> String:
	if c.s < 0.15:
		return "white" if c.v > 0.8 else ("grey" if c.v > 0.35 else "black")
	var hue := c.h * 360.0
	if hue < 20.0 or hue >= 330.0:
		return "pink" if c.v > 0.7 and c.s < 0.8 else "red"
	if hue < 45.0:
		return "orange"
	if hue < 70.0:
		return "yellow"
	if hue < 160.0:
		return "green"
	if hue < 250.0:
		return "pale blue" if c.s < 0.6 else "blue"
	return "purple" if hue < 300.0 else "pink"
