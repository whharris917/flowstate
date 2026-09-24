class_name PipeView
## A routed multi-segment run — process pipe, signal conduit, cable
## tray, or a loose cable lying on the floor (style "cable", drawn as
## one smooth tube) — rendered as oriented segments with fittings, glowing when a
## live wire backs it. Render only: a wire run's truth is the kernel
## wire it visualizes; an infrastructure run is support you laid down.
## Segments carry thin colliders (layer 8 for wire runs so pipe never
## supports pipe; layer 1 for infrastructure so trays and racks DO
## support what's routed along them). set_supports() draws the clamp
## brackets the support rule found, or paints the run alarm-red when
## an unsupported span is over the limit.
extends Node3D

const ALARM := Color(0.9, 0.2, 0.15)

var config_cb: Callable = Callable()
var service_label := ""
var fitting := "flange"   # "flange", "clamp" (sanitary tri-clamp) or "tube" (compression)
## The bore of the fittings the line meets, set by the plant before
## setup; where it differs from the line's own, each end spool is a
## concentric reducer tapering between the two.
var end_radius_a := -1.0   # the bore of the fitting at the line's start
var end_radius_b := -1.0   # and at its end
var _fitting_nodes: Array[Node3D] = []
## Set before setup to leave parts of the run unclickable: called with
## a point, false where no collider goes (a cable inside a sleeve, so
## a click there finds the sleeve).
var collide_where: Callable = Callable()

var _getter: Callable
var _desc: String
var _radius := 0.07
var _style := "pipe"
var _path: Array[Vector3] = []
var _hot: StandardMaterial3D
var _cold: StandardMaterial3D
var _bad: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _brackets: Array[Node3D] = []
var _label_nodes: Array[Label3D] = []
var _collider_rids: Array[RID] = []
var _state := 0  # 0 cold, 1 pressurised but still, 2 flowing
var _unsupported := false
var _pressure_getter: Callable = Callable()
var _charged: StandardMaterial3D


func radius() -> float:
	return _radius


func style() -> String:
	return _style


## The drawn path, local to the parent (the plant).
func path() -> Array[Vector3]:
	return _path


func setup(path: Array[Vector3], getter: Callable, color: Color, radius: float,
		desc: String = "", style: String = "pipe", collider_layer: int = 8) -> void:
	_getter = getter
	_desc = desc
	_radius = radius
	_style = style
	_path = path
	_set_service_color(color)
	_bad = ViewUtil.glow(ALARM, 1.3)
	_bad.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Corners are swept bends: each straight is shortened by the bend
	# radius at a corner that bends, and a quarter-torus elbow fills the
	# gap. A corner too tight for a bend keeps a ball joint.
	# Colliders once; the geometry in _build_body, which set_fitting
	# runs again, since the flanges are baked into the body.
	# A cable's curve has a point every few centimetres round a bend:
	# one collider spans several, named by the first.
	if collider_layer > 0:
		var stride := 6 if style == "cable" else 1
		var i := 0
		while i < path.size() - 1:
			if not _clickable(path, i):
				i += 1
				continue
			var j := i + 1
			# A piece is a chord: kept short, so it stays on a bend.
			while j < path.size() - 1 and j - i < stride and _clickable(path, j) 					and path[i].distance_to(path[j + 1]) < 0.5:
				j += 1
			if path[i].distance_to(path[j]) >= 0.005:
				_segment_collider(path[i], path[j], maxf(radius * 2.5, 0.12), collider_layer, i)
			i = j
	_build_body()


## Is the segment from path[i] clickable: nowhere collide_where
## refuses along it.
func _clickable(path: Array[Vector3], i: int) -> bool:
	if not collide_where.is_valid():
		return true
	var steps := maxi(1, ceili(path[i].distance_to(path[i + 1]) / 0.1))
	for s in range(steps + 1):
		if not bool(collide_where.call(path[i].lerp(path[i + 1], float(s) / steps))):
			return false
	return true


