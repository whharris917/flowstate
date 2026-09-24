class_name MeshMerge
## Fewer draw calls: a plant is bound by the draw calls of its
## furniture rather than by pixels. A view is built from
## hundreds of primitives, each its own mesh instance and its own
## draw; this bakes them into one mesh per look. What a view might
## later move, hide or repaint it holds in a member variable, so
## anything a script member refers to — a node, a material, a mesh,
## or an array or dictionary of them — is left alone, and everything
## else under the view is merged. A held Node3D that contains
## forgotten furniture (a tank's rebuilt shell) gets its own merged
## mesh under it, so freeing or moving the container still takes the
## furniture with it. Port fittings (meta port_name) and anything
## marked no_merge are never touched: the plant colours and grabs
## them. A mesh with children is not merged either, since freeing it
## would take them.

const MAX_DEPTH := 4


## Merge every forgotten single-surface mesh under root. Returns how
## many instances went away.
static func merge_view(root: Node3D) -> int:
	var held := _held(root)
	var groups: Dictionary = {}
	_collect(root, root, held, groups)
	return _build(groups, [])


## Merge a given list of mesh instances under parent, by look. Single
## survivors are returned unmerged, so the result is the whole list.
static func merge_group(parent: Node3D, nodes: Array) -> Array[MeshInstance3D]:
	var groups: Dictionary = {}
	for node in nodes:
		if node is MeshInstance3D:
			_add(node as MeshInstance3D, parent, groups, null)
	var out: Array[MeshInstance3D] = []
	_build(groups, out)
	return out


## Merge a given list into one mesh with one material, or null when
## there was nothing to merge.
static func merge_list(parent: Node3D, nodes: Array, mat: Material) -> MeshInstance3D:
	var groups: Dictionary = {}
	for node in nodes:
		if node is MeshInstance3D:
			_add(node as MeshInstance3D, parent, groups, mat)
	var out: Array[MeshInstance3D] = []
	if _build(groups, out) == 0:
		return null
	return out[0]


## The port fittings of a view as one mesh per look under the view
## (otherwise two draws a port).
## A fitting's body keeps its collision and its tag; its meshes join
## the view's. A movable fitting (a tank's nozzle) keeps its own. An
## earlier merged fitting mesh is a source again, so fittings attached
## in several calls accumulate; whoever frees the bodies (the cabinet
## sync) frees the merged meshes too, by their merged_markers meta.
static func merge_markers(view: Node3D) -> int:
	var groups: Dictionary = {}
	for child in view.get_children():
		if child.has_meta("merged_markers") and child is MeshInstance3D:
			_add(child as MeshInstance3D, view, groups, null)
		elif child.has_meta("port_name") and not child.has_meta("movable"):
			for inner in child.get_children():
				if inner is MeshInstance3D and inner.get_child_count() == 0:
					_add(inner as MeshInstance3D, view, groups, null)
	var out: Array = []
	var gone := _build(groups, out)
	for node in out:
		(node as Node).set_meta("merged_markers", true)
	return gone


## ---- the held set ---------------------------------------------------------

## Every object a script member of root refers to, directly or inside
## an array or dictionary: the parts the view will act on later.
static func _held(root: Node) -> Dictionary:
	var held: Dictionary = {}
	if root.get_script() == null:
		return held
	for prop: Dictionary in root.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		_refs(root.get(str(prop["name"])), held, 0)
	return held


