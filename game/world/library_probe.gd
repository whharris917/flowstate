extends Node
## Debug harness: opens the equipment library and screenshots a few
## pages, then walks every page to check that none of them is missing
## prose, an equation, or a meaning for one of its real ports.
##
## Run windowed: godot --path game res://world/library_probe.tscn


func _ready() -> void:
	MouseMode.probe = true
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(2.5).timeout
	var base := world as WorldBase
	var library := base.library
	library.visible = true

	# A process unit, a separation unit, and a controller: three pages
	# with quite different shapes.
	for entry: Array in [["reactor", "probe_library_reactor.png"],
			["still", "probe_library_still.png"],
			["controller", "probe_library_pid.png"]]:
		var index := library._types.find(str(entry[0]))
		if index >= 0:
			library._selected = index
			library._refresh()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://" + str(entry[1]))

	# Now audit every page against the live records.
	var missing_prose: Array[String] = []
	var missing_meaning: Array[String] = []
	var missing_equations: Array[String] = []
	for type_id in library._types:
		if SimLibrary.tier_of(type_id) == "undocumented":
			missing_prose.append(type_id)
			continue
		# An enclosure has no equations because it has no behaviour of
		# its own; only things with ports are expected to have any.
		if SimLibrary.has_record(type_id) and SimLibrary.equations_of(type_id).is_empty():
			missing_equations.append(type_id)
		for row: Dictionary in SimLibrary.port_rows(type_id):
			if str(row["meaning"]) == "":
				missing_meaning.append("%s.%s" % [type_id, row["name"]])
	print("[probe] library: %d pages" % library._types.size())
	print("[probe] undocumented types: %s" % (
		"none" if missing_prose.is_empty() else ", ".join(missing_prose)))
	print("[probe] pages without equations: %s" % (
		"none" if missing_equations.is_empty() else ", ".join(missing_equations)))
	print("[probe] ports without a meaning: %s" % (
		"none" if missing_meaning.is_empty() else ", ".join(missing_meaning)))
	print("[probe] library screenshots written to user://")
	get_tree().quit()