## The run's geometry — straights, bends, joints, end fittings — then
## merged: one mesh for the body with its flanges, one or two for the
## clamp parts.
func _build_body() -> void:
	var path := _path
	if _style == "cable":
		_build_cable()
		return
	# Tubing bends round a wide radius, since it is bent, not fitted.
	var bend := _radius * (4.0 if fitting == "tube" else 1.5)
	# A bend of any angle: each straight gives up the bend's tangent
	# length at its end, and the elbow sweeps the angle between them.
	# The tangents are fitted to the legs first, so a short leg gets a
	# tighter bend rather than a ball joint, which reads as bulbous.
	var tangents: Array[float] = []
	if _style != "tray":
		tangents = _tangents(path, bend)
	for i in range(path.size() - 1):
		var from := path[i]
		var to := path[i + 1]
		if from.distance_to(to) < 0.005:
			continue
		var direction := (to - from).normalized()
		var seg_from := from
		var seg_to := to
		var t_from := float(tangents[i]) if not tangents.is_empty() else -1.0
		var t_to := float(tangents[i + 1]) if not tangents.is_empty() else -1.0
		if t_from > 0.0:
			seg_from = from + direction * t_from
		if t_to > 0.0:
			seg_to = to - direction * t_to
		if seg_from.distance_to(seg_to) > 0.005:
			var seg_len := seg_from.distance_to(seg_to)
			var end_r := end_radius_a if i == 0 else end_radius_b
			var taper := _style == "pipe" and end_r > 0.0 and absf(end_r - _radius) > 0.001 \
				and (i == 0 or i == path.size() - 2)
			if taper:
				# The reducer: about a diameter and a half of the larger
				# bore, within this spool, the rest of the spool at the
				# line's own bore.
				var length := clampf(3.0 * maxf(_radius, end_r), 0.2, seg_len * 0.8)
				if i == 0:
					var mid := seg_from + direction * length
					add_child(_collected(reducer_node(seg_from, mid, end_r, _radius, _cold)))
					if mid.distance_to(seg_to) > 0.005:
						add_child(_collected(segment_node(mid, seg_to, _radius, _style, _cold)))
				else:
					var mid := seg_to - direction * length
					if seg_from.distance_to(mid) > 0.005:
						add_child(_collected(segment_node(seg_from, mid, _radius, _style, _cold)))
					add_child(_collected(reducer_node(mid, seg_to, _radius, end_r, _cold)))
			else:
				var seg := segment_node(seg_from, seg_to, _radius, _style, _cold)
				add_child(seg)
				_collect_meshes(seg)
		if i > 0:
			var joint: Node3D = null
			if t_from > 0.0:
				var corner_bend := t_from / tan(_turn_angle(path, i) / 2.0)
				joint = elbow_node(from, (from - path[i - 1]).normalized(), direction, _radius, corner_bend, _cold)
			if joint == null and _turns_at(path, i):
				joint = joint_node(from, _radius, _style, _cold)
			if joint != null:
				add_child(joint)
				_collect_meshes(joint)
	if _style == "pipe" and path.size() >= 2:
		_end_fitting(path[0], path[1], end_radius_a)
		_end_fitting(path[path.size() - 1], path[path.size() - 2], end_radius_b)
	_merge_body()
	_merge_fittings()


## A loose cable: one tube along its curve. A sleeve has an end cap at
## each end.
func _build_cable() -> void:
	var tube := CableDrape.tube_mesh(_path, _radius)
	if tube == null:
		return
	var inst := MeshInstance3D.new()
	inst.mesh = tube
	inst.material_override = _cold
	add_child(inst)
	_meshes.append(inst)
	if not has_meta("sleeve"):
		return   # a cable's gland is its terminal's
	var gland_mat := ViewUtil.flat(Color(0.16, 0.16, 0.18))
	var n := _path.size()
	for end: Array in [[_path[0], _path[1]], [_path[n - 1], _path[n - 2]]]:
		var direction := ((end[1] as Vector3) - (end[0] as Vector3)).normalized()
		var gland := _fitting_disc(_radius * 2.0, 0.03, gland_mat)
		gland.position = (end[0] as Vector3) + direction * 0.015
		gland.basis = _segment_basis(direction) * Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
	_merge_fittings()