static func _refs(value: Variant, held: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	if value is Object:
		held[value] = true
	elif value is Array:
		for item: Variant in value:
			_refs(item, held, depth + 1)
	elif value is Dictionary:
		for key: Variant in value:
			_refs((value as Dictionary)[key], held, depth + 1)


## ---- collecting -----------------------------------------------------------

## Walk under node. group_parent is the nearest ancestor that survives
## the merge and whose transform the merged mesh will live under: the
## root, or a held Node3D on the way down.
static func _collect(node: Node, group_parent: Node3D, held: Dictionary, groups: Dictionary) -> void:
	for child in node.get_children():
		if child.has_meta("port_name") or child.has_meta("no_merge"):
			continue
		var candidate := child is MeshInstance3D and not held.has(child) \
			and child.get_child_count() == 0 and (child as MeshInstance3D).visible
		if candidate:
			var inst := child as MeshInstance3D
			if inst.mesh == null or held.has(inst.mesh) or inst.mesh is ImmediateMesh \
					or inst.mesh.get_surface_count() != 1:
				candidate = false
			else:
				var mat := inst.get_active_material(0)
				if mat != null and held.has(mat):
					candidate = false
		if candidate:
			_add(child as MeshInstance3D, group_parent, groups, null)
			continue
		if child is Node3D and (held.has(child) or child is MeshInstance3D):
			# A held container, or a mesh that stays: its subtree lives
			# under it.
			_collect(child, child as Node3D, held, groups)
		else:
			_collect(child, group_parent, held, groups)


static func _add(inst: MeshInstance3D, parent: Node3D, groups: Dictionary, forced: Material) -> void:
	if inst.mesh == null or inst.mesh.get_surface_count() != 1:
		return
	var mat: Material = forced if forced != null else inst.get_active_material(0)
	var look := ("forced:" + str(forced.get_instance_id())) if forced != null \
		else (DrawCensus._look(mat) if mat != null else "none")
	var key := "%d|%s|%d" % [parent.get_instance_id(), look, int(inst.cast_shadow)]
	if not groups.has(key):
		groups[key] = {"parent": parent, "mat": mat, "cast": inst.cast_shadow, "items": [], "nodes": []}
	var group: Dictionary = groups[key]
	(group["items"] as Array).append([inst.mesh, _relative(inst, parent)])
	(group["nodes"] as Array).append(inst)


## The transform of node in the space of ancestor, composed up the
## tree, so it is right whether or not the tree is in a scene yet.
static func _relative(node: Node3D, ancestor: Node) -> Transform3D:
	var xf := node.transform
	var up: Node = node.get_parent()
	while up != null and up != ancestor:
		if up is Node3D:
			xf = (up as Node3D).transform * xf
		up = up.get_parent()
	return xf


## ---- building -------------------------------------------------------------

## One mesh per group of two or more; singles are left as they are
## (and listed in out, so a caller's list stays whole). Returns how
## many instances went away.
static func _build(groups: Dictionary, out: Array) -> int:
	var gone := 0
	for key: String in groups:
		var group: Dictionary = groups[key]
		var nodes: Array = group["nodes"]
		if nodes.size() < 2:
			for node in nodes:
				out.append(node)
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var expected := 0
		for item: Array in group["items"]:
			var source := _indexed(item[0])
			expected += _triangles(source)
			st.append_from(source, 0, item[1])
		var inst := MeshInstance3D.new()
		inst.mesh = st.commit()
		# Every source triangle must come out the other side, or lost
		# geometry vanishes silently.
		var got := _triangles(inst.mesh)
		if got != expected:
			push_error("MeshMerge: merged %d triangles of %d under %s" % [got, expected,
				(group["parent"] as Node).name])
		inst.material_override = group["mat"]
		inst.cast_shadow = group["cast"]
		# Every shadow cascade draws every caster again; a fitting or a
		# bracket the size of a hand throws no shadow anyone sees.
		var extent := inst.mesh.get_aabb().size
		if maxf(extent.x, maxf(extent.y, extent.z)) < 0.35:
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.set_meta("merged", true)
		# The pieces it was made of, each [mesh, transform]: the player
		# collides with each piece's own hull (PlantSolids).
		inst.set_meta("sources", group["items"])
		var parent := group["parent"] as Node3D
		parent.add_child(inst)
		for node in nodes:
			_free(node as Node, parent)
		out.append(inst)
		gone += nodes.size() - 1
	return gone


## Triangles in a mesh's first surface, from its arrays.
static func _triangles(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() < 1:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	if idx != null and not (idx as PackedInt32Array).is_empty():
		@warning_ignore("integer_division")
		return (idx as PackedInt32Array).size() / 3
	@warning_ignore("integer_division")
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## A source with an index array, always. SurfaceTool.append_from copies
## a source's vertices and its indices; once the tool has any indices,
## only indexed vertices are drawn, so a non-indexed source (a swept
## elbow built by SurfaceTool) appended after an indexed primitive
## would vanish.
static func _indexed(mesh: Mesh) -> Mesh:
	var arrays := mesh.surface_get_arrays(0)
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	if idx != null and not (idx as PackedInt32Array).is_empty():
		return mesh
	var tool := SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.index()
	return tool.commit()


## Free a merged source, and the plain Node3D it may have been the
## only child of (a pipe segment's root), never the group's parent.
static func _free(node: Node, keep: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()
	if parent != null and parent != keep and parent.get_child_count() == 0 \
			and parent.get_class() == "Node3D" and parent.get_script() == null \
			and parent.get_meta_list().is_empty():
		_free(parent, keep)
