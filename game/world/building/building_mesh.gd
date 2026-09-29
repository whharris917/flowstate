class_name BuildingMesh
extends Node3D
## A real building as generated and checked by tools/building/build.py:
## its visible surface, finished, in world metres (a .bld file). Drawn
## in two meshes (the fabric in the town wall shader, the glass) and
## solid to the player everywhere but its door leaves, which stand open.
## Art only: no records.

var stats: Dictionary = {}
## Whether the file was written from a building that failed its checks.
var broken := false


static func open(path: String) -> BuildingMesh:
	var b := BuildingMesh.new()
	b.name = "Building_" + path.get_file().get_basename()
	b._load(path)
	return b


func _load(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("BuildingMesh: cannot open %s" % path)
		return
	if f.get_buffer(4).get_string_from_ascii() != "BLD1":
		push_error("BuildingMesh: %s is not a building file" % path)
		return
	broken = (f.get_32() & 1) != 0
	var count := f.get_32()
	var sets: Array = []                 # per surface: [verts, normals, colours]
	for i in 3:
		sets.append([PackedVector3Array(), PackedVector3Array(), PackedColorArray()])
	var solid := PackedVector3Array()
	var tris := 0
	for i in count:
		var surface := f.get_8()
		var col := Color(f.get_8() / 255.0, f.get_8() / 255.0, f.get_8() / 255.0, f.get_8() / 255.0)
		var n := Vector3(f.get_float(), f.get_float(), f.get_float())
		var k := f.get_16()
		var pts := PackedVector3Array()
		var c := Vector3.ZERO
		for j in k:
			var p := Vector3(f.get_float(), f.get_float(), f.get_float())
			pts.append(p)
			c += p
		c /= float(k)
		var s: Array = sets[surface]
		var v: PackedVector3Array = s[0]
		var nn: PackedVector3Array = s[1]
		var cc: PackedColorArray = s[2]
		# fanned from the centre, wound clockwise as Godot draws the front
		for j in k:
			var a := pts[j]
			var b := pts[(j + 1) % k]
			v.append(c)
			v.append(b)
			v.append(a)
			for m in 3:
				nn.append(n)
				cc.append(col)
			if surface != 2:
				solid.append(c)
				solid.append(b)
				solid.append(a)
			tris += 1
		s[0] = v
		s[1] = nn
		s[2] = cc
	var wall := ShaderMaterial.new()
	wall.shader = load("res://world/town_wall.gdshader")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.50, 0.56, 0.58, 0.18)
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mats := [wall, glass, wall]
	var names := ["fabric", "glass", "doors"]
	for i in 3:
		var s: Array = sets[i]
		if (s[0] as PackedVector3Array).is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_COLOR] = s[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = names[i]
		mi.mesh = mesh
		mi.material_override = mats[i]
		if i == 1:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cps := ConcavePolygonShape3D.new()
	cps.backface_collision = true
	cps.set_faces(solid)
	shape.shape = cps
	body.add_child(shape)
	add_child(body)
	stats = {"faces": count, "triangles": tris, "ms": Time.get_ticks_msec() - t0}
	if broken:
		push_warning("BuildingMesh: %s was written from a building that fails its checks" % path)
