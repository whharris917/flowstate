class_name DrawCensus
## Where the draw calls come from (director, 2026-09-13: "we need to
## reduce draw calls for the showcase"): a walk over every visual
## instance in a world, counted by what owns it — a run, a structure,
## an equipment view by its class, the forest, the landscape, labels,
## the world's own walls and pads — with the surfaces each draws, and
## how many distinct materials there are against how many distinct
## looks. The headless report prints it so a smoke run says which
## merge would pay before anyone merges.


static func report(world: WorldBase) -> Array[String]:
	var plant := world.plant
	var owners: Dictionary = {}   # node -> category
	if plant != null:
		for record_name: String in plant.views:
			var view: Node = plant.views[record_name]
			var script: Script = view.get_script()
			owners[view] = "view " + (script.get_global_name() if script != null else view.get_class())
		for run_name: String in plant.runs:
			var node: Variant = plant.runs[run_name].get("node")
			if node is Node:
				owners[node] = "run"
		for structure_name: String in plant.structures:
			var node: Variant = plant.structures[structure_name].get("node")
			if node is Node:
				owners[node] = "structure " + str(plant.structures[structure_name].get("type", "?"))
	var counts: Dictionary = {}     # category -> [instances, surfaces]
	var rids: Dictionary = {}
	var looks: Dictionary = {}
	var totals := [0, 0]
	_walk(world, world, owners, counts, rids, looks, totals)
	var names: Array = counts.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(counts[a][1]) > int(counts[b][1]))
	var lines: Array[String] = []
	lines.append("[flowstate] draw census: %d visual instances, %d surfaces, %d materials (%d distinct looks)"
		% [totals[0], totals[1], rids.size(), looks.size()])
	for category: String in names:
		lines.append("    %-34s %6d instances %7d surfaces" % [category, int(counts[category][0]), int(counts[category][1])])
	return lines


static func _walk(node: Node, world: Node, owners: Dictionary, counts: Dictionary,
		rids: Dictionary, looks: Dictionary, totals: Array) -> void:
	if node is VisualInstance3D and not (node is Light3D) and (node as VisualInstance3D).visible:
		var surfaces := 0
		var category := _category(node, world, owners)
		if node is MeshInstance3D:
			var inst := node as MeshInstance3D
			if inst.mesh != null and inst.visible:
				surfaces = inst.mesh.get_surface_count()
				for s in surfaces:
					var mat: Material = inst.get_active_material(s)
					if mat != null:
						rids[mat.get_rid()] = true
						looks[_look(mat)] = true
		elif node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				surfaces = mm.mesh.get_surface_count()
		elif node is Label3D:
			surfaces = 1
			category = "label"
		else:
			surfaces = 1
		if surfaces > 0:
			if not counts.has(category):
				counts[category] = [0, 0]
			counts[category][0] += 1
			counts[category][1] += surfaces
			totals[0] += 1
			totals[1] += surfaces
	for child in node.get_children():
		_walk(child, world, owners, counts, rids, looks, totals)


static func _category(node: Node, world: Node, owners: Dictionary) -> String:
	var up: Node = node
	while up != null and up != world:
		if owners.has(up):
			return str(owners[up])
		if up is Forest:
			return "forest"
		if up is Landscape:
			return "landscape"
		up = up.get_parent()
	# Straight under the world: the hall, the pads, the gallery, the sky.
	var top: Node = node
	while top != null and top.get_parent() != world and top.get_parent() != null:
		top = top.get_parent()
	return "world " + (top.name if top != null else "?")


## What a material looks like, so materials that are the same to the
## eye count once: the merge that follows can share them.
static func _look(mat: Material) -> String:
	if mat is StandardMaterial3D:
		var m := mat as StandardMaterial3D
		return "%s|%.3f|%.3f|%d|%d|%s|%.2f|%d|%d|%.2f|%s" % [m.albedo_color.to_html(), m.metallic,
			m.roughness, int(m.transparency), int(m.emission_enabled), m.emission.to_html(),
			m.emission_energy_multiplier, int(m.cull_mode), int(m.clearcoat_enabled), m.anisotropy,
			"n" if m.normal_texture != null else "-"]
	if mat is ShaderMaterial:
		return "shader:" + str((mat as ShaderMaterial).shader.resource_path if (mat as ShaderMaterial).shader != null else mat.get_rid())
	return str(mat.get_rid())