## One mesh for the run's body — every straight, bend and joint shares
## the service material and is repainted as one — and one or two for
## the end fittings.
func _merge_body() -> void:
	var body: Array = []
	for inst in _meshes:
		if not _fitting_nodes.has(inst):
			body.append(inst)
	if body.size() < 2:
		return
	var merged := MeshMerge.merge_list(self, body, _cold)
	if merged == null:
		return
	for inst in body:
		_meshes.erase(inst)
	_meshes.append(merged)


func _merge_fittings() -> void:
	if _fitting_nodes.size() < 2:
		return
	var merged := MeshMerge.merge_group(self, _fitting_nodes)
	for old in _fitting_nodes:
		_meshes.erase(old)  # flange discs were repainted with the body
	_fitting_nodes.clear()
	for inst in merged:
		_fitting_nodes.append(inst)
		if inst.material_override == _cold:
			_meshes.append(inst)


## Where the run terminates, pipes bolt on, they don't just touch: a
## flange disc, or on a sanitary line a tri-clamp — two ferrules and
## the clamp band over them, the fitting a pharmaceutical plant uses
## wherever a line has to come apart to be cleaned.
func _end_fitting(at: Vector3, toward: Vector3, end_r: float = -1.0) -> void:
	_end_now = end_r
	var direction := (toward - at).normalized()
	var basis := _segment_basis(direction) * Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
	if fitting == "tube" and not SmallBoreUtil.is_tube(_end_r()):
		# A tube landing on a flanged nozzle ends in a flange behind its
		# reducer, never in a nut the size of the nozzle.
		var disc := _fitting_disc(_end_r() * 1.8, 0.045, _cold)
		disc.position = at + direction * 0.03
		disc.basis = basis
		_fitting_nodes.erase(disc)
		_meshes.append(disc)
		return
	if fitting == "tube":
		# A compression fitting: the hex nut over the tube end, a short
		# ferrule showing behind it. Sized to the tube.
		var nut_mat := ViewUtil.flat(Color(0.62, 0.66, 0.70))
		var nut_r := maxf(_radius * 2.2, 0.014)
		var nut_h := maxf(_radius * 2.4, 0.016)
		var nut := _fitting_disc(nut_r, nut_h, nut_mat)
		(nut.mesh as CylinderMesh).radial_segments = 6
		nut.position = at + direction * (nut_h / 2.0)
		nut.basis = basis
		var ferrule := _fitting_disc(nut_r * 0.6, 0.008, nut_mat)
		ferrule.position = at + direction * (nut_h + 0.004)
		ferrule.basis = basis
		return
	if fitting == "clamp":
		var bright := ViewUtil.flat(Color(0.80, 0.82, 0.85))
		var band := ViewUtil.flat(Color(0.30, 0.31, 0.34))
		for offset: float in [0.02, 0.075]:
			var ferrule := _fitting_disc(_end_r() * 1.45, 0.02, bright)
			ferrule.position = at + direction * offset
			ferrule.basis = basis
		var clamp := _fitting_disc(_end_r() * 1.75, 0.05, band)
		clamp.position = at + direction * 0.0475
		clamp.basis = basis
		# The wing nut that closes the band, on top.
		var nut := MeshInstance3D.new()
		var nut_mesh := BoxMesh.new()
		nut_mesh.size = Vector3(0.02, _end_r() * 0.9, 0.05)
		nut.mesh = nut_mesh
		nut.material_override = band
		nut.position = at + direction * 0.0475 + Vector3(0, _end_r() * 1.75 + _end_r() * 0.4, 0)
		add_child(nut)
		_fitting_nodes.append(nut)
		return
	var disc := _fitting_disc(_end_r() * 1.8, 0.045, _cold)
	disc.position = at + direction * 0.03
	disc.basis = basis
	_fitting_nodes.erase(disc)  # a flange is body: repainted with it, baked with it
	_meshes.append(disc)


func _fitting_disc(radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	disc.mesh = mesh
	disc.material_override = mat
	add_child(disc)
	_fitting_nodes.append(disc)
	return disc


## Swap the end fittings: "flange", "clamp" or "tube". The run itself
## is the same; only what it terminates in changes — except tubing,
## which is plastic and bends wide, so the body is drawn again too.
func set_fitting(style: String) -> void:
	if style == fitting:
		return
	fitting = style
	_set_service_color(service_color())
	# The flanges are baked into the body, so the body is built again.
	for node in _fitting_nodes:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
	_fitting_nodes.clear()
	for inst in _meshes:
		if inst.get_parent() != null:
			inst.get_parent().remove_child(inst)
		inst.queue_free()
	_meshes.clear()
	_build_body()
	_repaint()


func service_color() -> Color:
	return _hot.albedo_color


func _set_service_color(color: Color) -> void:
	_hot = ViewUtil.glow(color, 1.1)
	_charged = ViewUtil.glow(color, 0.35)
	if fitting == "tube" and _style == "pipe":
		# Nylon tubing: it keeps its colour, satin rather than steel.
		_cold = ViewUtil.flat(color.lerp(Color(0.55, 0.55, 0.55), 0.25))
		_cold.roughness = 0.45
		_cold.metallic = 0.0
	else:
		_cold = ViewUtil.flat(color.lerp(Color(0.35, 0.35, 0.37), 0.55)) if _style == "pipe" \
			else ViewUtil.flat(color)
	# Two-sided: the swept elbows are built by hand and a closed tube
	# shows no back faces anyway.
	for mat: StandardMaterial3D in [_hot, _charged, _cold]:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Repaint the run in a service color and hang line labels along it.
func apply_service(color: Color, label_text: String) -> void:
	_set_service_color(color)
	service_label = label_text
	_repaint()
	for old in _label_nodes:
		old.queue_free()
	_label_nodes.clear()
	if label_text == "":
		return
	var placed := false
	for i in range(_path.size() - 1):
		if _path[i].distance_to(_path[i + 1]) < 2.5:
			continue
		_label_nodes.append(_line_label(label_text, (_path[i] + _path[i + 1]) / 2.0))
		placed = true
	if not placed and _path.size() >= 2:
		_label_nodes.append(_line_label(label_text, _path[_path.size() / 2]))


func _line_label(text: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at + Vector3(0, _radius + 0.22, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.pixel_size = 0.0035
	label.outline_size = 8
	label.modulate = Color(0.95, 0.95, 0.90)
	label.visibility_range_end = 30.0  # unreadable further off, and each label is a draw
	# Floating text shows only for the run under the crosshair.
	label.visible = false
	label.set_meta("floating", true)
	add_child(label)
	return label


func use() -> void:
	if config_cb.is_valid():
		config_cb.call(self)


## One oriented segment: a cylinder for pipe/conduit, a channel with
## side rails for cable tray. Static so route previews can share it.
static func segment_node(from: Vector3, to: Vector3, radius: float,
		style: String, mat: StandardMaterial3D) -> Node3D:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var root := Node3D.new()
	root.position = (from + to) / 2.0
	root.basis = _segment_basis(direction)
	if style == "tray":
		# The floor and two side rails, in proportion to the width.
		var width := radius * 2.0
		var floor_t := tray_floor(radius) * 2.0
		var rail_t := minf(0.04, width * 0.12)
		var rail_h := clampf(width * 0.4, 0.06, 0.11)
		var base := MeshInstance3D.new()
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(width, floor_t, length)
		base.mesh = base_mesh
		base.material_override = mat
		root.add_child(base)
		for side: float in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(rail_t, rail_h, length)
			rail.mesh = rail_mesh
			rail.material_override = mat
			rail.position = Vector3(side * (width / 2.0 - rail_t / 2.0), rail_h / 2.0 - floor_t * 0.1, 0)
			root.add_child(rail)
	else:
		var inst := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		mesh.radial_segments = 16  # a pipe a few centimetres across needs no 64 sides
		mesh.rings = 1
		inst.mesh = mesh
		inst.material_override = mat
		# Cylinder axis is Y; map it onto the segment direction (-Z of
		# the looking_at basis).
		inst.basis = Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
		root.add_child(inst)
	return root


## How far a tray's floor stands above its centreline: half its
## thickness.
static func tray_floor(radius: float) -> float:
	return clampf(radius * 0.125, 0.008, 0.025)


func _collected(node: Node3D) -> Node3D:
	_collect_meshes(node)
	return node


## A concentric reducer: a frustum from `r_from` at `from` to `r_to`
## at `to`, oriented like a straight.
static func reducer_node(from: Vector3, to: Vector3, r_from: float, r_to: float,
		mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	root.position = (from + to) / 2.0
	root.basis = _segment_basis((to - from).normalized())
	var inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_to        # the cylinder's top lies at `to` once turned onto the segment
	mesh.bottom_radius = r_from
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 16
	mesh.rings = 1
	inst.mesh = mesh
	inst.material_override = mat
	inst.basis = Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
	root.add_child(inst)
	return root


## The bore at the fitting being drawn: the nozzle's, or the line's own.
var _end_now := -1.0


func _end_r() -> float:
	return _end_now if _end_now > 0.0 else _radius


## Does the path change direction at point k at all? A corner that
## does not is a leftover of the lay and gets no fitting.
static func _turns_at(path: Array[Vector3], k: int) -> bool:
	if k <= 0 or k >= path.size() - 1:
		return false
	var before := (path[k] - path[k - 1]).normalized()
	var after := (path[k + 1] - path[k]).normalized()
	return before.dot(after) < 0.999


## The angle the path turns through at point k.
static func _turn_angle(path: Array[Vector3], k: int) -> float:
	var before := (path[k] - path[k - 1]).normalized()
	var after := (path[k + 1] - path[k]).normalized()
	return acos(clampf(before.dot(after), -1.0, 1.0))


## The tangent length of the swept bend at every corner — how much of
## each straight its elbow takes — fitted to the legs: where two bends
## share a leg shorter than both their tangents, both tighten to fit,
## and a bend that would have to tighten below a short-radius elbow
## (its centreline radius under the pipe's own radius) keeps a ball
## joint instead. -1 marks a corner with no elbow: a path end, no
## turn, a hairpin past 150 degrees, or one too tight to sweep.
static func _tangents(path: Array[Vector3], bend: float) -> Array[float]:
	var n := path.size()
	var out: Array[float] = []
	out.resize(n)
	var half_tan: Array[float] = []
	half_tan.resize(n)
	for k in n:
		out[k] = -1.0
		half_tan[k] = 0.0
		if k <= 0 or k >= n - 1 or not _turns_at(path, k):
			continue
		var theta := _turn_angle(path, k)
		if theta > deg_to_rad(150.0):
			continue
		half_tan[k] = tan(theta / 2.0)
		out[k] = bend * half_tan[k]
	# Fit: a leg carries the tangents of both its corners. A corner that
	# would tighten past the floor becomes a ball, and the fit is run
	# again without it, so its leg's slack goes to the other end.
	var floor_bend := bend / 1.5   # the pipe's own radius: as tight as an elbow goes
	for pass_ in 3:
		for k in n:
			if half_tan[k] > 0.0:
				out[k] = bend * half_tan[k]
		for i in n - 1:
			var length := path[i].distance_to(path[i + 1])
			var need := maxf(out[i], 0.0) + maxf(out[i + 1], 0.0)
			if need <= length or need <= 0.0:
				continue
			var scale := length / need
			for k in [i, i + 1]:
				if out[k] > 0.0:
					out[k] *= scale
		var demoted := false
		for k in n:
			if out[k] > 0.0 and out[k] / half_tan[k] < floor_bend - 1e-4:
				out[k] = -1.0
				half_tan[k] = 0.0
				demoted = true
		if not demoted:
			break
	return out


## A swept bend of any angle: a torus section of the pipe's radius
## round the corner, tangent to both straights, its centre on the
## corner's bisector. Built once per corner with SurfaceTool; the
## tube's normals are set explicitly and the pipe materials are
## two-sided, so the winding need not be argued about.
static func elbow_node(at: Vector3, dir_in: Vector3, dir_out: Vector3, radius: float,
		bend: float, mat: Material) -> MeshInstance3D:
	var normal := dir_in.cross(dir_out)
	if normal.length() < 1e-4:
		return null
	normal = normal.normalized()
	var theta := acos(clampf(dir_in.dot(dir_out), -1.0, 1.0))
	var tangent_len := bend * tan(theta / 2.0)
	var center := at + (dir_out - dir_in).normalized() * (bend / cos(theta / 2.0))
	var start := at - dir_in * tangent_len
	var arc_steps := maxi(2, ceili(8.0 * theta / (PI / 2.0)))
	var ring := 12
	var rings: Array = []
	for s in arc_steps + 1:
		var swept := theta * s / arc_steps
		var p := center + (start - center).rotated(normal, swept)
		var tangent := dir_in.rotated(normal, swept)
		var n2 := tangent.cross(normal).normalized()
		var verts: Array[Vector3] = []
		var norms: Array[Vector3] = []
		for j in ring:
			var phi := TAU * j / ring
			var nrm := (normal * cos(phi) + n2 * sin(phi)).normalized()
			verts.append(p + nrm * radius)
			norms.append(nrm)
		rings.append([verts, norms, swept / theta])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in arc_steps:
		var r0: Array = rings[s]
		var r1: Array = rings[s + 1]
		for j in ring:
			var j2 := (j + 1) % ring
			var quad := [[r0, j], [r1, j], [r1, j2], [r0, j2]]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for idx: int in tri:
					var ringref: Array = quad[idx][0]
					var jj: int = quad[idx][1]
					st.set_normal((ringref[1] as Array[Vector3])[jj])
					st.set_uv(Vector2(float(jj) / ring, float(ringref[2])))
					st.add_vertex((ringref[0] as Array[Vector3])[jj])
	st.index()  # indexed like the primitives it is merged with, or the merge drops it
	st.generate_tangents()
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = mat
	return inst


static func joint_node(at: Vector3, radius: float, style: String,
		mat: StandardMaterial3D) -> Node3D:
	if style == "tray":
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(radius * 2.0, 0.11, radius * 2.0)
		box.mesh = mesh
		box.material_override = mat
		box.position = at
		return box
	var joint := MeshInstance3D.new()
	var elbow := SphereMesh.new()
	# The pipe's own radius: a ball no wider than the pipe fills the
	# corner without a bulge.
	elbow.radius = radius * 1.02
	elbow.height = radius * 2.04
	joint.mesh = elbow
	joint.material_override = mat
	joint.position = at
	return joint


static func _segment_basis(direction: Vector3) -> Basis:
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(direction, up)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)


## Thin box collider along one segment: the interact ray sees it
## (describe / X removes the run); on layer 1 it is also real support.
func _segment_collider(from: Vector3, to: Vector3, thickness: float, layer: int, leg: int = -1) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta("run", self)  # the router routes round equipment, never round runs
	body.set_meta("leg", leg)   # which straight of the path this is: selection is per leg
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var delta := to - from
	# Along the segment, whatever its bearing: an axis-aligned box round
	# a diagonal would cover the whole floor between its ends.
	box.size = Vector3(thickness, thickness, maxf(delta.length(), thickness))
	shape.shape = box
	body.add_child(shape)
	body.position = (from + to) / 2.0
	body.basis = _segment_basis(delta.normalized())
	body.set_meta("view", self)
	add_child(body)
	_collider_rids.append(body.get_rid())


## This run's own collider RIDs — excluded when it validates itself.
func collider_rids() -> Array[RID]:
	return _collider_rids


## Redraw the clamp hardware from a fresh support evaluation. Points
## are local to this node's parent (the plant).
func set_supports(brackets: Array, unsupported: bool) -> void:
	for old in _brackets:
		old.queue_free()
	_brackets.clear()
	_unsupported = unsupported
	_repaint()
	var mat := ViewUtil.flat(Color(0.22, 0.23, 0.26))
	for bracket: Dictionary in brackets:
		var from: Vector3 = bracket["from"]
		var to: Vector3 = bracket["to"]
		var length := from.distance_to(to)
		if length < 0.02:
			continue
		# A stand is a post from the floor with a base plate and a
		# saddle under the run; a bracket is a clamp strut.
		var stand := bool(bracket.get("stand", false))
		var strut := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		var scale := clampf(_radius / 0.07, 0.12, 1.5)   # hardware sized to the line
		mesh.top_radius = (0.045 if stand else 0.03) * scale
		mesh.bottom_radius = mesh.top_radius
		mesh.height = length
		strut.mesh = mesh
		strut.material_override = mat
		add_child(strut)
		strut.position = (from + to) / 2.0
		var direction := (to - from).normalized()
		strut.basis = _segment_basis(direction) * Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
		_brackets.append(strut)
		var foot := MeshInstance3D.new()
		var pad := BoxMesh.new()
		pad.size = (Vector3(0.26, 0.02, 0.26) if stand else Vector3(0.12, 0.03, 0.12)) * clampf(_radius / 0.07, 0.2, 1.5)
		foot.mesh = pad
		foot.material_override = mat
		add_child(foot)
		foot.position = to
		if stand:
			var saddle := MeshInstance3D.new()
			var saddle_mesh := BoxMesh.new()
			saddle_mesh.size = Vector3(0.16, 0.05, 0.12) * clampf(_radius / 0.07, 0.2, 1.5)
			saddle.mesh = saddle_mesh
			saddle.material_override = mat
			add_child(saddle)
			saddle.position = from - Vector3(0, radius() + 0.02, 0)
			_brackets.append(saddle)
		if absf(direction.y) < 0.5:  # side-anchored: stand the pad up
			foot.rotation = Vector3(0, 0, PI / 2.0) if absf(direction.x) > 0.5 \
				else Vector3(PI / 2.0, 0, 0)
		_brackets.append(foot)
	# All the clamp hardware of a run in one mesh.
	var merged := MeshMerge.merge_group(self, _brackets)
	_brackets.clear()
	for inst in merged:
		_brackets.append(inst)


func is_unsupported() -> bool:
	return _unsupported


func describe() -> String:
	# The support rule only speaks up when it fails.
	var tag := "" if service_label == "" else " · %s" % service_label
	var alarm := "\nUNSUPPORTED SPAN — add structure" if _unsupported else ""
	var keys := "E color/label · T sleeve, tray or conduit · X removes" if _style == "cable" else "E color/label · X removes"
	return "%s%s%s\n(%s)" % [_desc, tag, alarm, keys]


## What the run is doing: flowing, pressurised but still (a dead-headed
## discharge, a full riser under a stopped pump), or cold. A signal run
## only knows live or dead.
func _live_state() -> int:
	# Flowing at the speed a DN50 line shows 0.05 L/s at: a millimetre
	# line glows on microlitres.
	if _getter.call() > 0.05 * (_radius / 0.07) * (_radius / 0.07):
		return 2
	if _pressure_getter.is_valid() and _pressure_getter.call() > 5000.0:
		return 1
	return 0


func set_pressure_getter(getter: Callable) -> void:
	_pressure_getter = getter
	_repaint()


func _process(_delta: float) -> void:
	if _live_state() == _state:
		return
	_repaint()


func _repaint() -> void:
	_state = _live_state()
	var mat := _cold
	if _unsupported:
		mat = _bad
	elif _state == 2:
		mat = _hot
	elif _state == 1:
		mat = _charged
	for inst in _meshes:
		if is_instance_valid(inst):
			inst.material_override = mat
